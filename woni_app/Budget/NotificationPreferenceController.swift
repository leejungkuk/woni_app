//
//  NotificationPreferenceController.swift
//  woni_app
//

import Foundation
import Observation

/// "알림을 받을까요?" 창의 모양 — ② 기본 · ③ iOS 에서 꺼짐.
enum NotificationAskVariant: Equatable {
    case standard, iosOff
}

enum NotificationAskAnswer {
    case turnOn, openSettings, later
}

/// 설정 줄을 누른 뒤 띄울 토스트.
enum NotificationToggleResult: Equatable {
    case turnedOn, turnedOff, unchanged
}

/// "알림을 받을까요?" 창과 설정 탭 "알림" 줄의 판정(UI_GUIDE 203-208 · 스펙 :379-388). 두 화면이 같은 앱 알림 설정·
/// iOS 권한·"물어봤음"을 같이 쓰므로 여기 한 곳에서 정한다. 켤 때 서버를 부르지 않는다(스펙 :355).
@MainActor
@Observable
final class NotificationPreferenceController {
    /// 마지막으로 읽은 iOS 권한. 처음은 `.notDetermined` 이고 `refresh()` 와 iOS 권한 창의 답으로 바뀐다.
    private(set) var authorization: NotificationAuthorization = .notDetermined

    private let settings: NotificationSettingsStore
    private let permission: NotificationPermissionProviding
    private let openSystemSettings: () -> Void
    /// 다시 읽기를 시작할 때와 iOS 권한 창의 답이 들어올 때마다 올린다.
    private var authorizationGeneration = 0
    /// `authorization` 에 마지막으로 반영된 값의 세대. 다시 읽기는 자기 세대보다 새 값이 이미 반영됐을 때만 결과를
    /// 버린다 — 권한 창이 닫힐 때 겹친 foreground 갱신이 낡은 `.notDetermined` 로 답을 덮지 않게. 뒤에 시작만 한
    /// 다시 읽기로는 버리지 않는다 — 버리면 설정 줄·`알림 받기` 가 낡은 값으로 판정한다.
    private var appliedGeneration = 0

    init(
        settings: NotificationSettingsStore,
        permission: NotificationPermissionProviding,
        openSystemSettings: @escaping () -> Void
    ) {
        self.settings = settings
        self.permission = permission
        self.openSystemSettings = openSystemSettings
    }

    /// 보이는 값: 앱 알림 켜짐 ∧ iOS 허용.
    var isEffectivelyOn: Bool {
        NotificationSettingsStore.isEffectivelyOn(enabled: settings.isEnabled, authorization: authorization)
    }

    /// iOS 권한을 기기에서 다시 읽는다.
    func refresh() async {
        authorizationGeneration += 1
        let generation = authorizationGeneration
        let latest = await permission.authorization()
        guard generation > appliedGeneration else {
            return
        }
        apply(latest, generation: generation)
    }

    /// 보이는 달 응답으로 물을지와 모양. 물을 것이 없으면 nil. 부르기 전에 refresh 를 거친다.
    func askVariant(for budget: MonthlyBudget?) -> NotificationAskVariant? {
        guard let budget, budget.status != .notSet, !settings.hasAsked else {
            return nil
        }
        return authorization == .denied ? .iosOff : .standard
    }

    /// 예산 탭이 띄울 창. iOS 권한을 다시 읽은 뒤 `askVariant(for:)`. 기다리는 사이 이 작업이 취소됐으면 nil — 그 사이
    /// 가림이 생기거나 탭이 바뀌어 화면이 작업을 거뒀다.
    func askIfNeeded(for budget: MonthlyBudget?) async -> NotificationAskVariant? {
        await refresh()
        guard !Task.isCancelled else {
            return nil
        }
        return askVariant(for: budget)
    }

    func answerAsk(_ answer: NotificationAskAnswer) async {
        // 첫 await 앞에서 남긴다 — 창이 닫힌 뒤 iOS 권한 창을 기다리는 동안 예산 탭이 다시 물으면 같은 창이 또 뜬다.
        settings.hasAsked = true
        switch answer {
        case .turnOn:
            settings.isEnabled = true
            await refresh()
            // 임시 #40 — 이미 거부면 iOS 설정을 열지 않고 그대로 둔다
            if authorization == .notDetermined {
                await requestAuthorization()
            }
        case .openSettings:
            // 임시 #40 — 그 사이 허용됐어도 연다
            settings.isEnabled = true
            openSystemSettings()
        case .later:
            break
        }
    }

    func toggleFromSettings() async -> NotificationToggleResult {
        settings.hasAsked = true
        // iOS 설정에서 바꾸고 돌아와 foreground 갱신보다 먼저 누를 수 있다 — 판정과 "누르기 전" 값 모두 다시 읽은 뒤에.
        await refresh()
        let wasOn = isEffectivelyOn
        if wasOn {
            settings.isEnabled = false
        } else {
            settings.isEnabled = true
            switch authorization {
            case .notDetermined:
                await requestAuthorization()
            case .denied:
                openSystemSettings()
            case .allowed:
                break
            }
        }
        switch (wasOn, isEffectivelyOn) {
        case (false, true):
            return .turnedOn
        case (true, false):
            return .turnedOff
        default:
            return .unchanged
        }
    }
}

private extension NotificationPreferenceController {
    /// iOS 권한 창을 띄우고 답을 곧바로 반영한다 — 다음 `refresh()` 전에도 보이는 값이 맞아야 한다.
    func requestAuthorization() async {
        let answer = await permission.requestAuthorization()
        authorizationGeneration += 1
        apply(answer, generation: authorizationGeneration)
    }

    func apply(_ value: NotificationAuthorization, generation: Int) {
        authorization = value
        appliedGeneration = generation
    }
}
