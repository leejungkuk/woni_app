import SwiftUI

struct AmountInputSection: View {
    @Binding var amount: Decimal
    let currencyCode: String
    let ratePreview: BaseRatePreview?
    let isRateStale: Bool
    let isRateEstimated: Bool
    let language: AppLanguage
    var autoFocusAmount = false
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
            .accessibilityIdentifier("entry.currency")

            VStack(spacing: 4) {
                ZStack {
                    if amountText.isEmpty {
                        Text(CurrencyFormat.decimalPlaces(for: currencyCode) == 0 ? "0" : "0.00")
                            .woniFont(.h2)
                            .foregroundStyle(isAmountFocused ? WoniColor.gray40 : WoniColor.gray100)
                    }
                    TextField("", text: $amountText)
                        .accessibilityIdentifier("entry.amount")
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .woniFont(.h2)
                        .foregroundStyle(WoniColor.gray100)
                        .focused($isAmountFocused)
                        .onChange(of: amountText) { _, newValue in
                            formatAndSyncAmount(from: newValue, currencyCode: currencyCode)
                        }
                        .onChange(of: currencyCode) { _, newCode in
                            amount = amount.truncated(scale: CurrencyFormat.decimalPlaces(for: newCode))
                            syncTextFromAmount()
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

                if let ratePreview {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text(ratePreview.rateLabel)
                            Circle().fill(WoniColor.gray20).frame(width: 2, height: 2)
                            Text(ratePreview.convertedLabel)
                        }
                        if isRateStale {
                            Text(WoniStrings.ratePreviewStale(language))
                        }
                        if isRateEstimated {
                            Text(WoniStrings.rateEstimated(language))
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
        .task {
            guard autoFocusAmount else {
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }
            isAmountFocused = true
        }
    }
}

private struct AmountInputSectionRateStatePreview: View {
    let language: AppLanguage

    private let fixtures = [
        RateStateFixture(title: "server · current", currencyCode: "USD", hasQuote: true),
        RateStateFixture(title: "server · stale", currencyCode: "USD", hasQuote: true, isRateStale: true),
        RateStateFixture(title: "cache · current", currencyCode: "USD", hasQuote: true),
        RateStateFixture(title: "cache · stale", currencyCode: "USD", hasQuote: true, isRateStale: true),
        RateStateFixture(title: "seed", currencyCode: "USD", hasQuote: true, isRateEstimated: true),
        RateStateFixture(title: "seed · stale", currencyCode: "USD", hasQuote: true, isRateEstimated: true),
        RateStateFixture(title: "KRW", currencyCode: "KRW", hasQuote: true),
        RateStateFixture(title: "quote nil", currencyCode: "USD", hasQuote: false)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(fixtures) { fixture in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fixture.title)
                            .woniFont(.small1)
                            .foregroundStyle(WoniColor.gray80)
                        AmountInputSection(
                            amount: .constant(10),
                            currencyCode: fixture.currencyCode,
                            ratePreview: fixture.hasQuote
                                ? BaseRatePreview(
                                    rateLabel: "KRW 1.00 = \(fixture.currencyCode) 0.0007",
                                    convertedLabel: "KRW 14,000"
                                )
                                : nil,
                            isRateStale: fixture.isRateStale,
                            isRateEstimated: fixture.isRateEstimated,
                            language: language,
                            onTapCurrency: {}
                        )
                    }
                }
            }
            .padding()
        }
        .frame(width: 320)
        .background(WoniColor.base10)
    }
}

private struct RateStateFixture: Identifiable {
    let title: String
    let currencyCode: String
    let hasQuote: Bool
    var isRateStale = false
    var isRateEstimated = false

    var id: String {
        title
    }
}

#Preview("Rate states · KO · Narrow · AX2") {
    AmountInputSectionRateStatePreview(language: .ko)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Rate states · EN · Narrow · AX2") {
    AmountInputSectionRateStatePreview(language: .en)
        .environment(\.dynamicTypeSize, .accessibility2)
}

extension AmountInputSection {
    private func formatAndSyncAmount(from text: String, currencyCode: String) {
        let decimalPlaces = CurrencyFormat.decimalPlaces(for: currencyCode)
        if decimalPlaces > 0 {
            let result = Self.centsFirstResync(text)

            if result.text != text {
                amountText = result.text
            }

            amount = result.amount
            return
        }

        let sanitized = Self.sanitize(text, decimalPlaces: decimalPlaces)

        if sanitized != text {
            amountText = sanitized
        }

        amount = Self.decimalValue(from: sanitized)
    }

    private func syncTextFromAmount() {
        guard amount != 0 else {
            amountText = ""
            return
        }

        amountText = CurrencyFormat.string(amount, currencyCode: currencyCode)
            .replacingOccurrences(of: ",", with: "")
    }

    static func centsFirstResync(_ text: String) -> (text: String, amount: Decimal) {
        // Character.isNumber만으로는 ①·１ 같은 비ASCII 숫자가 통과해 표시 텍스트가 오염된다.
        let digits = normalizeLeadingZeros(String(text.filter { $0.isASCII && $0.isNumber }))
        guard !digits.isEmpty, digits != "0" else {
            return ("", 0)
        }

        let paddedDigits = String(repeating: "0", count: max(0, 3 - digits.count)) + digits
        let decimalIndex = paddedDigits.index(paddedDigits.endIndex, offsetBy: -2)
        let resyncedText = paddedDigits[..<decimalIndex] + "." + paddedDigits[decimalIndex...]
        let amount = Decimal(
            string: String(resyncedText),
            locale: Locale(identifier: "en_US_POSIX")
        ) ?? 0

        return (String(resyncedText), amount)
    }

    /// 0자리 통화 경로에서 정수를 자연스럽게 입력한다.
    /// legacy 자유 입력 계약상 소수점은 사용자가 직접 "." 을 누를 때만 붙는다.
    /// 소수 자릿수는 통화별 허용치(KRW·JPY·IDR=0, 그 외 2)로 제한하고, 소수 미허용 통화는
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
    private static func decimalValue(from text: String) -> Decimal {
        let trimmed = text.hasSuffix(".") ? String(text.dropLast()) : text
        guard !trimmed.isEmpty else {
            return 0
        }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}
