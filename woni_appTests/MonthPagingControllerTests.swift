//
//  MonthPagingControllerTests.swift
//  woni_appTests
//
//  달력 페이저가 내는 스크롤 활동 통지의 짝. 호출자(`MainView`)는 이 통지를 세어 정착 상태를
//  판단하고 그 상태로 날짜 셀 탭을 여닫으므로, 시작 통지가 종료 통지보다 많아지는 순간
//  선택이 영구히 죽는다. UI 테스트는 드래그마다 정착을 기다려 감속을 끊지 않아 잡지 못한다.
//

import SwiftUI
import Testing
import UIKit
@testable import woni_app

@MainActor
struct MonthPagingControllerTests {
    @Test("감속 중 다시 밀어도 스크롤 활동 통지의 짝이 맞는다")
    func scrollActivityStaysBalancedWhenDragInterruptsDeceleration() {
        var activity: [Bool] = []
        let controller = makeController { activity.append($0) }
        let scrollView = UIScrollView()

        controller.scrollViewWillBeginDragging(scrollView)
        controller.scrollViewDidEndDragging(scrollView, willDecelerate: true)
        // UIKit은 감속 중 손을 대면 `scrollViewDidEndDecelerating`을 건너뛰고 곧바로 여기로 온다.
        controller.scrollViewWillBeginDragging(scrollView)
        controller.scrollViewDidEndDecelerating(scrollView)

        #expect(activity == [true, false])
    }

    @Test("폭이 바뀌어 감속이 조용히 끊겨도 종료 통지가 나온다")
    func scrollActivityClosesWhenWidthChangeCancelsDeceleration() {
        var activity: [Bool] = []
        let controller = makeController { activity.append($0) }
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        controller.view.layoutIfNeeded()

        controller.scrollViewWillBeginDragging(UIScrollView())
        controller.view.frame = CGRect(x: 0, y: 0, width: 844, height: 300)
        controller.view.layoutIfNeeded()

        #expect(activity == [true, false])
    }

    private func makeController(
        onScrollActivity: @escaping (Bool) -> Void
    ) -> MonthPagingController<EmptyView> {
        MonthPagingController(
            rootView: EmptyView(),
            onCommit: { _ in },
            onScrollActivity: onScrollActivity,
            onSlideFinished: {}
        )
    }
}
