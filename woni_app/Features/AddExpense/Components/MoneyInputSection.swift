import SwiftUI

public struct MoneyInputSection: View {
    @Binding var amount: Decimal
    @State private var amountText: String = ""
    let currencyCode: String
    let baseCurrency: String
    let exchangeRate: Decimal?
    let baseAmount: Decimal?
    let palette: AccentPalette
    let onCurrencyTap: () -> Void

    public init(
        amount: Binding<Decimal>,
        currencyCode: String,
        baseCurrency: String = "KRW",
        exchangeRate: Decimal? = nil,
        baseAmount: Decimal? = nil,
        palette: AccentPalette,
        onCurrencyTap: @escaping () -> Void
    ) {
        _amount = amount
        self.currencyCode = currencyCode
        self.baseCurrency = baseCurrency
        self.exchangeRate = exchangeRate
        self.baseAmount = baseAmount
        self.palette = palette
        self.onCurrencyTap = onCurrencyTap
    }

    public var body: some View {
        VStack(spacing: 32) {
            CurrencySelectBox(currencyCode: currencyCode, palette: palette, action: onCurrencyTap)

            VStack(spacing: 4) {
                TextField("0", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.woni(.h2))
                    .foregroundColor(Color.Woni.gray100)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onChange(of: amountText) { _, newValue in
                        formatAndSyncAmount(from: newValue)
                    }
                    .onAppear {
                        if amount != 0 {
                            let formatter = NumberFormatter()
                            formatter.numberStyle = .decimal
                            formatter.usesGroupingSeparator = true
                            formatter.maximumFractionDigits = 2
                            if let formatted = formatter.string(from: amount as NSDecimalNumber) {
                                amountText = formatted
                            }
                        }
                    }

                if let rate = exchangeRate, let converted = baseAmount {
                    ExchangeRateLine(
                        baseCurrency: baseCurrency,
                        targetCurrency: currencyCode,
                        rate: rate,
                        baseAmount: converted
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatAndSyncAmount(from newValue: String) {
        var cleaned = newValue.replacingOccurrences(of: ",", with: "")
        let validCharacters = CharacterSet(charactersIn: "0123456789.")
        cleaned = String(cleaned.unicodeScalars.filter { validCharacters.contains($0) })

        let components = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        if components.count > 2 {
            cleaned = components[0] + "." + components[1]
        }

        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        let integerString = String(parts.first ?? "")
        var decimalString = parts.count > 1 ? String(parts[1]) : nil

        if let dec = decimalString, dec.count > 2 {
            decimalString = String(dec.prefix(2))
        }

        var formatted = ""
        if !integerString.isEmpty {
            if let decimalInt = Decimal(string: integerString) {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.usesGroupingSeparator = true
                formatter.maximumFractionDigits = 0
                formatted = formatter.string(from: decimalInt as NSDecimalNumber) ?? integerString
            } else {
                formatted = integerString
            }
        }

        if let dec = decimalString {
            formatted += "." + dec
        } else if cleaned.hasSuffix(".") {
            formatted += "."
        }

        if amountText != formatted {
            amountText = formatted
        }

        let stringForDecimal = cleaned.isEmpty || cleaned == "." ? "0" : cleaned
        if let decimalValue = Decimal(string: stringForDecimal) {
            amount = decimalValue
        } else {
            amount = 0
        }
    }
}

#Preview {
    MoneyInputSection(
        amount: .constant(999_999.00),
        currencyCode: "JPY",
        baseCurrency: "KRW",
        exchangeRate: 0.1,
        baseAmount: 99999.90,
        palette: .terracotta,
        onCurrencyTap: {}
    )
    .padding()
}
