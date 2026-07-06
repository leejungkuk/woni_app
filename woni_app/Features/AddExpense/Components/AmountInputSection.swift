import SwiftUI

struct AmountInputSection: View {
    @Binding var amount: Decimal
    let currencyCode: String
    let krwToForeignRate: Decimal?
    let convertedBaseAmount: Decimal?
    var accent: ChipButton.ChipAccent = .terracotta
    var onTapCurrency: () -> Void

    @State private var amountText = ""
    @FocusState private var isAmountFocused: Bool

    private var pillBackground: Color {
        accent == .terracotta ? WoniColor.terracotta20 : WoniColor.olive20
    }

    private var pillForeground: Color {
        accent == .terracotta ? WoniColor.terracotta110 : WoniColor.olive110
    }

    private var isForeignCurrency: Bool {
        currencyCode != SelectableCurrency.krw.rawValue
    }

    var body: some View {
        VStack(spacing: 16) {
            Button(action: onTapCurrency) {
                HStack(spacing: 4) {
                    Text(currencyCode)
                        .woniFont(.body1)
                        .foregroundStyle(pillForeground)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14))
                        .foregroundStyle(pillForeground)
                        .frame(width: 24, height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(pillBackground)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                ZStack {
                    if amountText.isEmpty {
                        Text("0")
                            .woniFont(.h2)
                            .foregroundStyle(isAmountFocused ? WoniColor.gray40 : WoniColor.gray100)
                    }
                    TextField("", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .woniFont(.h2)
                        .foregroundStyle(WoniColor.gray100)
                        .focused($isAmountFocused)
                        .onChange(of: amountText) { _, newValue in
                            formatAndSyncAmount(from: newValue, currencyCode: currencyCode)
                        }
                        .onChange(of: currencyCode) { _, newCode in
                            formatAndSyncAmount(from: amountText, currencyCode: newCode)
                        }
                        .onChange(of: amount) { _, newValue in
                            if newValue == 0, !amountText.isEmpty {
                                amountText = ""
                            }
                        }
                        .onAppear {
                            syncTextFromAmount()
                        }
                }

                if isForeignCurrency, let krwToForeignRate, let convertedBaseAmount {
                    let convertedText = CurrencyFormat.string(
                        convertedBaseAmount,
                        currencyCode: SelectableCurrency.krw.rawValue
                    )
                    HStack(spacing: 4) {
                        Text("KRW 1.00 = \(currencyCode) \(formatRate(krwToForeignRate))")
                        Circle().fill(WoniColor.gray20).frame(width: 2, height: 2)
                        Text("KRW \(convertedText)")
                    }
                    .woniFont(.small1)
                    .foregroundStyle(WoniColor.gray80)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

private extension AmountInputSection {
    func formatAndSyncAmount(from text: String, currencyCode: String) {
        let reformatted = Self.reformat(
            text,
            decimalPlaces: CurrencyFormat.decimalPlaces(for: currencyCode)
        )

        if reformatted != text {
            amountText = reformatted
        }

        if reformatted.isEmpty {
            amount = 0
            return
        }

        amount = Decimal(string: reformatted, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    func syncTextFromAmount() {
        guard amount != 0 else {
            amountText = ""
            return
        }

        amountText = CurrencyFormat.string(amount, currencyCode: currencyCode)
            .replacingOccurrences(of: ",", with: "")
    }

    static func reformat(_ text: String, decimalPlaces: Int) -> String {
        var digits = String(text.filter(\.isNumber).drop { $0 == "0" })
        if digits.isEmpty {
            return ""
        }
        if decimalPlaces == 0 {
            return digits
        }
        if digits.count <= decimalPlaces {
            digits = String(repeating: "0", count: decimalPlaces - digits.count + 1) + digits
        }
        let splitIndex = digits.index(digits.endIndex, offsetBy: -decimalPlaces)
        return "\(digits[digits.startIndex ..< splitIndex]).\(digits[splitIndex...])"
    }

    func formatRate(_ rate: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        formatter.decimalSeparator = "."
        return formatter.string(from: rate as NSDecimalNumber) ?? "\(rate)"
    }
}
