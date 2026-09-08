//
//  RateLabelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

struct RateLabelTests {
    @Test("거래 통화의 고시 단위 표시값이 1 미만이면 기준 통화를 왼쪽에 둔다", arguments: [
        ("USD", "KRW", decimalLiteral("1480.05"), decimalLiteral("1"), "USD 1 = KRW 1,480.05"),
        ("JPY", "KRW", decimalLiteral("9.0396"), decimalLiteral("1"), "JPY 100 = KRW 903.96"),
        ("IDR", "KRW", decimalLiteral("0.0822"), decimalLiteral("1"), "IDR 100 = KRW 8.22"),
        ("KRW", "USD", decimalLiteral("1"), decimalLiteral("1480.05"), "USD 1 = KRW 1,480.05"),
        ("KRW", "JPY", decimalLiteral("1"), decimalLiteral("9.0396"), "JPY 100 = KRW 903.96"),
        ("USD", "JPY", decimalLiteral("1480.05"), decimalLiteral("9.0396"), "USD 1 = JPY 163.72"),
        ("JPY", "USD", decimalLiteral("9.0396"), decimalLiteral("1480.05"), "USD 1 = JPY 163.72"),
        ("USD", "EUR", decimalLiteral("1480.05"), decimalLiteral("1480.05"), "USD 1 = EUR 1.00"),
        ("EUR", "USD", decimalLiteral("1480.04"), decimalLiteral("1480.05"), "USD 1 = EUR 1.00"),
        ("THB", "JPY", decimalLiteral("44.0"), decimalLiteral("9.0396"), "THB 1 = JPY 4.8674"),
        ("JPY", "THB", decimalLiteral("9.0396"), decimalLiteral("44.0"), "JPY 100 = THB 20.54")
    ])
    func flipsDirectionBelowOne(
        quote: String,
        base: String,
        quoteKrwPerUnit: Decimal,
        baseKrwPerUnit: Decimal,
        expected: String
    ) {
        #expect(CurrencyFormat.rateLabel(
            quoteCurrencyCode: quote,
            baseCurrencyCode: base,
            quoteKrwPerUnit: quoteKrwPerUnit,
            baseKrwPerUnit: baseKrwPerUnit
        ) == expected)
    }
}
