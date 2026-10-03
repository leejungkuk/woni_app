//
//  WoniStringsNotifications.swift
//  woni_app
//

import Foundation

/// "알림을 받을까요?" 창·설정 탭 "알림" 줄·토스트 문구(UI_GUIDE "알림"·en 표).
extension WoniStrings {
    static func notificationAskTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "알림을 받을까요?"
        case .en: "Turn on notifications?"
        }
    }

    /// 본문 첫 줄. 둘째 줄은 창 모양(②·③)에 따라 `notificationAskSettingsHint`·`notificationAskIOSOff`.
    static func notificationAskBody(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산의 80%와 100%를 쓰면 알려 드립니다."
        case .en: "We'll let you know when you've used 80% and 100% of your budget."
        }
    }

    static func notificationAskSettingsHint(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "설정에서 언제든 바꿀 수 있습니다."
        case .en: "You can change this anytime in Settings."
        }
    }

    static func notificationAskIOSOff(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "지금은 iOS 설정에서 알림이 꺼져 있습니다."
        case .en: "Notifications are turned off in iOS Settings."
        }
    }

    static func notificationAskTurnOn(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "알림 받기"
        case .en: "Turn On"
        }
    }

    static func notificationAskLater(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "나중에"
        case .en: "Not Now"
        }
    }

    static func notificationAskOpenSettings(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "설정 열기"
        case .en: "Open Settings"
        }
    }

    static func notificationsRow(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "알림"
        case .en: "Notifications"
        }
    }

    static func notificationsOn(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "켜짐"
        case .en: "On"
        }
    }

    static func notificationsOff(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "꺼짐"
        case .en: "Off"
        }
    }

    static func notificationsTurnedOnToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "알림이 켜졌습니다."
        case .en: "Notifications turned on."
        }
    }

    static func notificationsTurnedOffToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "알림이 꺼졌습니다."
        case .en: "Notifications turned off."
        }
    }
}
