//
//  ReportRemainingTextTests.swift
//  woni_appTests
//
//  통계 합계 탭 "남은 돈" 문자열. 합계 금액은 부호 없이 오므로 부호는 이 함수가 붙인다.
//

import Foundation
import Testing
@testable import woni_app

struct ReportRemainingTextTests {
    @Test("남은 돈은 흑자에 +, 적자에 - 를 붙이고 0 은 그대로 둔다")
    func remainingTextKeepsSignForDeficitAndSurplus() {
        #expect(ReportCompareBars.remainingText(amountText: "3,000", total: 3000) == "+3,000")
        #expect(ReportCompareBars.remainingText(amountText: "3,000", total: -3000) == "-3,000")
        #expect(ReportCompareBars.remainingText(amountText: "0", total: 0) == "0")
    }
}
