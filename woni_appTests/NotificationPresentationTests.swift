//
//  NotificationPresentationTests.swift
//  woni_appTests
//

import Testing
@testable import woni_app

/// "알림을 받을까요?" 창·설정 탭 "알림" 줄의 문구와 창을 띄울 수 있는지(UI_GUIDE 204-208 · 325-330).
/// 물을지·창 모양·토스트 여부는 `NotificationPreferenceController` 가 정하고, 여기서는 그 결과를 글자로 옮기는 일과
/// 루트의 가림만 본다.
@MainActor
struct NotificationPresentationTests {
    // MARK: 문구

    @Test("B64N.S4-R1 창·설정 줄·토스트 문구는 UI_GUIDE 표 그대로다", arguments: NotificationCopy.all)
    func copyMatchesGuide(_ copy: NotificationCopy) {
        let language = copy.language

        #expect(WoniStrings.notificationAskTitle(language) == copy.askTitle)
        #expect(WoniStrings.notificationAskBody(language) == copy.askBody)
        #expect(WoniStrings.notificationAskSettingsHint(language) == copy.askSettingsHint)
        #expect(WoniStrings.notificationAskIOSOff(language) == copy.askIOSOff)
        #expect(WoniStrings.notificationAskTurnOn(language) == copy.turnOn)
        #expect(WoniStrings.notificationAskLater(language) == copy.later)
        #expect(WoniStrings.notificationAskOpenSettings(language) == copy.openSettings)
        #expect(WoniStrings.notificationsRow(language) == copy.row)
        #expect(WoniStrings.notificationsOn(language) == copy.on)
        #expect(WoniStrings.notificationsOff(language) == copy.off)
        #expect(WoniStrings.notificationsTurnedOnToast(language) == copy.turnedOnToast)
        #expect(WoniStrings.notificationsTurnedOffToast(language) == copy.turnedOffToast)
    }

    @Test("B64N.S4-R1 짝: 같은 자리의 ko·en 문구는 서로 다르다 — 한 언어 문구로 다른 언어를 덮지 않았다")
    func copyDiffersByLanguage() {
        let pairs: [@MainActor (AppLanguage) -> String] = [
            WoniStrings.notificationAskTitle,
            WoniStrings.notificationAskBody,
            WoniStrings.notificationAskSettingsHint,
            WoniStrings.notificationAskIOSOff,
            WoniStrings.notificationAskTurnOn,
            WoniStrings.notificationAskLater,
            WoniStrings.notificationAskOpenSettings,
            WoniStrings.notificationsRow,
            WoniStrings.notificationsOn,
            WoniStrings.notificationsOff,
            WoniStrings.notificationsTurnedOnToast,
            WoniStrings.notificationsTurnedOffToast
        ]

        for copy in pairs {
            #expect(copy(.ko) != copy(.en))
        }
        // 켜짐·꺼짐과 두 토스트는 같은 언어 안에서도 서로 다르다.
        #expect(WoniStrings.notificationsOn(.ko) != WoniStrings.notificationsOff(.ko))
        #expect(WoniStrings.notificationsTurnedOnToast(.en) != WoniStrings.notificationsTurnedOffToast(.en))
    }
}

// MARK: 창 모양

extension NotificationPresentationTests {
    @Test("B64N.S4-R2 기본 창(②)과 iOS 꺼짐 창(③)은 둘째 줄·주 버튼·주 버튼의 답이 다르다", arguments: VariantCopy.all)
    func variantCopyAndAnswer(_ expected: VariantCopy) {
        #expect(expected.variant.message(expected.language) == expected.message)
        #expect(expected.variant.confirmTitle(expected.language) == expected.confirmTitle)
        #expect(expected.variant.confirmAnswer == expected.answer)
    }

    @Test("B64N.S4-R2 짝: 주 버튼의 답은 ② 켜기 · ③ iOS 설정 열기로 서로 다르다 — 어느 쪽도 나중에가 아니다")
    func confirmAnswersDiffer() {
        #expect(NotificationAskVariant.standard.confirmAnswer != NotificationAskVariant.iosOff.confirmAnswer)
        #expect(NotificationAskVariant.standard.confirmAnswer != .later)
        #expect(NotificationAskVariant.iosOff.confirmAnswer != .later)
        // 본문 첫 줄은 같고 둘째 줄만 다르다.
        #expect(NotificationAskVariant.standard.message(.ko) != NotificationAskVariant.iosOff.message(.ko))
        #expect(NotificationAskVariant.standard.message(.ko).hasPrefix(WoniStrings.notificationAskBody(.ko)))
        #expect(NotificationAskVariant.iosOff.message(.ko).hasPrefix(WoniStrings.notificationAskBody(.ko)))
    }
}

// MARK: 지금 띄울 수 있는지

extension NotificationPresentationTests {
    @Test("B64N.S4-R3 예산 탭이 선택돼 있고 가림이 하나도 없으면 창을 띄울 수 있다")
    func clearGateCanAsk() {
        #expect(NotificationAskGate.clear.canAsk)
    }

    @Test("B64N.S4-R3 다른 탭이거나 가림이 하나라도 있으면 띄우지 않고 기다린다", arguments: GateFlip.allCases)
    func blockedGateCannotAsk(_ flip: GateFlip) {
        let gate = flip.applied(to: .clear)

        #expect(gate != .clear)
        #expect(!gate.canAsk)
        // 짝: 이 한 칸만 되돌리면 다시 띄울 수 있다.
        #expect(NotificationAskGate.clear.canAsk)
    }
}

