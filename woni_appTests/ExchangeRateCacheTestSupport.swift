//
//  ExchangeRateCacheTestSupport.swift
//  woni_appTests
//

import Foundation
@testable import woni_app

struct ExchangeRateCacheLookup: Hashable {
    let currencyCode: String
    let localDate: String
}

enum FakeExchangeRateCacheError: Error {
    case configuredReadFailure
}

final class FakeExchangeRateCache: ExchangeRateCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var ratesByLookup: [ExchangeRateCacheLookup: CachedExchangeRate]
    private let failingLookups: Set<ExchangeRateCacheLookup>
    private var recordedUpserts: [[CachedExchangeRate]] = []
    private var recordedLookups: [ExchangeRateCacheLookup] = []

    init(
        ratesByLookup: [ExchangeRateCacheLookup: CachedExchangeRate] = [:],
        failingLookups: Set<ExchangeRateCacheLookup> = []
    ) {
        self.ratesByLookup = ratesByLookup
        self.failingLookups = failingLookups
    }

    func upsert(_ rates: [CachedExchangeRate]) async throws {
        lock.withLock {
            recordedUpserts.append(rates)
            for rate in rates {
                let lookup = ExchangeRateCacheLookup(
                    currencyCode: rate.currencyCode,
                    localDate: rate.baseDate
                )
                ratesByLookup[lookup] = rate
            }
        }
    }

    func latestRate(
        for currencyCode: String,
        onOrBefore localDate: String
    ) async throws -> CachedExchangeRate? {
        let lookup = ExchangeRateCacheLookup(currencyCode: currencyCode, localDate: localDate)

        return try lock.withLock {
            recordedLookups.append(lookup)
            if failingLookups.contains(lookup) {
                throw FakeExchangeRateCacheError.configuredReadFailure
            }
            return ratesByLookup[lookup]
        }
    }

    func upsertSnapshots() -> [[CachedExchangeRate]] {
        lock.withLock { recordedUpserts }
    }

    func lookupSnapshots() -> [ExchangeRateCacheLookup] {
        lock.withLock { recordedLookups }
    }
}
