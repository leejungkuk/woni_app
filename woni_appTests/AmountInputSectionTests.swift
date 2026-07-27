//
//  AmountInputSectionTests.swift
//  woni_appTests
//

import Testing
@testable import woni_app

@MainActor
struct AmountInputSectionTests {
    @Test("0자리 통화 입력은 소수점과 소수부를 차단한다")
    func zeroDecimalPlacesRejectsFractionInput() {
        #expect(AmountInputSection.sanitize(".", decimalPlaces: 0).isEmpty)
        #expect(AmountInputSection.sanitize("12.50", decimalPlaces: 0) == "12")
    }

    @Test("2자리 통화 입력은 소수 둘째 자리와 후행 소수점을 허용한다")
    func twoDecimalPlacesLimitsFractionAndKeepsTrailingDot() {
        #expect(AmountInputSection.sanitize("12.345", decimalPlaces: 2) == "12.34")
        #expect(AmountInputSection.sanitize("12.", decimalPlaces: 2) == "12.")
    }

    @Test("금액 입력의 선행 0 정규화를 유지한다")
    func normalizesLeadingZeros() {
        #expect(AmountInputSection.normalizeLeadingZeros("007") == "7")
        #expect(AmountInputSection.normalizeLeadingZeros(".5") == "0.5")
    }
}
