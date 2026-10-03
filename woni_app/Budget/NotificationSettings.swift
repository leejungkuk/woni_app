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

/// `UNUserNotificationCenter` 의 얇은 입구 — 테스트가 요청 옵션과 다시 읽기를 본다.
protocol NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNUserNotificationCenter: NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

/// `UNUserNotificationCenter` 를 감싼다.
struct SystemNotificationPermission: NotificationPermissionProviding {
    private let center: any NotificationCenterClient

    init(center: any NotificationCenterClient = UNUserNotificationCenter.current()) {
        self.center = center
    }

    func authorization() async -> NotificationAuthorization {
        await Self.authorization(from: center.authorizationStatus())
    }

    func requestAuthorization() async -> NotificationAuthorization {
        // 임시 #20 — 배너+소리, 배지 없음(시안·문서에 표기 없음, 사용자 결정 대기)
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorization()
    }

    static func authorization(from status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .authorized, .provisional, .ephemeral:
            .allowed
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        // 임시 #23 — 모르는 상태는 보내지 않는 쪽(denied). codex 는 조용한 폴백으로 본다(설계 3차·구현 1차 Critical) — 사용자 결정 대기
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
