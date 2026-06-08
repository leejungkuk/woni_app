import SwiftUI

public struct PaymentSection: View {
    let selectedMethod: PaymentMethod?
    let palette: AccentPalette
    let onSelect: (PaymentMethod) -> Void

    public init(selectedMethod: PaymentMethod?, palette: AccentPalette, onSelect: @escaping (PaymentMethod) -> Void) {
        self.selectedMethod = selectedMethod
        self.palette = palette
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "PROPERTY", trailingTitle: "Edit", trailingAction: {})

            FlowLayout(spacing: 8) {
                ForEach(PaymentMethod.allCases) { method in
                    ChipButton(
                        label: method.label,
                        isSelected: selectedMethod == method,
                        palette: palette,
                        action: { onSelect(method) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PaymentSection(selectedMethod: .creditCard, palette: .terracotta, onSelect: { _ in })
        .padding()
}
