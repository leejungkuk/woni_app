import Foundation
import Observation

@Observable
@MainActor
final class BaseCurrencyStore {
    var baseCurrency: SelectableCurrency {
        didSet {
            userDefaults.set(baseCurrency.rawValue, forKey: Self.storageKey)
        }
    }

    private let userDefaults: UserDefaults
    private static let storageKey = "woni.app.baseCurrency"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        baseCurrency = userDefaults.string(forKey: Self.storageKey)
            .flatMap(SelectableCurrency.init(rawValue:)) ?? .krw
    }
}
