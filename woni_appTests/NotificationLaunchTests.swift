//
//  NotificationLaunchTests.swift
//  woni_appTests
//

import Testing
import UserNotifications
@testable import woni_app

/// 앱을 열 때 iOS 권한 창(UI_GUIDE 202 · 스펙 :380)과 앱을 보고 있을 때의 배너(UI_GUIDE 212 · 스펙 :364).
/// 루트 연결(의존성 조립 뒤 따로 띄움 · 위임 객체 연결)은 SwiftUI 수명주기라 여기서 부르지 못한다 — AC 와 실기기가 본다.
@MainActor
struct NotificationLaunchTests {
    @Test("B64N.S5-R1 iOS 가 아직 안 물었으면 iOS 권한 창을 한 번 띄우고 물었다고 답한다")
    func requestsWhenNotDetermined() async {
        let permission = FakeLaunchPermission(status: .notDetermined)

        let asked = await NotificationLaunch.requestIfNotDetermined(permission)

        #expect(asked)
        #expect(permission.requestCount == 1)
    }

    @Test(
        "B64N.S5-R1 iOS 가 이미 답했으면(허용·거부) 앱도 권한 창을 띄우지 않는다",
        arguments: [NotificationAuthorization.allowed, .denied]
    )
    func skipsWhenAnswered(_ status: NotificationAuthorization) async {
        let permission = FakeLaunchPermission(status: status)

        let asked = await NotificationLaunch.requestIfNotDetermined(permission)

        #expect(!asked)
        #expect(permission.requestCount == 0)
    }

    @Test(
        "B64N.S5-R2 앱을 보고 있을 때도 배너·알림 목록·소리로 보인다",
        arguments: [
            UNNotificationPresentationOptions.banner,
            .list,
            .sound
        ]
    )
    func presentsWhileForeground(_ option: UNNotificationPresentationOptions) {
        #expect(BudgetNotificationPresenter.presentationOptions.contains(option))
    }

    @Test("B64N.S5-R2 배너·알림 목록·소리 밖의 표시(배지)는 더하지 않는다 — iOS 권한도 배지를 묻지 않는다")
    func presentsNothingElse() {
        #expect(!BudgetNotificationPresenter.presentationOptions.contains(.badge))
        #expect(BudgetNotificationPresenter.presentationOptions == [.banner, .list, .sound])
    }
}

/// 지금 상태와 권한 창을 띄운 횟수만 본다. 창을 띄우면 허용으로 답한 것으로 둔다.
@MainActor
private final class FakeLaunchPermission: NotificationPermissionProviding {
    private(set) var status: NotificationAuthorization
    private(set) var requestCount = 0

    init(status: NotificationAuthorization) {
        self.status = status
    }

    func authorization() async -> NotificationAuthorization {
        status
    }

    func requestAuthorization() async -> NotificationAuthorization {
        requestCount += 1
        status = .allowed
        return status
    }
}
