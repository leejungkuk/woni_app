import Foundation

extension Decimal {
    private static let twoFractionDigitRoundingBehavior = NSDecimalNumberHandler(
        roundingMode: .plain,
        scale: 2,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )

    var roundedToTwoFractionDigits: Decimal {
        NSDecimalNumber(decimal: self)
            .rounding(accordingToBehavior: Self.twoFractionDigitRoundingBehavior)
            .decimalValue
    }

    func truncated(scale: Int) -> Decimal {
        let behavior = NSDecimalNumberHandler(
            roundingMode: .down,
            scale: Int16(scale),
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )

        return NSDecimalNumber(decimal: self)
            .rounding(accordingToBehavior: behavior)
            .decimalValue
    }
}
