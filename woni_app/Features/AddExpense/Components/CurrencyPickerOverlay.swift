import SwiftUI

struct CurrencyPickerOverlay: View {
    @Binding var selection: String
    @Binding var isPresented: Bool
    let options: [SelectableCurrency]
    let language: AppLanguage
    let accentColor: Color

    @State private var isExpanded = false
    @GestureState private var dragTranslation: CGFloat = 0

    private let compactListHeight: CGFloat = 400
    private let handleAreaHeight: CGFloat = 29
    private let rowHeight: CGFloat = 48

    private var topSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            let expandedListHeight = proxy.size.height - handleAreaHeight - topSafeAreaInset
            let baseHeight = isExpanded ? expandedListHeight : compactListHeight
            let listHeight = min(expandedListHeight, max(compactListHeight, baseHeight - dragTranslation))

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
                        .gesture(dragGesture)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                row(for: option, isLast: index == options.count - 1)
                            }
                        }
                    }
                    .frame(height: listHeight)
                }
                .background(WoniColor.gray00)
                .clipShape(.rect(topLeadingRadius: 24, topTrailingRadius: 24))
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}

private extension CurrencyPickerOverlay {
    var dragGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                withAnimation(.easeOut(duration: 0.25)) {
                    if value.translation.height < -40 {
                        isExpanded = true
                    } else if value.translation.height > 40 {
                        isExpanded = false
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
                Text(option.flag)
                    .font(.system(size: 22))
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
            .background(isSelected ? WoniColor.base20 : WoniColor.gray00)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(WoniColor.base20).frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
