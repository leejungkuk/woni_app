//
//  NotificationSettings.swift
//  woni_app
//

import Foundation
import Observation
import UserNotifications

/// 이 기기의 iOS 알림 권한.
enum NotificationAuthorization: Equatable {
    case notDetermined, denied, allowed
}

protocol NotificationPermissionProviding {
    func authorization() async -> NotificationAuthorization
    /// iOS 권한 창을 띄우고 답한 뒤의 상태를 돌려준다(이미 답했으면 창 없이 지금 상태).
    /// iOS 요청이 던지면 결과를 짐작하지 않고 `authorization()` 으로 지금 상태를 다시 읽어 돌려준다.
    func requestAuthorization() async -> NotificationAuthorization
}

/// `UNUserNotificationCenter` 를 감싼다. 요청 옵션은 배너+소리다 — 배지는 시안·문서에 없다.
struct SystemNotificationPermission: NotificationPermissionProviding {
    func authorization() async -> NotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.authorization(from: settings.authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorization {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await authorization()
    }

    /// 모르는 상태는 denied 다 — 허용으로 덮지 않고 보내지 않는 쪽으로 둔다.
    static func authorization(from status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .authorized, .provisional, .ephemeral:
            .allowed
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }
    }
}

/// 앱 알림 설정과 "물어봤음" 표시. iOS 권한이 기기 단위라 둘 다 기기에 남기고 계정과 상관없다 —
/// 로그아웃·계정 전환에도 지우지 않는다.
@Observable
@MainActor
final class NotificationSettingsStore {
    var isEnabled: Bool {
        didSet {
            userDefaults.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    var hasAsked: Bool {
        didSet {
            userDefaults.set(hasAsked, forKey: Self.askedKey)
        }
    }

    private let userDefaults: UserDefaults
    private static let enabledKey = "woni.app.notifications.enabled"
    private static let askedKey = "woni.app.notifications.asked"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        isEnabled = userDefaults.bool(forKey: Self.enabledKey)
        hasAsked = userDefaults.bool(forKey: Self.askedKey)
    }

    /// 보이는 "켜짐"이자 보낼 수 있는 상태: 앱 알림 켜짐 ∧ iOS 허용.
    static func isEffectivelyOn(enabled: Bool, authorization: NotificationAuthorization) -> Bool {
        enabled && authorization == .allowed
    }
}
