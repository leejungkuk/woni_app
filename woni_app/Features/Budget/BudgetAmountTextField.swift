//
//  BudgetAmountTextField.swift
//  woni_app
//

import SwiftUI
import UIKit

/// 예산 금액 칸(스펙 §2.4). `AmountTextField` 와 같은 이유로 UIKit 으로 감싼다 — `shouldChangeCharactersIn` 에서
/// 글자를 확정하고 `false` 를 돌려줘야 사후 재작성이 다음 키를 잃지 않는다(`AmountTextField.swift` 머리 주석).
/// 거래 칸과 달리 값이 `Decimal?`(빈칸 = 몫 없음)이고, 키 하나의 글자·값은 `BudgetAmountInput` 이 정한다.
///
/// 표시와 편집을 나눈다 — 포커스가 없으면 `displayAmount` 를 그리고, 포커스가 있는 동안은 칸이 글자를 쥔다.
/// 다 지운 전체 칸은 벗어날 때까지 갈래 A 의 빈칸이라 새로 칠 수 있고, 벗어난 뒤에야 카테고리 합(갈래 B)을 그린다
/// (`BudgetEditDraft.endTotalEditing()`).
struct BudgetAmountTextField: UIViewRepresentable {
    enum Style {
        /// 전체 칸 — h2 가운데(큰 금액).
        case total
        /// 금액 줄 — body2 오른쪽 정렬.
        case line

        var typography: WoniTypography {
            switch self {
            case .total: .h2
            case .line: .body2
            }
        }
    }

    /// 키 하나를 반영한 새 값을 넘긴다(전체 칸이면 T). false 면 글자를 확정하지 않는다 — 칸 밖의 판정
    /// (카테고리 합 상한 등)이 거절한 키가 칸 글자에만 남아 초안과 어긋나지 않게.
    let onAmountChange: (Decimal?) -> Bool
    /// 결제수단·카테고리 "최대 N" 은 입력 중인 칸 아래에만 뜬다.
    @Binding var isFocused: Bool
    /// 포커스가 없을 때 칸에 보일 값(전체 칸은 갈래의 전체 — A 는 T, B 는 S — 줄 칸은 그 줄 금액).
    let displayAmount: Decimal?
    let decimalPlaces: Int
    let style: Style
    let isEnabled: Bool
    let accessibilityIdentifier: String
    /// VoiceOver 가 빈칸을 읽는 말 — "예산 없음"/"No budget".
    let emptyAccessibilityValue: String
    let onLimitExceeded: () -> Void
    /// 칸을 벗어남 — 전체 칸은 비운 채 벗어나면 갈래를 다시 정하고, 카테고리 칸은 넘는 입력 경고를 끈다.
    /// 값이 있는 전체는 카테고리 합보다 작아도 맞추지 않는다.
    let onEditingEnded: () -> Void
    /// 잠긴 칸(갈래 B 의 전체)을 누름 — 칸은 편집을 시작하지 않는다. nil 이면 잠기지 않았다.
    var onLockedTap: (() -> Void)?

    func makeUIView(context: Context) -> BudgetAmountUITextField {
        let field = BudgetAmountUITextField()
        field.delegate = context.coordinator
        field.keyboardType = .numberPad
        field.textAlignment = style == .total ? .center : .right
        // `woniFont` 는 Dynamic Type 을 따르지 않는다(백로그 D-006) — 거래 칸과 같이 칸도 고정 크기로 둔다.
        field.font = UIFont(name: WoniFontFamily.regular, size: style.typography.fontSize)
        field.adjustsFontForContentSizeCategory = false
        field.textColor = UIColor(WoniColor.gray100)
        // 자리표시는 `BudgetAmountField` 의 SwiftUI Text 가 그린다. `UITextField.placeholder` 를 채우면
        // XCUITest 가 빈 칸의 value 로 자리표시를 돌려준다.
        field.text = BudgetAmountInput.text(for: displayAmount, decimalPlaces: decimalPlaces)
        return field
    }

