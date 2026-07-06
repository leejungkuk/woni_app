import Foundation

/// KRW는 소숫점 없이, 그 외 통화(JPY/USD 등)는 소숫점 2자리까지 표기.
enum CurrencyFormat {
    static func decimalPlaces(for currencyCode: String) -> Int {
        currencyCode == "KRW" ? 0 : 2
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
        let places = decimalPlaces(for: currencyCode)
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        return formatter.string(for: amount) ?? "\(amount)"
    }
}
