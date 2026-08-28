//
//  RateStringTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

struct RateStringTests {
    @Test("일반 환율은 필요한 소수 자릿수와 천 단위 구분을 보존한다")
    func formatsCommonRates() throws {
        #expect(try CurrencyFormat.rateString(Self.decimal("9.0476")) == "9.0476")
        #expect(try CurrencyFormat.rateString(Self.decimal("0.0061")) == "0.0061")
        #expect(try CurrencyFormat.rateString(Self.decimal("1463.25")) == "1,463.25")
    }

    @Test("IDR base의 작은 cross rate는 선행 0 뒤 유효 자릿수를 왜곡하지 않는다")
    func preservesSmallCrossRateSignificance() throws {
        let rate = try Self.decimal("0.00006109")
        let formatted = CurrencyFormat.rateString(rate)

        #expect(formatted == "0.00006109")
        #expect(formatted != "0.0001")
        #expect(formatted != "0.0000")
    }

    @Test("더 작은 0이 아닌 환율과 0을 구분한다")
    func doesNotCollapseSmallRatesToZero() throws {
        #expect(try CurrencyFormat.rateString(Self.decimal("0.0001")) == "0.0001")
        #expect(try CurrencyFormat.rateString(Self.decimal("0.00001")) == "0.00001")
        #expect(CurrencyFormat.rateString(Decimal(0)) == "0.00")
    }
}

private extension RateStringTests {
    static func decimal(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
    }
}
