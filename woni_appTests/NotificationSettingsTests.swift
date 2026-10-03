//
//  NotificationSettingsTests.swift
//  woni_appTests
//

import Foundation
import Testing
import UserNotifications
@testable import woni_app

@Suite(.serialized)
@MainActor
struct NotificationSettingsTests {
    @Test("저장값이 없으면 앱 알림은 꺼짐이고 물어본 적이 없다")
    func defaultsAreOffAndNotAsked() throws {
        try Self.withUserDefaultsSuite { userDefaults, _ in
            let store = NotificationSettingsStore(userDefaults: userDefaults)

            #expect(store.isEnabled == false)
            #expect(store.hasAsked == false)
        }
    }

    @Test("켜짐과 물어봤음은 같은 suite 의 새 인스턴스에 남고 다른 suite 에는 없다")
    func valuesPersistAcrossInstances() throws {
        try Self.withUserDefaultsSuite { userDefaults, suiteName in
            let store = NotificationSettingsStore(userDefaults: userDefaults)
            store.isEnabled = true
            store.hasAsked = true

            let restoredDefaults = try #require(UserDefaults(suiteName: suiteName))
            let restored = NotificationSettingsStore(userDefaults: restoredDefaults)
            #expect(restored.isEnabled == true)
            #expect(restored.hasAsked == true)

            try Self.withUserDefaultsSuite { otherDefaults, _ in
                let other = NotificationSettingsStore(userDefaults: otherDefaults)
                #expect(other.isEnabled == false)
                #expect(other.hasAsked == false)
            }
        }
    }

    @Test("보이는 켜짐은 앱 알림 켜짐과 iOS 허용이 둘 다 있어야 한다")
    func effectiveOnNeedsBothAppAndIOS() {
        #expect(NotificationSettingsStore.isEffectivelyOn(enabled: true, authorization: .allowed))
        #expect(!NotificationSettingsStore.isEffectivelyOn(enabled: true, authorization: .denied))
        #expect(!NotificationSettingsStore.isEffectivelyOn(enabled: true, authorization: .notDetermined))
        #expect(!NotificationSettingsStore.isEffectivelyOn(enabled: false, authorization: .allowed))
    }

    @Test("iOS 권한 상태는 허용 3종만 allowed 이고 모르는 상태는 denied 다")
    func systemStatusMapping() throws {
        #expect(SystemNotificationPermission.authorization(from: .authorized) == .allowed)
        #expect(SystemNotificationPermission.authorization(from: .provisional) == .allowed)
        #expect(SystemNotificationPermission.authorization(from: .ephemeral) == .allowed)
        #expect(SystemNotificationPermission.authorization(from: .denied) == .denied)
        #expect(SystemNotificationPermission.authorization(from: .notDetermined) == .notDetermined)

        let unknown = try #require(UNAuthorizationStatus(rawValue: 99))
        #expect(SystemNotificationPermission.authorization(from: unknown) == .denied)
    }
}

private extension NotificationSettingsTests {
    static func withUserDefaultsSuite(
        _ body: (UserDefaults, String) throws -> Void
    ) throws {
        let suiteName = "woni_appTests.NotificationSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try body(userDefaults, suiteName)
    }
}
