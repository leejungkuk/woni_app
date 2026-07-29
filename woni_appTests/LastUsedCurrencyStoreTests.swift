//
//  LastUsedCurrencyStoreTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct LastUsedCurrencyStoreTests {
    @Test("저장값이 없으면 마지막 사용 통화가 없다")
    func returnsNilWhenNoCurrencyIsStored() throws {
        try Self.withUserDefaultsSuite { userDefaults in
            let store = LastUsedCurrencyStore(userDefaults: userDefaults)

            #expect(store.lastUsedCurrency == nil)
        }
    }

    @Test("기록한 통화를 같은 UserDefaults suite에서 복원하고 지울 수 있다")
    func persistsRestoresAndClearsCurrency() throws {
        try Self.withUserDefaultsSuite { userDefaults, suiteName in
            let store = LastUsedCurrencyStore(userDefaults: userDefaults)
            store.record(.thb)

            let restoredDefaults = try #require(UserDefaults(suiteName: suiteName))
            let restoredStore = LastUsedCurrencyStore(userDefaults: restoredDefaults)

            #expect(restoredStore.lastUsedCurrency == .thb)

            restoredStore.clear()

            #expect(restoredStore.lastUsedCurrency == nil)
        }
    }

    @Test("알 수 없는 저장 rawValue는 마지막 사용 통화가 없는 것으로 처리한다")
    func returnsNilForUnknownRawValue() throws {
        try Self.withUserDefaultsSuite { userDefaults in
            userDefaults.set("UNKNOWN", forKey: "woni.app.lastUsedCurrency")

            let store = LastUsedCurrencyStore(userDefaults: userDefaults)

            #expect(store.lastUsedCurrency == nil)
        }
    }
}

private extension LastUsedCurrencyStoreTests {
    static func withUserDefaultsSuite(
        _ body: (UserDefaults) throws -> Void
    ) throws {
        try withUserDefaultsSuite { userDefaults, _ in
            try body(userDefaults)
        }
    }

    static func withUserDefaultsSuite(
        _ body: (UserDefaults, String) throws -> Void
    ) throws {
        let suiteName = "woni_appTests.LastUsedCurrencyStoreTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try body(userDefaults, suiteName)
    }
}
