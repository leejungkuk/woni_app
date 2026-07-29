//
//  RateBackfillCoverageStore.swift
//  woni_app
//

import Foundation

@MainActor
final class RateBackfillCoverageStore {
    private let userDefaults: UserDefaults
    private static let storageKey = "woni.app.rateBackfillCoveredThrough"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var coveredThrough: String? {
        userDefaults.string(forKey: Self.storageKey)
    }

    func record(_ localDate: String) {
        userDefaults.set(localDate, forKey: Self.storageKey)
    }
}
