import SwiftUI

struct LanguageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageStore.self) private var languageStore

    private var language: AppLanguage {
        languageStore.language
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: WoniStrings.languageRow(language), backLabel: WoniStrings.back(language)) {
                dismiss()
            }
            .zIndex(1)

            Spacer()
                .frame(height: 8)

            LanguageOptionRow(
                title: WoniStrings.languageKorean(language),
                isSelected: language == .ko,
                accessibilityIdentifier: "settings.language.option.ko"
            ) {
                languageStore.language = .ko
            }

            LanguageOptionRow(
                title: WoniStrings.languageEnglish(language),
                isSelected: language == .en,
                accessibilityIdentifier: "settings.language.option.en"
            ) {
                languageStore.language = .en
            }

            Spacer()
        }
        .background(WoniColor.gray00)
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled()
    }
}
