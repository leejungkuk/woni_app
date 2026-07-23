//
//  ExchangeRateCacheRepositoryTests.swift
//  woni_appTests
//

import Foundation
import GRDB
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct ExchangeRateCacheRepositoryTests {
    @Test("upsert는 같은 배열에 멱등이고 같은 PK의 tts를 교체한다")
    func upsertIsIdempotentAndReplacesMatchingPrimaryKey() async throws {
        let database = try AppDatabase.inMemory()
        let repository = ExchangeRateCacheRepository(database: database)
        let initialRates = try [
            CachedExchangeRate(
                currencyCode: "USD",
                baseDate: "2026-07-23",
                tts: Self.decimal("1569.94")
            ),
            CachedExchangeRate(
                currencyCode: "JPY(100)",
                baseDate: "2026-07-23",
                tts: Self.decimal("1046.28")
            )
        ]

        try await repository.upsert(initialRates)
        try await repository.upsert(initialRates)

        let idempotentCount = try await database.read { @Sendable db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rate_cache") ?? 0
        }
        #expect(idempotentCount == 2)

        let replacement = try CachedExchangeRate(
            currencyCode: "USD",
            baseDate: "2026-07-23",
            tts: Self.decimal("1570.01")
        )
        try await repository.upsert([replacement])

        #expect(try await repository.latestRate(
            for: "USD",
            onOrBefore: "2026-07-23"
        ) == replacement)
        let replacedCount = try await database.read { @Sendable db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exchange_rate_cache") ?? 0
        }
        #expect(replacedCount == 2)
    }

    @Test("latestRate는 같은 날 또는 이전 최신값만 반환하고 미래값은 반환하지 않는다")
    func latestRateHonorsAsOfBoundary() async throws {
        let database = try AppDatabase.inMemory()
        let repository = ExchangeRateCacheRepository(database: database)
        let earlier = try CachedExchangeRate(
            currencyCode: "USD",
            baseDate: "2026-07-18",
            tts: Self.decimal("1550.10")
        )
        let sameDay = try CachedExchangeRate(
            currencyCode: "USD",
            baseDate: "2026-07-20",
            tts: Self.decimal("1569.94")
        )
        let futureOnly = try CachedExchangeRate(
            currencyCode: "EUR",
            baseDate: "2026-07-25",
            tts: Self.decimal("1830.25")
        )
        try await repository.upsert([earlier, sameDay, futureOnly])

        #expect(try await repository.latestRate(
            for: "USD",
            onOrBefore: "2026-07-20"
        ) == sameDay)
        #expect(try await repository.latestRate(
            for: "USD",
            onOrBefore: "2026-07-19"
        ) == earlier)
        #expect(try await repository.latestRate(
            for: "EUR",
            onOrBefore: "2026-07-24"
        ) == nil)
    }

    @Test("tts는 Decimal을 TEXT로 변환해 정밀도 손실 없이 왕복한다")
    func decimalRoundTripsThroughTextWithoutPrecisionLoss() async throws {
        let database = try AppDatabase.inMemory()
        let repository = ExchangeRateCacheRepository(database: database)
        let expected = try CachedExchangeRate(
            currencyCode: "USD",
            baseDate: "2026-07-23",
            tts: Self.decimal("1569.94")
        )

        try await repository.upsert([expected])

        let stored: (type: String, text: String) = try await database.read { @Sendable db in
            let row = try #require(try Row.fetchOne(
                db,
                sql: "SELECT typeof(tts) AS storage_type, tts FROM exchange_rate_cache"
            ))
            return (row["storage_type"], row["tts"])
        }
        let loaded = try #require(try await repository.latestRate(
            for: "USD",
            onOrBefore: "2026-07-23"
        ))

        #expect(stored.type == "text")
        #expect(stored.text == "1569.94")
        #expect(loaded == expected)
        #expect(DecimalTextConversion.string(from: loaded.tts) == "1569.94")
    }

    private static func decimal(_ text: String) throws -> Decimal {
        try #require(DecimalTextConversion.decimal(from: text))
    }
}
