import Foundation

/// KRW·JPY·IDR은 소숫점 없이, 그 외 통화는 소숫점 2자리까지 표기.
enum CurrencyFormat {
    static func decimalPlaces(for currencyCode: String) -> Int {
        SelectableCurrency(rawValue: currencyCode)?.decimalPlaces ?? 2
    }

    static func string(_ amount: Decimal, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        // Figma 고정 표기(천단위 콤마·점 소수·ASCII 숫자)를 device locale과 무관하게 보장한다.
        // en_US_POSIX는 소수점 "."·ASCII 숫자를 고정하지만 grouping이 기본 OFF라, 콤마 천단위는
        // usesGroupingSeparator/groupingSize로 명시 활성화해야 한다(표시·테스트 결정성).
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.roundingMode = .down
        let places = decimalPlaces(for: currencyCode)
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        return formatter.string(for: amount) ?? "\(amount)"
    }

    static func rateString(_ rate: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.roundingMode = .down
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = maximumRateFractionDigits(for: rate)
        return formatter.string(for: rate) ?? "\(rate)"
    }

    /// 은행 고시와 같은 형태의 환율 문구. 예: "USD 1 = KRW 1,394.10", "JPY 100 = KRW 874.78".
    ///
    /// 거래 통화를 왼쪽, 기준 통화를 오른쪽에 두는 방향으로 고정한다 — 화면에는 여러 통화가
    /// 섞여 나오므로 통화마다 방향이 달라지면 읽을 때마다 어느 쪽이 기준인지 확인해야 한다.
    ///
    /// 왼쪽 수량은 통화의 고시 단위(`exchangeUnit`)를 그대로 쓴다. 1단위로 환산하면 IDR이
    /// "IDR 1 = KRW 0.0786"이 되어 읽기 어렵고, 100단위 고시는 은행·포털이 쓰는 관례라
    /// 사용자에게도 익숙하다.
    static func rateLabel(
        quoteCurrencyCode: String,
        baseCurrencyCode: String,
        basePerQuoteUnit: Decimal
    ) -> String {
        let unit = SelectableCurrency(rawValue: quoteCurrencyCode)?.exchangeUnit ?? 1
        let scaled = NSDecimalNumber(decimal: basePerQuoteUnit)
            .multiplying(by: NSDecimalNumber(decimal: unit))
            .decimalValue
        return "\(quoteCurrencyCode) \(unit) = \(baseCurrencyCode) \(rateString(scaled))"
    }

    /// 10 이상이면 소수 2자리로 충분하다("1,394.10"). 그 아래는 2자리로 자르면 유효숫자가
    /// 사라지므로("9.0476" -> "9.04") 4자리를 남기고, 1 미만인 값만 앞의 0 개수만큼 더 늘린다.
    private static func maximumRateFractionDigits(for rate: Decimal) -> Int {
        let number = NSDecimalNumber(decimal: rate)
        let zero = NSDecimalNumber(value: 0)
        guard number.compare(zero) != .orderedSame else {
            return 2
        }

        var magnitude = number.compare(zero) == .orderedAscending
            ? number.multiplying(by: NSDecimalNumber(value: -1))
            : number
        guard magnitude.compare(NSDecimalNumber(value: 10)) == .orderedAscending else {
            return 2
        }

        let oneTenth = NSDecimalNumber(mantissa: 1, exponent: -1, isNegative: false)
        var leadingFractionalZeros = 0

        while magnitude.compare(oneTenth) == .orderedAscending {
            magnitude = magnitude.multiplying(by: NSDecimalNumber(value: 10))
            leadingFractionalZeros += 1
        }

        return 4 + leadingFractionalZeros
    }
}
