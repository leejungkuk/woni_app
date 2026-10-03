//
//  NotificationPresentation.swift
//  woni_app
//

/// "알림을 받을까요?" 창을 지금 띄울 수 있는지 — 루트 상태만 본다(물을지·모양은 `NotificationPreferenceController`).
/// 숨은 탭도 살아 있어 화면의 등장만으로는 예산 탭이 보이는지 모르므로 루트가 선택된 탭을 알려 준다.
struct NotificationAskGate: Equatable {
    var isBudgetTabSelected: Bool
    var hasRootToast: Bool
    var hasBudgetToast: Bool
    /// 예산 편집 회차 — 모달이 닫힌 뒤에도 결과 반영·토스트가 정해질 때까지 열려 있다(첫 저장이면 저장 토스트 뒤에 묻는다).
    var isEditSessionOpen: Bool
    /// 이 창 자신도 루트 오버레이라 떠 있는 동안은 다시 묻지 않는다.
    var hasRootOverlay: Bool

    var canAsk: Bool {
        isBudgetTabSelected && !hasRootToast && !hasBudgetToast && !isEditSessionOpen && !hasRootOverlay
    }
}

/// 창 모양별 글자와 주 버튼의 답(UI_GUIDE 205-206). 보조 버튼은 둘 다 `나중에` 다.
extension NotificationAskVariant {
    var confirmAnswer: NotificationAskAnswer {
        switch self {
        case .standard: .turnOn
        case .iosOff: .openSettings
        }
    }

    /// 본문 두 줄을 줄바꿈으로 잇는다 — 둘째 줄만 모양에 따라 다르다.
    func message(_ language: AppLanguage) -> String {
        let secondLine = switch self {
        case .standard: WoniStrings.notificationAskSettingsHint(language)
        case .iosOff: WoniStrings.notificationAskIOSOff(language)
        }
        return WoniStrings.notificationAskBody(language) + "\n" + secondLine
    }

    func confirmTitle(_ language: AppLanguage) -> String {
        switch self {
        case .standard: WoniStrings.notificationAskTurnOn(language)
        case .iosOff: WoniStrings.notificationAskOpenSettings(language)
        }
    }
}

extension NotificationToggleResult {
    /// 설정 줄을 누른 뒤의 완료 토스트. 보이는 값이 그대로면 없다(UI_GUIDE 208).
    func toastMessage(_ language: AppLanguage) -> String? {
        switch self {
        case .turnedOn: WoniStrings.notificationsTurnedOnToast(language)
        case .turnedOff: WoniStrings.notificationsTurnedOffToast(language)
        case .unchanged: nil
        }
    }
}
