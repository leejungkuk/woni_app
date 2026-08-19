//
//  InteractivePopModifierTests.swift
//  woni_appTests
//

import Foundation
import Testing
import UIKit
@testable import woni_app

/// `isEnabled` 세 갈래(값 전달 경로·`enable()`의 desired 반영·KVO 강제 복원의 desired 관통)를
/// 고정한다. 하나라도 빠지면 SwiftUI/시스템이 제스처를 되살려 요청 중 pop 차단이 기기별로 갈린다.
@MainActor
struct InteractivePopModifierTests {
    @Test("attach 시 desiredEnabled=false면 delegate만 교체하고 제스처는 켜지 않는다")
    func enableRespectsDesiredDisabledState() async throws {
        let harness = try await makePopHarness(desiredEnabled: false)

        #expect(harness.gesture.isEnabled == false)
    }

    @Test("desiredEnabled 토글은 제스처 활성 상태에 즉시 반영된다")
    func desiredEnabledTogglePropagates() async throws {
        let harness = try await makePopHarness(desiredEnabled: true)
        #expect(harness.gesture.isEnabled == true)

        harness.view.desiredEnabled = false
        #expect(harness.gesture.isEnabled == false)

        harness.view.desiredEnabled = true
        #expect(harness.gesture.isEnabled == true)
    }

    @Test("KVO 복원은 desired 상태를 따른다 — 외부에서 끄든 켜든 desired로 되돌린다")
    func observerEnforcesDesiredState() async throws {
        let harness = try await makePopHarness(desiredEnabled: true)

        // SwiftUI(`.toolbar(.hidden)`)가 끄는 상황 — desired=true면 즉시 되살린다.
        harness.gesture.isEnabled = false
        #expect(harness.gesture.isEnabled == true)

        // 요청 중 차단 상태에서 시스템이 되살리는 상황 — desired=false면 즉시 되돌린다.
        harness.view.desiredEnabled = false
        harness.gesture.isEnabled = true
        #expect(harness.gesture.isEnabled == false)
    }
}

@MainActor
private struct PopHarness {
    // window·nav는 참조를 유지해야 뷰가 detach되지 않는다.
    let window: UIWindow
    let nav: UINavigationController
    let view: InteractivePopView
    let gesture: UIGestureRecognizer
}

@MainActor
private func makePopHarness(desiredEnabled: Bool) async throws -> PopHarness {
    let nav = UINavigationController()
    nav.viewControllers = [UIViewController(), UIViewController()]
    // key로 만들지 않는다 — key window 개수를 전제하는 테스트(PresentationAnchorTests)와 간섭을 피한다.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = nav
    window.isHidden = false
    nav.view.layoutIfNeeded()
    let topView = try #require(nav.topViewController?.view)
    await waitUntil { topView.window != nil }

    let gesture = try #require(nav.interactivePopGestureRecognizer)
    let originalDelegate = gesture.delegate
    let view = InteractivePopView()
    view.desiredEnabled = desiredEnabled
    topView.addSubview(view)
    // didMoveToWindow의 enable()은 다음 main queue 턴에 돈다 — delegate 교체로 완료를 판정한다.
    await waitUntil { gesture.delegate !== originalDelegate }

    return PopHarness(window: window, nav: nav, view: view, gesture: gesture)
}
