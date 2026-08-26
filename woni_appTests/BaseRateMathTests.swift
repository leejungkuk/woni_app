//
//  BaseRateMathTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

struct BaseRateMathTests {
    @Test("KRW와 단위 1·100 환율을 통화 1단위당 KRW로 정확히 변환한다")
    func calculatesKRWPerUnit() throws {
        let usdTTS = try Self.decimal("1480.96")
        let jpyTTS = try Self.decimal("904.76")
        let idrTTS = try Self.decimal("9.25")
        let expectedJPY = try Self.decimal("9.0476")
        let expectedIDR = try Self.decimal("0.0925")

        #expect(BaseRateMath.krwPerUnit(tts: Decimal(1), unit: Decimal(1)) == Decimal(1))
        #expect(
            BaseRateMath.krwPerUnit(
                tts: usdTTS,
                unit: SelectableCurrency.usd.exchangeUnit
            ) == usdTTS
        )
        #expect(
            BaseRateMath.krwPerUnit(
                tts: jpyTTS,
                unit: SelectableCurrency.jpy.exchangeUnit
            ) == expectedJPY
        )
        #expect(
            BaseRateMath.krwPerUnit(
                tts: idrTTS,
                unit: SelectableCurrency.idr.exchangeUnit
            ) == expectedIDR
        )
    }

    @Test("JPY base에서 USD counter 환율 방향은 JPY 1당 USD 값이다")
    func calculatesCounterRateInLabelDirection() throws {
        let usd = try #require(try BaseRateMath.krwPerUnit(
            tts: Self.decimal("1480.96"),
            unit: SelectableCurrency.usd.exchangeUnit
        ))
        let jpy = try #require(try BaseRateMath.krwPerUnit(
            tts: Self.decimal("904.76"),
            unit: SelectableCurrency.jpy.exchangeUnit
        ))

        let jpyToUSD = BaseRateMath.counterRate(
            numeratorKrwPerUnit: jpy,
            denominatorKrwPerUnit: usd
        )

        #expect(try Self.isApproximatelyEqual(
            jpyToUSD,
            Self.decimal("0.0061092804667242869"),
            tolerance: Self.decimal("0.0000000000000000001")
        ))
    }

    @Test("counter 환율은 USD↔JPY와 USD↔IDR 양방향에서 곱이 1이다")
    func counterRatesAreSymmetric() throws {
        let usd = try #require(try BaseRateMath.krwPerUnit(
            tts: Self.decimal("1480.96"),
            unit: SelectableCurrency.usd.exchangeUnit
        ))
        let jpy = try #require(try BaseRateMath.krwPerUnit(
            tts: Self.decimal("904.76"),
            unit: SelectableCurrency.jpy.exchangeUnit
        ))
        let idr = try #require(try BaseRateMath.krwPerUnit(
            tts: Self.decimal("9.25"),
            unit: SelectableCurrency.idr.exchangeUnit
        ))
        let tolerance = try Self.decimal("0.0000000000000000000000000001")

        for counter in [jpy, idr] {
            let forward = BaseRateMath.counterRate(
                numeratorKrwPerUnit: usd,
                denominatorKrwPerUnit: counter
            )
            let reverse = BaseRateMath.counterRate(
                numeratorKrwPerUnit: counter,
                denominatorKrwPerUnit: usd
            )
            let product = NSDecimalNumber(decimal: forward)
                .multiplying(by: NSDecimalNumber(decimal: reverse))
                .decimalValue

            #expect(Self.isApproximatelyEqual(product, Decimal(1), tolerance: tolerance))
        }
    }

    @Test("KRW 확정값을 base 통화 1단위당 KRW로 나누고 반올림하지 않는다")
    func calculatesRawBaseDisplayValue() throws {
        let value = try BaseRateMath.baseDisplayValue(
            krwValue: Self.decimal("14809.6"),
            baseKrwPerUnit: Self.decimal("9.0476")
        )

        #expect(try Self.isApproximatelyEqual(
            value,
            Self.decimal("1636.853972324152261"),
            tolerance: Self.decimal("0.000000000000001")
        ))
    }

    @Test("0·음수 tts와 유효하지 않은 unit은 nil이다")
    func rejectsNonPositiveInputs() {
        for unit in [Decimal(1), Decimal(100)] {
            #expect(BaseRateMath.krwPerUnit(tts: Decimal(0), unit: unit) == nil)
            #expect(BaseRateMath.krwPerUnit(tts: Decimal(-1), unit: unit) == nil)
        }

        #expect(BaseRateMath.krwPerUnit(tts: Decimal(1), unit: Decimal(0)) == nil)
        #expect(BaseRateMath.krwPerUnit(tts: Decimal(1), unit: Decimal(-100)) == nil)
    }
}

private extension BaseRateMathTests {
    static func decimal(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
    }

    static func isApproximatelyEqual(
        _ lhs: Decimal,
        _ rhs: Decimal,
        tolerance: Decimal
    ) -> Bool {
        let difference = NSDecimalNumber(decimal: lhs)
            .subtracting(NSDecimalNumber(decimal: rhs))
        let magnitude = difference.compare(NSDecimalNumber(value: 0)) == .orderedAscending
            ? difference.multiplying(by: NSDecimalNumber(value: -1))
            : difference
        return magnitude.compare(NSDecimalNumber(decimal: tolerance)) != .orderedDescending
    }
}
