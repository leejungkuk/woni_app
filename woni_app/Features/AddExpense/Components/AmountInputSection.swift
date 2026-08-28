import SwiftUI

struct AmountInputSection: View {
    @Binding var amount: Decimal
    let currencyCode: String
    let ratePreview: BaseRatePreview?
    let isRateEstimated: Bool
    let language: AppLanguage
    var autoFocusAmount = false
    var accent: ChipButton.ChipAccent = .terracotta
    var onTapCurrency: () -> Void
    /// 상한 초과로 입력이 거부됐음을 상위에 알린다(안내 문구는 상위가 정한다).
    var onMaximumAmountExceeded: () -> Void

    @State private var amountText = ""
    /// UITextField 랩의 편집 상태를 받아 placeholder 색을 가른다(옛 `@FocusState` 역할).
    /// 자동 포커스도 이 값을 true로 올려 요청한다.
    @State private var isAmountFocused = false
    @State private var didAutoFocus = false

    private var pillBackground: Color {
        accent == .terracotta ? WoniColor.terracotta20 : WoniColor.olive20
    }

    private var pillForeground: Color {
        accent == .terracotta ? WoniColor.terracotta110 : WoniColor.olive110
    }

    var body: some View {
        VStack(spacing: 16) {
            Button {
                hideKeyboard()
                onTapCurrency()
            } label: {
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
                    AmountTextField(
                        text: $amountText,
                        amount: $amount,
                        isFocused: $isAmountFocused,
                        currencyCode: currencyCode,
                        onMaximumAmountExceeded: onMaximumAmountExceeded
                    )
                    // `woniFont(.h2)`가 붙이던 세로 여백을 같은 값으로 재현해 기존 높이를 유지한다.
                    .padding(.vertical, WoniTypography.h2.lineSpacing / 2)
                    .frame(maxWidth: .infinity)
                    .onChange(of: currencyCode) { _, newCode in
                        amount = amount.truncated(scale: CurrencyFormat.decimalPlaces(for: newCode))
                        syncTextFromAmount()
                    }
                    .onChange(of: amount) { _, newValue in
                        // 저장 후 ViewModel이 amount를 0으로 되돌리면 입력 텍스트도 비운다.
                        // 단, 사용자가 "0." 처럼 값이 0인 상태를 입력 중일 때는 유지한다.
                        // 표시 텍스트의 천 단위 콤마는 파싱 전에 벗긴다 — `Decimal(string:)`이
                        // "10,005"를 10으로 조용히 잘라 먹어 판정이 뒤집힌다.
                        let plainText = amountText.replacingOccurrences(of: ",", with: "")
                        if newValue == 0, Self.decimalValue(from: plainText) != 0 {
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
                        if let staleDateLabel = ratePreview.staleDateLabel {
                            Text(staleDateLabel)
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
        // 첫 진입 1회만 — push 화면(카테고리 관리·추가)에서 돌아올 때도 `.task`가 다시 돌므로,
        // 떠날 때 내려간 키패드가 복귀와 함께 되살아나지 않게 한다.
        .task {
            guard autoFocusAmount, !didAutoFocus else {
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }
            didAutoFocus = true
            isAmountFocused = true
        }
    }
}

private struct AmountInputSectionRateStatePreview: View {
    let language: AppLanguage

    private var fixtures: [RateStateFixture] {
        let staleDateLabel = WoniStrings.ratePreviewStale(
            language,
            baseDate: language == .ko ? "5월 22일" : "May 22"
        )
        return [
            RateStateFixture(title: "server · current", currencyCode: "USD", hasQuote: true),
            RateStateFixture(
                title: "server · stale",
                currencyCode: "USD",
                hasQuote: true,
                staleDateLabel: staleDateLabel
            ),
            RateStateFixture(title: "cache · current", currencyCode: "USD", hasQuote: true),
            RateStateFixture(
                title: "cache · stale",
                currencyCode: "USD",
                hasQuote: true,
                staleDateLabel: staleDateLabel
            ),
            RateStateFixture(title: "seed", currencyCode: "USD", hasQuote: true, isRateEstimated: true),
            RateStateFixture(title: "seed · stale", currencyCode: "USD", hasQuote: true, isRateEstimated: true),
            RateStateFixture(title: "KRW", currencyCode: "KRW", hasQuote: true),
            RateStateFixture(title: "quote nil", currencyCode: "USD", hasQuote: false)
        ]
    }

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
                                    rateLabel: "\(fixture.currencyCode) 1 = KRW 1,400.00",
                                    convertedLabel: "KRW 14,000",
                                    staleDateLabel: fixture.staleDateLabel
                                )
                                : nil,
                            isRateEstimated: fixture.isRateEstimated,
                            language: language,
                            onTapCurrency: {},
                            onMaximumAmountExceeded: {}
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
    var staleDateLabel: String?
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
    /// `acceptedInput` 결과를 화면 표시 문자열로 바꾼다. 천 단위 콤마는 이 단계에서만 붙는다
    /// (`sanitize`·`centsFirstResync`는 평문을 유지한다 — 파싱·상한 비교의 기준).
    static func displayText(
        for input: (text: String, amount: Decimal),
        currencyCode: String
    ) -> String {
        input.text.isEmpty ? "" : CurrencyFormat.string(input.amount, currencyCode: currencyCode)
    }

    /// 입력 텍스트를 통화 자릿수 규칙(0자리=sanitize, 그 외=cents-first)대로 재해석한다.
    /// 결과가 저장 검증과 같은 상한(`AddExpenseViewModel.maximumAmount`)을 넘으면
    /// nil을 반환해 그 입력을 거부한다 — 입력은 되는데 저장만 막히는 어긋남을 없앤다.
    static func acceptedInput(
        from text: String,
        currencyCode: String
    ) -> (text: String, amount: Decimal)? {
        let decimalPlaces = CurrencyFormat.decimalPlaces(for: currencyCode)
        let result: (text: String, amount: Decimal)
        if decimalPlaces > 0 {
            result = centsFirstResync(text)
        } else {
            let sanitized = sanitize(text, decimalPlaces: decimalPlaces)
            result = (sanitized, decimalValue(from: sanitized))
        }

        guard result.amount <= AddExpenseViewModel.maximumAmount else {
            return nil
        }

        return result
    }

    private func syncTextFromAmount() {
        guard amount != 0 else {
            amountText = ""
            return
        }

        amountText = CurrencyFormat.string(amount, currencyCode: currencyCode)
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
    /// 소수점 이후 입력을 버린다. 숫자·"." 외 문자는 무시한다 — ","는 표시 텍스트가
    /// 되돌아올 때의 천 단위 구분자이므로 자릿수 구분자로 무시한다.
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
            } else if character == "." {
                guard decimalPlaces > 0, !hasDot else {
                    break
                }
                hasDot = true
                result.append(".")
            }
            // ","는 무시(천 단위 구분자). 소수점으로 취급하지 않아도 안전하다 —
            // 금액 키패드는 .numberPad라 콤마 키 자체가 없어, 사용자가 콤마를
            // 소수점 의도로 입력할 경로가 없다.
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
