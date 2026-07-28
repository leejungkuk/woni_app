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
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumRateFractionDigits(for: rate)
        return formatter.string(for: rate) ?? "\(rate)"
    }

    private static func maximumRateFractionDigits(for rate: Decimal) -> Int {
        let number = NSDecimalNumber(decimal: rate)
        let zero = NSDecimalNumber(value: 0)
        guard number.compare(zero) != .orderedSame else {
            return 4
        }

        var magnitude = number.compare(zero) == .orderedAscending
            ? number.multiplying(by: NSDecimalNumber(value: -1))
            : number
        let oneTenth = NSDecimalNumber(mantissa: 1, exponent: -1, isNegative: false)
        var leadingFractionalZeros = 0

        while magnitude.compare(oneTenth) == .orderedAscending {
            magnitude = magnitude.multiplying(by: NSDecimalNumber(value: 10))
            leadingFractionalZeros += 1
        }

        return 4 + leadingFractionalZeros
    }
}
