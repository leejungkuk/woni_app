//
//  BaseCurrencyStoreTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct BaseCurrencyStoreTests {
    @Test("저장값이 없으면 KRW를 기본 통화로 사용한다")
    func defaultsToKRW() throws {
        try Self.withUserDefaultsSuite { userDefaults in
            let store = BaseCurrencyStore(userDefaults: userDefaults)

            #expect(store.baseCurrency == .krw)
        }
    }

    @Test("선택한 기본 통화를 같은 UserDefaults suite에서 복원한다")
    func persistsAndRestoresSelection() throws {
        try Self.withUserDefaultsSuite { userDefaults, suiteName in
            let store = BaseCurrencyStore(userDefaults: userDefaults)
            store.baseCurrency = .jpy

            let restoredDefaults = try #require(UserDefaults(suiteName: suiteName))
            let restoredStore = BaseCurrencyStore(userDefaults: restoredDefaults)

            #expect(restoredStore.baseCurrency == .jpy)
        }
    }

    @Test("알 수 없는 저장 rawValue는 KRW로 안전하게 폴백한다")
    func fallsBackToKRWForUnknownRawValue() throws {
        try Self.withUserDefaultsSuite { userDefaults in
            userDefaults.set("UNKNOWN", forKey: "woni.app.baseCurrency")

            let store = BaseCurrencyStore(userDefaults: userDefaults)

            #expect(store.baseCurrency == .krw)
        }
    }
}

private extension BaseCurrencyStoreTests {
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
        let suiteName = "woni_appTests.BaseCurrencyStoreTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try body(userDefaults, suiteName)
    }
}
