//
//  MonthPagingRuleTests.swift
//  woni_appTests
//
//  달력 페이저의 기하 판정(축 잠금·커밋 규칙·속도 승계). 화면 없이 결정되는 규칙이라
//  XCUITest에 맡기지 않고 여기서 못박는다.
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

    @Test("반 폭 이상 끌면 커밋하고 미만이면 취소한다")
    func horizontalCommitUsesHalfWidth() {
        let width: CGFloat = 300

        #expect(
            MonthPagingRule.horizontalCommit(translation: -150, predictedEnd: -150, width: width)
                == .move(1)
        )
        #expect(
            MonthPagingRule.horizontalCommit(translation: 150, predictedEnd: 150, width: width)
                == .move(-1)
        )
        #expect(
            MonthPagingRule.horizontalCommit(translation: -149, predictedEnd: -149, width: width)
                == .cancel
        )
    }

    @Test("짧게 끌어도 투영 종점이 반 폭을 넘으면 커밋한다")
    func horizontalCommitUsesProjectedEnd() {
        #expect(
            MonthPagingRule.horizontalCommit(translation: -40, predictedEnd: -400, width: 300)
                == .move(1)
        )
    }

    @Test("끌다가 반대로 되튕겨 놓으면 취소한다")
    func horizontalCommitCancelsOnOppositeProjection() {
        #expect(
            MonthPagingRule.horizontalCommit(translation: -200, predictedEnd: 120, width: 300)
                == .cancel
        )
        #expect(
            MonthPagingRule.horizontalCommit(translation: -200, predictedEnd: 0, width: 300)
                == .cancel
        )
    }

    /// 레이아웃 전 프레임에서는 폭이 0이라 반 폭 판정 자체가 성립하지 않는다.
    @Test("폭을 모르면 커밋하지 않는다")
    func horizontalCommitRequiresKnownWidth() {
        #expect(
            MonthPagingRule.horizontalCommit(translation: -400, predictedEnd: -400, width: 0)
                == .cancel
        )
    }

    @Test("세로는 40pt 임계로 판정한다")
    func verticalCommitUsesFixedThreshold() {
        #expect(MonthPagingRule.verticalCommit(translation: -40) == .move(1))
        #expect(MonthPagingRule.verticalCommit(translation: 40) == .move(-1))
        #expect(MonthPagingRule.verticalCommit(translation: -39) == .cancel)
    }

    @Test("정착 속도는 남은 거리 대비 비율로, 목표 방향이 양수가 되게 정규화한다")
    func settleVelocityNormalizesTowardTarget() {
        // 왼쪽으로 놓는 중(-1000pt/s)이고 남은 거리는 +200pt → 목표(0)로 향하므로 양수다.
        #expect(MonthPagingRule.settleVelocity(velocity: -1000, remaining: 200) == 5)
        #expect(MonthPagingRule.settleVelocity(velocity: 1000, remaining: 200) == -5)
        // 이전 달 방향(남은 거리 음수)에서 부호가 뒤집히면 스프링이 반대로 출발한다.
        #expect(MonthPagingRule.settleVelocity(velocity: 1000, remaining: -200) == 5)
        #expect(MonthPagingRule.settleVelocity(velocity: -1000, remaining: -200) == -5)
        #expect(MonthPagingRule.settleVelocity(velocity: -1000, remaining: 0) == 0)
    }
}
