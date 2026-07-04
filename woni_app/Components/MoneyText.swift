import SwiftUI

/// Figma element_money — 지출은 Terracotta, 수입은 Olive로 색이 고정된 금액 텍스트.
struct MoneyText: View {
    let amount: Decimal
    let tone: AmountTone
    var style: WoniTypography = .body3

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter
    }()

    var body: some View {
        Text(Self.formatter.string(for: amount) ?? "\(amount)")
            .woniFont(style)
            .foregroundStyle(tone == .expense ? WoniColor.terracotta100 : WoniColor.olive100)
    }
}
