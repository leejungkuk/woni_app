import SwiftUI
import UIKit

/// 금액 입력 전용 UITextField 랩.
///
/// **왜 UIKit인가** — SwiftUI `TextField` + `onChange` 조합은 입력이 반영된 **뒤** 텍스트를 다시 쓰는
/// 구조라(콤마 그룹핑·cents-first 재해석), 그 사후 재작성이 OS 키보드 파이프라인의 다음 키 입력과
/// 경합해 키가 유실됐다. 실측: `testC7ZeroDecimalCurrencyRejectsFractionInput` 단독 실행 3회 중 2회
/// 실패했고 실패 값은 "1,000"이었다(기대 "10,005" — 마지막 5 유실).
/// `shouldChangeCharactersIn`에서 입력이 반영되기 **전에** 최종 문자열을 확정하고 `false`를 돌려주면
/// 사후 재작성이 사라져 이 경합 계열이 원천 제거된다.
struct AmountTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var amount: Decimal
    @Binding var isFocused: Bool
    let currencyCode: String
    let onMaximumAmountExceeded: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .numberPad
        field.textAlignment = .center
        // `woniFont(.h2)`는 `.custom(_:fixedSize:)`라 Dynamic Type을 따르지 않는다(백로그 D-006).
        // 랩도 같은 고정 크기로 둔다 — 이 필드만 확대되면 나머지 문구와 어긋나 기존 레이아웃이 달라진다.
        field.font = UIFont(name: WoniFontFamily.regular, size: WoniTypography.h2.fontSize)
        field.adjustsFontForContentSizeCategory = false
        field.textColor = UIColor(WoniColor.gray100)
        // placeholder는 상위의 SwiftUI Text 오버레이가 그린다. `UITextField.placeholder`를 채우면
        // XCUITest가 빈 필드의 value로 placeholder 문자열을 돌려줘 `value == ""` 단언이 깨진다.
        field.accessibilityIdentifier = "entry.amount"
        field.text = text
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self

        // 통화 전환·외부 amount 리셋처럼 SwiftUI 쪽에서 텍스트가 바뀐 경우만 반영한다.
        // 타이핑 경로는 코디네이터가 이미 필드에 직접 썼으므로 여기서 다시 건드리지 않는다.
        if uiView.text != text {
            uiView.text = text
            Self.moveCaretToEnd(uiView)
        }

        // 뷰 갱신 도중 becomeFirstResponder를 부르면 델리게이트가 같은 사이클에서 isFocused
        // 바인딩을 써 버린다 → 다음 런루프로 미룬다.
        // 실행 시점에 상태를 다시 읽는다 — 미룬 사이 델리게이트가 isFocused를 바꿨으면(방금 탭해 잡은 포커스 등)
        // 묵은 결정으로 되돌리지 않는다.
        let coordinator = context.coordinator
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard coordinator.parent.isFocused, !uiView.isFirstResponder else {
                    return
                }
                uiView.becomeFirstResponder()
            }
        } else if !isFocused, uiView.isFirstResponder {
            // SwiftUI 쪽이 포커스를 내렸는데 필드가 아직 first responder면 직접 내린다 —
            // 응답자 체인 sendAction이 닿지 않는 기기·OS에서도 상태가 곧 키보드다.
            DispatchQueue.main.async {
                guard !coordinator.parent.isFocused, uiView.isFirstResponder else {
                    return
                }
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 표시 문자열은 콤마 삽입·cents-first 재해석으로 매번 길이가 달라져 원래 캐럿 위치가 의미를 잃는다.
    /// 그래서 항상 끝으로 보낸다.
    static func moveCaretToEnd(_ field: UITextField) {
        let end = field.endOfDocument
        field.selectedTextRange = field.textRange(from: end, to: end)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AmountTextField

        init(parent: AmountTextField) {
            self.parent = parent
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""
            guard let editedRange = Range(range, in: current) else {
                return false
            }

            let candidate = current.replacingCharacters(in: editedRange, with: string)
            guard
                let accepted = AmountInputSection.acceptedInput(
                    from: candidate,
                    currencyCode: parent.currencyCode
                )
            else {
                // 상한 초과는 필드를 그대로 둔 채(직전 유효 값 유지) 안내만 올린다.
                parent.onMaximumAmountExceeded()
                return false
            }

            let display = AmountInputSection.displayText(for: accepted, currencyCode: parent.currencyCode)
            textField.text = display
            AmountTextField.moveCaretToEnd(textField)

            parent.text = display
            parent.amount = accepted.amount
            return false
        }

        func textFieldDidBeginEditing(_: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_: UITextField) {
            parent.isFocused = false
        }
    }
}
