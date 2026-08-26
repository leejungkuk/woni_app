import Foundation

/// KRW 기준 quote를 변형하거나 새 `RateQuote`로 재포장하지 않고 표시용 파생값만 계산한다.
enum BaseRateMath {
    static func krwPerUnit(tts: Decimal, unit: Decimal) -> Decimal? {
        let ttsNumber = NSDecimalNumber(decimal: tts)
        let unitNumber = NSDecimalNumber(decimal: unit)
        let zero = NSDecimalNumber(value: 0)
        guard ttsNumber.compare(zero) == .orderedDescending,
              unitNumber.compare(zero) == .orderedDescending
        else {
            return nil
        }

        return ttsNumber.dividing(by: unitNumber).decimalValue
    }

    static func baseDisplayValue(
        krwValue: Decimal,
        baseKrwPerUnit: Decimal
    ) -> Decimal {
        NSDecimalNumber(decimal: krwValue)
            .dividing(by: NSDecimalNumber(decimal: baseKrwPerUnit))
            .decimalValue
    }

    static func counterRate(
        numeratorKrwPerUnit: Decimal,
        denominatorKrwPerUnit: Decimal
    ) -> Decimal {
        NSDecimalNumber(decimal: numeratorKrwPerUnit)
            .dividing(by: NSDecimalNumber(decimal: denominatorKrwPerUnit))
            .decimalValue
    }
}
