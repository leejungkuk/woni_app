//
//  AmountInputSectionTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@MainActor
struct AmountInputSectionTests {
    @Test("0자리 통화 입력은 소수점과 소수부를 차단한다")
    func zeroDecimalPlacesRejectsFractionInput() {
        #expect(AmountInputSection.sanitize(".", decimalPlaces: 0).isEmpty)
        #expect(AmountInputSection.sanitize("12.50", decimalPlaces: 0) == "12")
    }

    @Test("legacy 자유 입력 헬퍼는 2자리 소수 제한과 후행 소수점을 유지한다")
    func legacyFreeInputHelperLimitsFractionAndKeepsTrailingDot() {
        #expect(AmountInputSection.sanitize("12.345", decimalPlaces: 2) == "12.34")
        #expect(AmountInputSection.sanitize("12.", decimalPlaces: 2) == "12.")
    }

    @Test("금액 입력의 선행 0 정규화를 유지한다")
    func normalizesLeadingZeros() {
        #expect(AmountInputSection.normalizeLeadingZeros("007") == "7")
        #expect(AmountInputSection.normalizeLeadingZeros(".5") == "0.5")
    }

    @Test("cents-first 연속 입력은 소수 둘째 자리부터 왼쪽으로 이동한다")
    func centsFirstContinuousInputTransitions() {
        let cases: [(input: String, expected: (text: String, amount: String))] = [
            ("1", ("0.01", "0.01")),
            ("0.012", ("0.12", "0.12")),
            ("0.123", ("1.23", "1.23")),
            ("1.234", ("12.34", "12.34"))
        ]

        for testCase in cases {
            let result = AmountInputSection.centsFirstResync(testCase.input)

            #expect(result.text == testCase.expected.text)
            #expect(result.amount == Decimal(string: testCase.expected.amount))
        }
    }

    @Test("cents-first 연속 삭제는 끝자리를 제거하고 최종 0은 빈 상태로 만든다")
    func centsFirstContinuousDeletionTransitions() {
        let cases: [(input: String, expected: (text: String, amount: String))] = [
            ("12.3", ("1.23", "1.23")),
            ("1.2", ("0.12", "0.12")),
            ("0.1", ("0.01", "0.01")),
            ("0.0", ("", "0"))
        ]

        for testCase in cases {
            let result = AmountInputSection.centsFirstResync(testCase.input)

            #expect(result.text == testCase.expected.text)
            #expect(result.amount == Decimal(string: testCase.expected.amount))
        }
    }

    @Test("cents-first 단독 입력과 붙여넣기는 숫자 버퍼를 정확한 Decimal로 재해석한다")
    func centsFirstStandaloneAndPasteCases() {
        let cases: [(input: String, expected: (text: String, amount: String))] = [
            ("", ("", "0")),
            ("0", ("", "0")),
            ("005", ("0.05", "0.05")),
            ("12.5", ("1.25", "1.25")),
            ("①", ("", "0")),
            ("1①2", ("0.12", "0.12"))
        ]

        for testCase in cases {
            let result = AmountInputSection.centsFirstResync(testCase.input)

            #expect(result.text == testCase.expected.text)
            #expect(result.amount == Decimal(string: testCase.expected.amount))
        }

        #expect(AmountInputSection.centsFirstResync("1").amount == Decimal(string: "0.01"))
    }
}
