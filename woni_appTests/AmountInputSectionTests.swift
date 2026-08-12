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

    @Test("경계값 99,999,999는 0자리·2자리 통화 경로 모두 허용한다")
    func acceptsMaximumAmountBoundary() {
        let zeroDecimal = AmountInputSection.acceptedInput(from: "99999999", currencyCode: "KRW")
        #expect(zeroDecimal?.text == "99999999")
        #expect(zeroDecimal?.amount == Decimal(99_999_999))

        let twoDecimal = AmountInputSection.acceptedInput(from: "99999999.00", currencyCode: "USD")
        #expect(twoDecimal?.text == "99999999.00")
        #expect(twoDecimal?.amount == Decimal(99_999_999))
    }

    @Test("상한을 넘는 입력은 두 통화 경로 모두 거부한다(nil이면 호출부가 직전 값을 유지한다)")
    func rejectsInputOverMaximumAmount() {
        // 0자리 통화 — "99999999"에서 한 자리 더 입력한 상태.
        #expect(AmountInputSection.acceptedInput(from: "999999991", currencyCode: "KRW") == nil)
        // 2자리 통화 — 99,999,999.99는 저장 검증(amount <= 상한)과 같은 기준으로 거부한다.
        #expect(AmountInputSection.acceptedInput(from: "99999999.99", currencyCode: "USD") == nil)
        // cents-first로 "99999999.99"에 도달하는 실제 키 입력("9999999.99" + "9")도 거부한다.
        #expect(AmountInputSection.acceptedInput(from: "9999999.999", currencyCode: "USD") == nil)
    }

    @Test("상한 안내 표기는 검증 기준(maximumAmount)에서 파생된다")
    func maximumAmountLabelDerivesFromValidationBasis() {
        #expect(AddExpenseViewModel.maximumAmountLabel == "99,999,999")
    }

    @Test("1,000 이상 표시 문자열은 0자리·2자리 통화 모두 천 단위 콤마를 붙인다")
    func displayTextInsertsThousandsGrouping() throws {
        let zeroDecimal = try #require(AmountInputSection.acceptedInput(from: "10005", currencyCode: "KRW"))
        #expect(AmountInputSection.displayText(for: zeroDecimal, currencyCode: "KRW") == "10,005")

        let twoDecimal = try #require(AmountInputSection.acceptedInput(from: "123400", currencyCode: "USD"))
        #expect(AmountInputSection.displayText(for: twoDecimal, currencyCode: "USD") == "1,234.00")
    }

    @Test("콤마가 든 표시 텍스트를 다시 입력받아도 값이 보존된다(콤마=자릿수 구분자)")
    func reacceptsGroupedDisplayTextWithoutValueLoss() {
        let zeroDecimal = AmountInputSection.acceptedInput(from: "10,005", currencyCode: "KRW")
        #expect(zeroDecimal?.text == "10005")
        #expect(zeroDecimal?.amount == Decimal(10005))

        let twoDecimal = AmountInputSection.acceptedInput(from: "1,234.00", currencyCode: "USD")
        #expect(twoDecimal?.text == "1234.00")
        #expect(twoDecimal?.amount == Decimal(1234))
    }
}
