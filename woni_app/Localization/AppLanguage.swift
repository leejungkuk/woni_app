import Foundation

enum AppLanguage: String, CaseIterable {
    case ko
    case en

    static func resolved(from locale: Locale) -> AppLanguage {
        languageCode(locale: locale) == "ko" ? .ko : .en
    }

    static func languageCode(locale: Locale) -> String {
        if #available(iOS 16, *) {
            return locale.language.languageCode?.identifier ?? "en"
        } else {
            return locale.languageCode ?? "en"
        }
    }
}
