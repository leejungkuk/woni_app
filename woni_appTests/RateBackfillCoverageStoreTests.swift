//
//  RateBackfillCoverageStoreTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct RateBackfillCoverageStoreTests {
    @Test("기록이 없으면 coveredThrough는 nil이다")
    func defaultsToNil() throws {
        try Self.withUserDefaultsSuite { userDefaults in
            let store = RateBackfillCoverageStore(userDefaults: userDefaults)

            #expect(store.coveredThrough == nil)
        }
    }

    @Test("기록한 날짜를 같은 UserDefaults suite에서 복원한다")
    func persistsAndRestoresCoveredThrough() throws {
        try Self.withUserDefaultsSuite { userDefaults, suiteName in
            let store = RateBackfillCoverageStore(userDefaults: userDefaults)
            store.record("2026-08-01")

            let restoredDefaults = try #require(UserDefaults(suiteName: suiteName))
            let restoredStore = RateBackfillCoverageStore(userDefaults: restoredDefaults)

            #expect(restoredStore.coveredThrough == "2026-08-01")
        }
    }

    @Test("record는 기존 날짜를 마지막 값으로 덮어쓴다")
    func recordOverwritesCoveredThrough() throws {
        try Self.withUserDefaultsSuite { userDefaults in
            let store = RateBackfillCoverageStore(userDefaults: userDefaults)
            store.record("2026-07-31")
            store.record("2026-08-01")

            #expect(store.coveredThrough == "2026-08-01")
        }
    }
}

private extension RateBackfillCoverageStoreTests {
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
        let suiteName = "woni_appTests.RateBackfillCoverageStoreTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try body(userDefaults, suiteName)
    }
}
