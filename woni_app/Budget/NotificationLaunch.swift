//
//  NotificationLaunch.swift
//  woni_app
//

import Foundation
import UserNotifications

/// 앱을 열 때의 iOS 권한 창 — 앞에 앱 안내 창은 없다(UI_GUIDE 202). 허용해도 앱 알림은 꺼진 채다.
enum NotificationLaunch {
    /// iOS 가 아직 안 물었으면 한 번 묻는다. 물었으면 true. 답한 뒤에는 iOS 가 다시 띄우지 않으므로 앱도 부르지 않는다.
    static func requestIfNotDetermined(_ permission: NotificationPermissionProviding) async -> Bool {
        guard await permission.authorization() == .notDetermined else {
            return false
        }
        _ = await permission.requestAuthorization()
        return true
    }
}

/// 앱이 떠 있을 때도 배너를 보인다(UI_GUIDE 212). 판정은 모두 앱이 떠 있을 때라 이것이 없으면 배너 없이 기록만 남는다
/// (스펙 :364). `UNUserNotificationCenterDelegate` 는 어느 스레드에서 부르는지 보장이 없어 메인에 묶지 않는다 — 저장 상태가 없다.
/// `final` 은 두지 않는다 — SwiftFormat 과 SwiftLint 가 `nonisolated` 와의 순서를 반대로 요구해 둘 다 지나는 순서가 없다.
nonisolated class BudgetNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let presentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound]

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.presentationOptions
    }
}
