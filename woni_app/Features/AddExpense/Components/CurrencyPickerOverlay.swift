import SwiftUI

struct CurrencyPickerOverlay: View {
    @Binding var selection: String
    @Binding var isPresented: Bool
    let options: [SelectableCurrency]
    let language: AppLanguage
    let accentColor: Color

    @State private var isExpanded = false
    /// 닫는 동안 시트 기하를 손 뗀 위치에 고정한다. 고정하지 않으면 드래그 값이 풀리는 사이
    /// 시트가 제자리로 되돌아가는 궤적 위에서 사라진다. 닫히는 중(`isPresented == false`)에만
    /// 쓰므로, 제거 도중 시트가 다시 열려 이 상태가 살아남아도 그 값은 버려진다.
    @State private var dismissTranslation: CGFloat?
    /// 손을 뗄 때 0으로 돌아가는 이 리셋 자체가 제자리 복귀 동작이다. onEnded의 withAnimation은
    /// 리셋을 감싸지 못하므로, 애니메이션을 여기 리셋 트랜잭션에 걸어야 툭 끊기지 않는다.
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.25)))
    private var dragTranslation: CGFloat = 0

    static let compactListHeight: CGFloat = 600
    static let expandThreshold: CGFloat = 40
    static let dismissThreshold: CGFloat = 100

    private let handleAreaHeight: CGFloat = 29
    private let rowHeight: CGFloat = 52

    /// 드래그 중 시트 기하. 리스트 높이는 축소 하한까지만 줄고, 하한을 넘어선 몫은 시트 전체를
    /// 아래로 미는 거리가 된다 — 그래서 축소 상태에서도 손가락을 따라 내려간다.
    /// 확장 높이가 하한보다 작은 소형 화면에서 기준이 갈리지 않도록 하한 자체를 클램프한다.
    static func sheetGeometry(
        isExpanded: Bool,
        expandedListHeight: CGFloat,
        dragTranslation: CGFloat
    ) -> (listHeight: CGFloat, offset: CGFloat) {
        let minHeight = min(compactListHeight, expandedListHeight)
        let rawHeight = (isExpanded ? expandedListHeight : minHeight) - dragTranslation
        return (min(expandedListHeight, max(minHeight, rawHeight)), max(0, minHeight - rawHeight))
    }

    enum DragOutcome {
        case dismiss
        case expand
        case collapse
        case stay
    }

    /// 손을 뗐을 때의 결과. 닫기는 드래그 거리가 아니라 축소 하한 아래로 밀려난 거리로 판정한다 —
    /// 그래야 확장 상태에서도 축소를 거쳐 닫기까지 한 제스처로 이어진다.
    static func dragOutcome(
        isExpanded: Bool,
        expandedListHeight: CGFloat,
        dragTranslation: CGFloat
    ) -> DragOutcome {
        let geometry = sheetGeometry(
            isExpanded: isExpanded,
            expandedListHeight: expandedListHeight,
            dragTranslation: dragTranslation
        )
        if geometry.offset > dismissThreshold {
            return .dismiss
        }
        if dragTranslation < -expandThreshold {
            return .expand
        }
        if dragTranslation > expandThreshold {
            return .collapse
        }
        return .stay
    }

    private var topSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            let expandedListHeight = proxy.size.height - handleAreaHeight - topSafeAreaInset
            let geometry = Self.sheetGeometry(
                isExpanded: isExpanded,
                expandedListHeight: expandedListHeight,
                dragTranslation: isPresented ? dragTranslation : dismissTranslation ?? dragTranslation
            )

            ZStack(alignment: .bottom) {
                WoniColor.gray100.opacity(0.6)
                    .onTapGesture {
                        isPresented = false
                    }

                VStack(spacing: 0) {
                    Capsule()
                        .fill(WoniColor.base20)
                        .frame(width: 40, height: 5)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(expandedListHeight: expandedListHeight))

                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                    row(for: option, isLast: index == options.count - 1)
                                        .id(option.id)
                                }
                            }
                        }
                        .accessibilityIdentifier("currencyPicker.list")
                        .onAppear {
                            guard let selectedOption = options.first(where: { $0.rawValue == selection }) else {
                                return
                            }
                            // 첫 onAppear 시점엔 행 앵커 등록 전이라 scrollTo가 무시될 수 있어 다음 런루프로 미룬다.
                            DispatchQueue.main.async {
                                scrollProxy.scrollTo(selectedOption.id, anchor: .center)
                            }
                        }
                        .frame(height: geometry.listHeight)
                    }
                }
                .background(WoniColor.gray00)
                .clipShape(.rect(topLeadingRadius: 24, topTrailingRadius: 24))
                .offset(y: geometry.offset)
                .transition(.move(edge: .bottom))
            }
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) {
                isPresented = false
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}

private extension CurrencyPickerOverlay {
    func dragGesture(expandedListHeight: CGFloat) -> some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let outcome = Self.dragOutcome(
                    isExpanded: isExpanded,
                    expandedListHeight: expandedListHeight,
                    dragTranslation: value.translation.height
                )
                if case .dismiss = outcome {
                    // 제거보다 먼저, 애니메이션 밖에서 기하를 굳힌다.
                    dismissTranslation = value.translation.height
                }
                withAnimation(.easeOut(duration: 0.25)) {
                    switch outcome {
                    case .dismiss:
                        isPresented = false
                    case .expand:
                        isExpanded = true
                    case .collapse:
                        isExpanded = false
                    case .stay:
                        break
                    }
                }
            }
    }

    func row(for option: SelectableCurrency, isLast: Bool) -> some View {
        let isSelected = option.rawValue == selection
        return Button {
            selection = option.rawValue
            isPresented = false
        } label: {
            HStack(spacing: 12) {
                Text(option.displayName(language))
                    .woniFont(.body1)
                    .foregroundStyle(WoniColor.gray100)
                Text("/")
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.base30)
                Text(option.rawValue)
                    .woniFont(.body1)
                    .foregroundStyle(WoniColor.gray100)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(accentColor)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity)
            .background(isSelected ? WoniColor.base15 : WoniColor.gray00)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(WoniColor.base20).frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(option.displayName(language)), \(option.rawValue)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
