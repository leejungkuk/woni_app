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

        let override = userDefaults.string(forKey: Self.overrideKey).flatMap(AppLanguage.init(rawValue:))
        if let override {
            language = override
        } else {
            language = AppLanguage.resolved(from: systemLocale)
        }
    }
}