// MARK: 설정 줄 토스트

extension NotificationPresentationTests {
    @Test("B64N.S4-R5 보이는 값이 바뀌었을 때만 완료 토스트 문구가 있다", arguments: [AppLanguage.ko, .en])
    func toggleToastOnlyWhenChanged(_ language: AppLanguage) {
        let expected: (on: String, off: String) = switch language {
        case .ko: ("알림이 켜졌습니다.", "알림이 꺼졌습니다.")
        case .en: ("Notifications turned on.", "Notifications turned off.")
        }

        #expect(NotificationToggleResult.turnedOn.toastMessage(language) == expected.on)
        #expect(NotificationToggleResult.turnedOff.toastMessage(language) == expected.off)
        // 짝: iOS 가 막아 iOS 설정으로 갔거나 권한 창에서 거부해 보이는 값이 그대로면 토스트가 없다.
        #expect(NotificationToggleResult.unchanged.toastMessage(language) == nil)
    }
}

// MARK: 기대값

/// UI_GUIDE 325-330 en 표.
struct NotificationCopy: CustomTestStringConvertible {
    let language: AppLanguage
    let askTitle: String
    let askBody: String
    let askSettingsHint: String
    let askIOSOff: String
    let turnOn: String
    let later: String
    let openSettings: String
    let row: String
    let on: String
    let off: String
    let turnedOnToast: String
    let turnedOffToast: String

    var testDescription: String {
        "\(language)"
    }

    static let all = [
        NotificationCopy(
            language: .ko,
            askTitle: "알림을 받을까요?",
            askBody: "예산의 80%와 100%를 쓰면 알려 드립니다.",
            askSettingsHint: "설정에서 언제든 바꿀 수 있습니다.",
            askIOSOff: "지금은 iOS 설정에서 알림이 꺼져 있습니다.",
            turnOn: "알림 받기",
            later: "나중에",
            openSettings: "설정 열기",
            row: "알림",
            on: "켜짐",
            off: "꺼짐",
            turnedOnToast: "알림이 켜졌습니다.",
            turnedOffToast: "알림이 꺼졌습니다."
        ),
        NotificationCopy(
            language: .en,
            askTitle: "Turn on notifications?",
            askBody: "We'll let you know when you've used 80% and 100% of your budget.",
            askSettingsHint: "You can change this anytime in Settings.",
            askIOSOff: "Notifications are turned off in iOS Settings.",
            turnOn: "Turn On",
            later: "Not Now",
            openSettings: "Open Settings",
            row: "Notifications",
            on: "On",
            off: "Off",
            turnedOnToast: "Notifications turned on.",
            turnedOffToast: "Notifications turned off."
        )
    ]
}

/// 창 모양별 본문(두 줄을 줄바꿈으로 잇는다)·주 버튼·주 버튼의 답(UI_GUIDE 205-206).
struct VariantCopy: CustomTestStringConvertible {
    let variant: NotificationAskVariant
    let language: AppLanguage
    let message: String
    let confirmTitle: String
    let answer: NotificationAskAnswer

    var testDescription: String {
        "\(variant) · \(language)"
    }

    static let all = [
        VariantCopy(
            variant: .standard,
            language: .ko,
            message: "예산의 80%와 100%를 쓰면 알려 드립니다.\n설정에서 언제든 바꿀 수 있습니다.",
            confirmTitle: "알림 받기",
            answer: .turnOn
        ),
        VariantCopy(
            variant: .standard,
            language: .en,
            message: "We'll let you know when you've used 80% and 100% of your budget.\n"
                + "You can change this anytime in Settings.",
            confirmTitle: "Turn On",
            answer: .turnOn
        ),
        VariantCopy(
            variant: .iosOff,
            language: .ko,
            message: "예산의 80%와 100%를 쓰면 알려 드립니다.\n지금은 iOS 설정에서 알림이 꺼져 있습니다.",
            confirmTitle: "설정 열기",
            answer: .openSettings
        ),
        VariantCopy(
            variant: .iosOff,
            language: .en,
            message: "We'll let you know when you've used 80% and 100% of your budget.\n"
                + "Notifications are turned off in iOS Settings.",
            confirmTitle: "Open Settings",
            answer: .openSettings
        )
    ]
}

/// 가림 없는 상태에서 한 칸만 뒤집는다.
enum GateFlip: CaseIterable, CustomTestStringConvertible {
    case otherTab, rootToast, budgetToast, editSession, rootOverlay

    var testDescription: String {
        switch self {
        case .otherTab: "다른 탭"
        case .rootToast: "루트 토스트"
        case .budgetToast: "예산 탭 토스트"
        case .editSession: "예산 편집 회차"
        case .rootOverlay: "루트 오버레이"
        }
    }

    @MainActor
    func applied(to gate: NotificationAskGate) -> NotificationAskGate {
        var gate = gate
        switch self {
        case .otherTab: gate.isBudgetTabSelected = false
        case .rootToast: gate.hasRootToast = true
        case .budgetToast: gate.hasBudgetToast = true
        case .editSession: gate.isEditSessionOpen = true
        case .rootOverlay: gate.hasRootOverlay = true
        }
        return gate
    }
}

extension NotificationAskGate {
    /// 예산 탭 선택 · 가림 없음.
    @MainActor static let clear = NotificationAskGate(
        isBudgetTabSelected: true,
        hasRootToast: false,
        hasBudgetToast: false,
        isEditSessionOpen: false,
        hasRootOverlay: false
    )
}
