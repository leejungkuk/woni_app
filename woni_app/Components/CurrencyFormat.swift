import Foundation

/// KRW는 소숫점 없이, 그 외 통화(JPY/USD 등)는 소숫점 2자리까지 표기.
enum CurrencyFormat {
    static func decimalPlaces(for currencyCode: String) -> Int {
        currencyCode == "KRW" ? 0 : 2
    }

    static func string(_ amount: Decimal, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        let places = decimalPlaces(for: currencyCode)
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        return formatter.string(for: amount) ?? "\(amount)"
    }
}
