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

    /// 거래 통화를 왼쪽에 두되, 고시 단위 표시값이 1 미만이면 기준 통화를 왼쪽에 둔다.
    /// 뒤집힌 값은 항상 1 초과다: (kq/kb)·u_q < 1 ⇒ kb/kq > u_q ≥ 1 ⇒ (kb/kq)·u_b > 1.
    /// 전제: 두 KRW 환산값은 0보다 커야 한다.
    /// 역수의 역수로 인한 절사 오차를 피하고 양방향을 같은 식으로 계산하기 위해 소스값 둘을 받는다.
    static func rateLabel(
        quoteCurrencyCode: String,
        baseCurrencyCode: String,
        quoteKrwPerUnit: Decimal,
        baseKrwPerUnit: Decimal
    ) -> String {
        let quoteUnit = SelectableCurrency(rawValue: quoteCurrencyCode)?.exchangeUnit ?? 1
        let quoteValue = BaseRateMath.counterRate(
            numeratorKrwPerUnit: quoteKrwPerUnit,
            denominatorKrwPerUnit: baseKrwPerUnit
        ) * quoteUnit
        let (left, right, leftKrw, rightKrw) = quoteValue >= 1
            ? (quoteCurrencyCode, baseCurrencyCode, quoteKrwPerUnit, baseKrwPerUnit)
            : (baseCurrencyCode, quoteCurrencyCode, baseKrwPerUnit, quoteKrwPerUnit)
        let leftUnit = SelectableCurrency(rawValue: left)?.exchangeUnit ?? 1
        let value = BaseRateMath.counterRate(
            numeratorKrwPerUnit: leftKrw,
            denominatorKrwPerUnit: rightKrw
        ) * leftUnit
        return "\(left) \(leftUnit) = \(right) \(rateString(value))"
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
