import SwiftUI

/// 설정 탭 "알림" 줄(UI_GUIDE 208). 스위치 없이 값 행에 "켜짐"/"꺼짐"이다. 값·누른 뒤의 동작·토스트를 띄울지는
/// `NotificationPreferenceController` 가 정한다.
struct NotificationSettingsRow: View {
    @Environment(AppLanguageStore.self) private var languageStore

    let preference: NotificationPreferenceController
    /// 완료 토스트는 루트가 띄운다.
    let onToast: (String) -> Void

    var body: some View {
        let language = languageStore.language
        SettingsRow(
            title: WoniStrings.notificationsRow(language),
            value: preference.isEffectivelyOn
                ? WoniStrings.notificationsOn(language)
                : WoniStrings.notificationsOff(language)
        ) {
            Task {
                let result = await preference.toggleFromSettings()
                if let message = result.toastMessage(languageStore.language) {
                    onToast(message)
                }
            }
        }
        .accessibilityIdentifier("settings.row.notifications")
    }
}
