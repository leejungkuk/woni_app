//
//  CurrencyFormatTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

struct CurrencyFormatTests {
    @Test("통화별 소수 자릿수와 미지 통화 fallback을 적용한다")
    func formatsCurrencySpecificDecimalPlaces() {
        let amount = Decimal(1000)

        #expect(CurrencyFormat.string(amount, currencyCode: "JPY") == "1,000")
        #expect(CurrencyFormat.string(amount, currencyCode: "IDR") == "1,000")
        #expect(CurrencyFormat.string(amount, currencyCode: "USD") == "1,000.00")
        #expect(CurrencyFormat.string(amount, currencyCode: "KRW") == "1,000")
        #expect(CurrencyFormat.string(amount, currencyCode: "XXX") == "1,000.00")
    }

    @Test("금액 표시는 허용 소수 자릿수 아래를 절삭한다")
    func truncatesExcessFractionDigits() throws {
        let jpyAmount = try #require(Decimal(string: "12.9"))
        let usdAmount = try #require(Decimal(string: "12.999"))

        #expect(CurrencyFormat.string(jpyAmount, currencyCode: "JPY") == "12")
        #expect(CurrencyFormat.string(usdAmount, currencyCode: "USD") == "12.99")
    }
}

struct DecimalTruncationTests {
    @Test("0자리 절삭은 소수부를 버린다")
    func truncatesToInteger() throws {
        let amounts = try ["12.49", "12.50", "12.99"].map {
            try #require(Decimal(string: $0))
        }

        #expect(amounts.map { $0.truncated(scale: 0) } == [Decimal(12), Decimal(12), Decimal(12)])
    }

    @Test("2자리 절삭은 셋째 자리 이하를 버린다")
    func truncatesToTwoFractionDigits() throws {
        let amount = try #require(Decimal(string: "12.999"))
        let expected = try #require(Decimal(string: "12.99"))

        #expect(amount.truncated(scale: 2) == expected)
        #expect(amount.roundedToTwoFractionDigits != expected)
    }
}