    func updateUIView(_ uiView: BudgetAmountUITextField, context: Context) {
        context.coordinator.parent = self
        uiView.isEnabled = isEnabled
        uiView.accessibilityIdentifier = accessibilityIdentifier
        uiView.emptyAccessibilityValue = emptyAccessibilityValue

        // 편집 중에는 코디네이터가 글자를 쥔다 — 밖의 값으로 덮지 않는다.
        if !uiView.isFirstResponder {
            Self.show(displayAmount, in: uiView, decimalPlaces: decimalPlaces)
        }

        // 포커스 요청·해제는 `AmountTextField.updateUIView` 와 같다 — 같은 사이클에 바인딩을 쓰지 않게 다음 런루프로
        // 미루고, 실행 시점에 상태를 다시 읽는다.
        let coordinator = context.coordinator
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard coordinator.parent.isFocused, !uiView.isFirstResponder else {
                    return
                }
                uiView.becomeFirstResponder()
            }
        } else if !isFocused, uiView.isFirstResponder {
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

    static func show(_ amount: Decimal?, in field: UITextField, decimalPlaces: Int) {
        let text = BudgetAmountInput.text(for: amount, decimalPlaces: decimalPlaces)
        if field.text != text {
            field.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: BudgetAmountTextField

        init(parent: BudgetAmountTextField) {
            self.parent = parent
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let commit = BudgetAmountInput.commit(
                string,
                in: range,
                of: textField.text ?? "",
                decimalPlaces: parent.decimalPlaces,
                accept: parent.onAmountChange
            )
            switch commit {
            case let .accepted(text):
                // 글자가 그대로인 키(숫자 없는 글 등)는 칸을 건드리지 않는다 — 고른 범위를 그대로 둔다.
                if text != textField.text {
                    textField.text = text
                    // 글자 길이가 쉼표·오른쪽부터 채우기로 매번 바뀌어 원래 캐럿 위치가 뜻을 잃는다.
                    AmountTextField.moveCaretToEnd(textField)
                }
            case .overLimit:
                parent.onLimitExceeded()
            case .rejected:
                break
            }
            return false
        }

        /// 잠긴 칸은 편집을 시작하지 않고 알리기만 한다 — 키보드가 뜨지 않는다. `isEnabled = false` 로 막지 않는다 —
        /// VoiceOver 가 "흐리게"로 읽고 활성화가 되지 않는다. 손가락 누름도 VoiceOver 활성화도 `becomeFirstResponder` 를
        /// 거쳐 이 한 곳으로 온다.
        func textFieldShouldBeginEditing(_: UITextField) -> Bool {
            guard let onLockedTap = parent.onLockedTap else {
                return true
            }
            onLockedTap()
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
            AmountTextField.keepCaretAtEnd(textField)
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            AmountTextField.keepCaretAtEnd(textField)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
            parent.onEditingEnded()
            BudgetAmountTextField.show(parent.displayAmount, in: textField, decimalPlaces: parent.decimalPlaces)
        }
    }
}

/// 빈칸이면 VoiceOver 에 글자 대신 `emptyAccessibilityValue` 를 읽힌다.
final class BudgetAmountUITextField: UITextField {
    var emptyAccessibilityValue = ""

    override var accessibilityValue: String? {
        get {
            (text ?? "").isEmpty ? emptyAccessibilityValue : super.accessibilityValue
        }
        set {
            super.accessibilityValue = newValue
        }
    }
}

/// 예산 금액 칸 + 자리표시. 빈칸이면 전체 칸은 회색 0(거래 입력 칸과 같은 말), 금액 줄은 "예산 없음"을
/// `gray40` 으로 겹쳐 그린다(UI_GUIDE 입력 규칙). 자리표시는 칸이 읽으므로 VoiceOver 에서 뺀다.
struct BudgetAmountField: View {
    let onAmountChange: (Decimal?) -> Bool
    @Binding var isFocused: Bool
    let displayAmount: Decimal?
    let decimalPlaces: Int
    let style: BudgetAmountTextField.Style
    let isEnabled: Bool
    let accessibilityIdentifier: String
    let emptyAccessibilityValue: String
    let onLimitExceeded: () -> Void
    let onEditingEnded: () -> Void
    /// 잠긴 칸(갈래 B 의 전체)을 누름. nil 이면 잠기지 않았다.
    var onLockedTap: (() -> Void)?

    /// 이번 편집에서 마지막으로 받아들인 키가 칸을 비웠는지. 키를 치기 전에는 nil 이다.
    /// 편집 중 자리표시는 칸이 쥔 글자를 따른다 — 칸 글자를 바깥 값으로 다시 그리지 않는 것(`BudgetAmountTextField`)과 같다.
    @State private var isEditingEmpty: Bool?

    private var showsPlaceholder: Bool {
        isFocused ? (isEditingEmpty ?? (displayAmount == nil)) : (displayAmount == nil)
    }

    private var placeholder: String {
        switch style {
        case .total:
            BudgetAmountInput.text(for: 0, decimalPlaces: decimalPlaces)
        case .line:
            // 줄 칸의 자리표시와 VoiceOver 가 읽는 말은 같은 "예산 없음"이다(UI_GUIDE en 표).
            emptyAccessibilityValue
        }
    }

    var body: some View {
        ZStack(alignment: style == .total ? .center : .trailing) {
            if showsPlaceholder {
                Text(placeholder)
                    .woniFont(style.typography)
                    .foregroundStyle(WoniColor.gray40)
                    .accessibilityHidden(true)
            }
            BudgetAmountTextField(
                onAmountChange: { amount in
                    guard onAmountChange(amount) else {
                        return false
                    }
                    isEditingEmpty = amount == nil
                    return true
                },
                isFocused: $isFocused,
                displayAmount: displayAmount,
                decimalPlaces: decimalPlaces,
                style: style,
                isEnabled: isEnabled,
                accessibilityIdentifier: accessibilityIdentifier,
                emptyAccessibilityValue: emptyAccessibilityValue,
                onLimitExceeded: onLimitExceeded,
                onEditingEnded: {
                    isEditingEmpty = nil
                    onEditingEnded()
                },
                onLockedTap: onLockedTap
            )
            // `woniFont` 가 붙이는 세로 여백을 같은 값으로 재현해 자리표시와 높이를 맞춘다.
            .padding(.vertical, style.typography.lineSpacing / 2)
            .frame(maxWidth: .infinity)
        }
    }
}
