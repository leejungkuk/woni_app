//
//  BudgetInfoBubbleLayoutTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 탭 "남은 돈" 옆 (i) 말풍선의 꼬리 자리(UI_GUIDE "꼬리 12×6 이 (i) 가운데"). 말풍선 왼쪽 끝이 "남은 돈" 글자
/// 왼쪽이라, 꼬리 가운데 x 는 글자 폭 + 글자와 (i) 사이 간격 4 + (i) 폭 16 의 반이다.
@MainActor
struct BudgetInfoBubbleLayoutTests {
    @Test("BDF2.S1-R3 꼬리 가운데 x 는 글자 폭 + 간격 4 + (i) 폭의 반이다 — 글자 40 이면 52")
    func tailCenterIsIconCenter() {
        #expect(BudgetInfoBubbleLayout.tailCenterX(labelWidth: 40) == 52)
    }

    @Test("BDF2.S1-R3 꼬리는 글자 폭을 따라 움직인다 — 글자 73.5 면 85.5")
    func tailCenterFollowsLabelWidth() {
        #expect(BudgetInfoBubbleLayout.tailCenterX(labelWidth: 73.5) == 85.5)
    }

    @Test("BDF2.S1-R3 짝: 꼬리는 글자 끝(40)도 (i) 오른쪽 끝(60)도 가리키지 않는다")
    func tailCenterIsNeitherLabelEndNorIconEnd() {
        let center = BudgetInfoBubbleLayout.tailCenterX(labelWidth: 40)
        #expect(center != 40)
        #expect(center != 60)
    }
}
