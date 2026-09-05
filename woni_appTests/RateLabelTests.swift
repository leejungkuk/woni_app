//
//  RateLabelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

struct RateLabelTests {
    @Test("고시 단위에서 시작해 오른쪽 값이 0.1 이상인 첫 표시 단위를 선택한다", arguments: [
        ("USD", "KRW", "1480.05", "USD 1 = KRW 1,480.05"),
        ("JPY", "KRW", "9.0396", "JPY 100 = KRW 903.96"),
        ("IDR", "KRW", "0.0822", "IDR 100 = KRW 8.22"),
        ("KRW", "USD", "0.000675652", "KRW 10,000 = USD 6.7565"),
        ("KRW", "JPY", "0.1", "KRW 1 = JPY 0.10"),
        ("KRW", "JPY", "0.0999999", "KRW 100 = JPY 9.9999"),
        ("IDR", "JPY", "0.0090933", "IDR 100 = JPY 0.9093"),
        ("THB", "USD", "0.0297281", "THB 100 = USD 2.9728")
    ])
    func scalesDisplayUnit(quote: String, base: String, rate: String, expected: String) {
        #expect(CurrencyFormat.rateLabel(
            quoteCurrencyCode: quote,
            baseCurrencyCode: base,
            basePerQuoteUnit: decimalLiteral(rate)
        ) == expected)
    }

    @Test("사다리 끝에서도 임계 미달이면 10,000에 클램프한다")
    func clampsAtLargestUnit() {
        let label = CurrencyFormat.rateLabel(
            quoteCurrencyCode: "KRW",
            baseCurrencyCode: "USD",
            basePerQuoteUnit: decimalLiteral("0.00000001")
        )

        #expect(label.hasPrefix("KRW 10,000 = USD "))
    }
}
