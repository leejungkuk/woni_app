//
//  SelectableCurrencyTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@MainActor
struct SelectableCurrencyTests {
    @Test("통화 피커는 확정 순서로 13종을 제공한다")
    func entryPickerOptionsMatchContract() {
        #expect(SelectableCurrency.entryPickerOptions == [
            .krw, .jpy, .thb, .cny, .hkd, .sgd, .idr,
            .myr, .usd, .eur, .aud, .nzd, .gbp
        ])
        #expect(SelectableCurrency.allCases.count == 13)
    }

    @Test("13종 통화의 한국어와 영어 표시명은 국가명 계약과 일치한다")
    func displayNamesMatchContract() {
        let currencies: [SelectableCurrency] = [
            .krw, .usd, .eur, .jpy, .cny, .gbp, .thb,
            .hkd, .sgd, .idr, .myr, .aud, .nzd
        ]
        let koreanNames = [
            "대한민국", "미국", "유럽", "일본", "중국", "영국", "태국",
            "홍콩", "싱가포르", "인도네시아", "말레이시아", "호주", "뉴질랜드"
        ]
        let englishNames = [
            "South Korea", "United States", "Europe", "Japan", "China", "United Kingdom", "Thailand",
            "Hong Kong", "Singapore", "Indonesia", "Malaysia", "Australia", "New Zealand"
        ]

        #expect(currencies.map { $0.displayName(.ko) } == koreanNames)
        #expect(currencies.map { $0.displayName(.en) } == englishNames)
    }

    @Test("13종 통화는 서버 환율 코드에 정확히 대응한다")
    func exchangeCodesMatchContract() {
        let currencies: [SelectableCurrency] = [
            .krw, .usd, .eur, .jpy, .cny, .gbp, .thb,
            .hkd, .sgd, .idr, .myr, .aud, .nzd
        ]
        let exchangeCodes: [CurrencyCode?] = [
            nil, .usd, .eur, .jpy, .cny, .gbp, .thb,
            .hkd, .sgd, .idr, .myr, .aud, .nzd
        ]

        #expect(currencies.map(\.exchangeCode) == exchangeCodes)
    }

    @Test("JPY와 IDR은 100단위이고 나머지 통화는 1단위다")
    func exchangeUnitsMatchContract() {
        let currencies: [SelectableCurrency] = [
            .krw, .usd, .eur, .jpy, .cny, .gbp, .thb,
            .hkd, .sgd, .idr, .myr, .aud, .nzd
        ]
        let exchangeUnits = currencies.map(\.exchangeUnit)

        #expect(exchangeUnits == [
            Decimal(1), Decimal(1), Decimal(1), Decimal(100), Decimal(1), Decimal(1), Decimal(1),
            Decimal(1), Decimal(1), Decimal(100), Decimal(1), Decimal(1), Decimal(1)
        ])
        #expect(SelectableCurrency.jpy.exchangeUnit == Decimal(100))
        #expect(SelectableCurrency.idr.exchangeUnit == Decimal(100))
    }
}
