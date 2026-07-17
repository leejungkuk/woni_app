import SwiftUI

struct AmountInputSection: View {
    @Binding var amount: Decimal
    let currencyCode: String
    let krwToForeignRate: Decimal?
    let convertedBaseAmount: Decimal?
    let isRateStale: Bool
    let language: AppLanguage
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
                            // 저장 후 ViewModel이 amount를 0으로 되돌리면 입력 텍스트도 비운다.
                            // 단, 사용자가 "0." 처럼 값이 0인 상태를 입력 중일 때는 유지한다.
                            if newValue == 0, Self.decimalValue(from: amountText) != 0 {
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
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text("KRW 1.00 = \(currencyCode) \(formatRate(krwToForeignRate))")
                            Circle().fill(WoniColor.gray20).frame(width: 2, height: 2)
                            Text("KRW \(convertedText)")
                        }
                        if isRateStale {
                            Text(WoniStrings.ratePreviewStale(language))
                        }
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
        let sanitized = Self.sanitize(
            text,
            decimalPlaces: CurrencyFormat.decimalPlaces(for: currencyCode)
        )

        if sanitized != text {
            amountText = sanitized
        }

        amount = Self.decimalValue(from: sanitized)
    }

    func syncTextFromAmount() {
        guard amount != 0 else {
            amountText = ""
            return
        }

        amountText = CurrencyFormat.string(amount, currencyCode: currencyCode)
            .replacingOccurrences(of: ",", with: "")
    }

    /// 정수부터 자연스럽게 입력하고, 소수점은 사용자가 직접 "." 을 누를 때만 붙는다.
    /// 소수 자릿수는 통화별 허용치(KRW=0, 그 외 2)로 제한하고, 소수 미허용 통화는
    /// 소수점 이후 입력을 버린다. 숫자·"."(로케일 대비 ",") 외 문자는 무시한다.
    static func sanitize(_ text: String, decimalPlaces: Int) -> String {
        var result = ""
        var hasDot = false
        var fractionCount = 0

        for character in text {
            if character.isNumber {
                if hasDot {
                    if fractionCount >= decimalPlaces {
                        break
                    }
                    fractionCount += 1
                }
                result.append(character)
            } else if character == "." || character == "," {
                guard decimalPlaces > 0, !hasDot else {
                    break
                }
                hasDot = true
                result.append(".")
            }
        }

        return normalizeLeadingZeros(result)
    }

    /// "007" → "7", "05" → "5" 처럼 불필요한 선행 0을 제거하되 "0.5" 는 보존하고,
    /// ".5" 처럼 소수점으로 시작하면 "0.5" 로 보정한다.
    static func normalizeLeadingZeros(_ text: String) -> String {
        var result = text
        if result.hasPrefix(".") {
            result = "0" + result
        }
        while result.count > 1, result.hasPrefix("0"), !result.hasPrefix("0.") {
            result.removeFirst()
        }
        return result
    }

    /// 입력 텍스트를 Decimal 로 환산한다. 입력 도중의 후행 "."(예: "12.")은 12로 본다.
    static func decimalValue(from text: String) -> Decimal {
        let trimmed = text.hasSuffix(".") ? String(text.dropLast()) : text
        guard !trimmed.isEmpty else {
            return 0
        }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) ?? 0
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
