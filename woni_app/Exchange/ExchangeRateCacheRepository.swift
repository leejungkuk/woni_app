//
//  ExchangeRateCacheRepository.swift
//  woni_app
//

import Foundation
import GRDB

struct CachedExchangeRate: Equatable {
    let currencyCode: String
    let baseDate: String
    let tts: Decimal
}

protocol ExchangeRateCaching: Sendable {
    func upsert(_ rates: [CachedExchangeRate]) async throws

    /// currencyCode의 baseDate가 localDate 이하인 행 중 가장 최신 환율을 반환한다.
    func latestRate(
        for currencyCode: String,
        onOrBefore localDate: String
    ) async throws -> CachedExchangeRate?
}

struct ExchangeRateCacheRepository: ExchangeRateCaching {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func upsert(_ rates: [CachedExchangeRate]) async throws {
        let storedRates = rates.map {
            StoredCachedExchangeRate(
                currencyCode: $0.currencyCode,
                baseDate: $0.baseDate,
                tts: DecimalTextConversion.string(from: $0.tts)
            )
        }

        try await database.write { @Sendable db in
            for rate in storedRates {
                try db.execute(
                    sql: """
                    INSERT INTO exchange_rate_cache (currency_code, base_date, tts)
                    VALUES (?, ?, ?)
                    ON CONFLICT(currency_code, base_date) DO UPDATE SET
                        tts = excluded.tts
                    """,
                    arguments: [rate.currencyCode, rate.baseDate, rate.tts]
                )
            }
        }
    }

    func latestRate(
        for currencyCode: String,
        onOrBefore localDate: String
    ) async throws -> CachedExchangeRate? {
        try await database.read { @Sendable db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT currency_code, base_date, tts
                FROM exchange_rate_cache
                WHERE currency_code = ? AND base_date <= ?
                ORDER BY base_date DESC
                LIMIT 1
                """,
                arguments: [currencyCode, localDate]
            ) else {
                return nil
            }

            let ttsText: String = row["tts"]
            guard let tts = DecimalTextConversion.decimal(from: ttsText) else {
                throw ExchangeRateCacheRepositoryError.invalidTTS(ttsText)
            }

            return CachedExchangeRate(
                currencyCode: row["currency_code"],
                baseDate: row["base_date"],
                tts: tts
            )
        }
    }
}

private struct StoredCachedExchangeRate {
    let currencyCode: String
    let baseDate: String
    let tts: String
}

private enum ExchangeRateCacheRepositoryError: Error {
    case invalidTTS(String)
}
