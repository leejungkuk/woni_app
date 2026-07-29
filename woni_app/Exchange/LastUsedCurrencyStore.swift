import Foundation

@MainActor
final class LastUsedCurrencyStore {
    private let userDefaults: UserDefaults
    private static let storageKey = "woni.app.lastUsedCurrency"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var lastUsedCurrency: SelectableCurrency? {
        userDefaults.string(forKey: Self.storageKey)
            .flatMap(SelectableCurrency.init(rawValue:))
    }

    func record(_ currency: SelectableCurrency) {
        userDefaults.set(currency.rawValue, forKey: Self.storageKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }
}
