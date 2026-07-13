import Foundation
import Observation

@Observable
@MainActor
final class AppLanguageStore {
    var language: AppLanguage {
        didSet {
            userDefaults.set(language.rawValue, forKey: Self.overrideKey)
        }
    }

    private let userDefaults: UserDefaults
    private static let overrideKey = "woni.app.language.override"

    init(userDefaults: UserDefaults = .standard, systemLocale: Locale = .current) {
        self.userDefaults = userDefaults

        if let rawValue = userDefaults.string(forKey: Self.overrideKey),
           let override = AppLanguage(rawValue: rawValue) {
            language = override
        } else {
            language = AppLanguage.resolved(from: systemLocale)
        }
    }
}
