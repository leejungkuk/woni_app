import SwiftUI

public struct ExchangeRateLine: View {
    let baseCurrency: String
    let targetCurrency: String
    let rate: Decimal
    let baseAmount: Decimal

    public init(baseCurrency: String, targetCurrency: String, rate: Decimal, baseAmount: Decimal) {
        self.baseCurrency = baseCurrency
        self.targetCurrency = targetCurrency
        self.rate = rate
        self.baseAmount = baseAmount
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }

    private var formattedRate: String {
        let rateString = numberFormatter.string(from: rate as NSDecimalNumber) ?? "0.00"
        return "\(baseCurrency) 1.00 = \(targetCurrency) \(rateString)"
    }

    private var formattedAmount: String {
        let amountString = numberFormatter.string(from: baseAmount as NSDecimalNumber) ?? "0.00"
        return "\(baseCurrency) \(amountString)"
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(formattedRate)

            Circle()
                .fill(Color.Woni.gray20)
                .frame(width: 4, height: 4)

            Text(formattedAmount)
        }
        .font(.woni(.small1))
        .foregroundColor(Color.Woni.gray80)
    }
}

#Preview {
    ExchangeRateLine(
        baseCurrency: "KRW",
        targetCurrency: "JPY",
        rate: 0.1,
        baseAmount: 999_999.00
    )
}
