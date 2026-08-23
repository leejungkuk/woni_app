//
//  MonthPagingRuleTests.swift
//  woni_appTests
//
//  달력 페이저의 기하 판정(축 잠금·세로 커밋 임계). 화면 없이 결정되는 규칙이라
//  XCUITest에 맡기지 않고 여기서 못박는다. 가로 판정은 UIScrollView 몫이라 여기 없다.
//

import Foundation
import Testing
@testable import woni_app

struct MonthPagingRuleTests {
    @Test("가로·세로가 같으면 가로로 잠근다")
    func axisLockPrefersHorizontalOnTie() {
        #expect(MonthPagingRule.axis(translation: CGSize(width: 30, height: 30)) == .horizontal)
        #expect(MonthPagingRule.axis(translation: CGSize(width: -30, height: 30)) == .horizontal)
        #expect(MonthPagingRule.axis(translation: CGSize(width: 10, height: -40)) == .vertical)
    }

    @Test("세로는 40pt 임계로 판정한다")
    func verticalCommitUsesFixedThreshold() {
        #expect(MonthPagingRule.verticalCommit(translation: -40) == .move(1))
        #expect(MonthPagingRule.verticalCommit(translation: 40) == .move(-1))
        #expect(MonthPagingRule.verticalCommit(translation: -39) == .cancel)
    }
}
