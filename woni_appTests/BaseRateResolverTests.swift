//
//  BaseRateResolverTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@MainActor
struct BaseRateResolverTests {
    @Test("동일 날짜에 캐시와 시드가 모두 있으면 캐시 tts를 우선한다")
    func cacheTakesPriorityOverSeed() async throws {
        let date = "2026-07-02"
        let lookup = ExchangeRateCacheLookup(currencyCode: "USD", localDate: date)
        let cacheRate = try CachedExchangeRate(
            currencyCode: "USD",
            baseDate: date,
            tts: Self.decimal("1480.96")
        )
        let cache = FakeExchangeRateCache(ratesByLookup: [lookup: cacheRate])
        let resolver = try BaseRateResolver(
            cache: cache,
            seedRateProvider: Self.seedRateProvider(
                currency: .usd,
                tts: Self.decimal("1400.00"),
                baseDate: date
            )
        )

        let result = await resolver.ttsByDate(for: .usd, dates: [date])

        #expect(try result == [date: Self.decimal("1480.96")])
        #expect(cache.lookupSnapshots() == [lookup])
    }

    @Test("캐시 miss면 요청일 이하의 시드 tts로 폴백한다")
    func fallsBackToSeedOnCacheMiss() async throws {
        let date = "2026-07-03"
        let resolver = try BaseRateResolver(
            cache: FakeExchangeRateCache(),
            seedRateProvider: Self.seedRateProvider(
                currency: .jpy,
                tts: Self.decimal("904.76"),
                baseDate: "2026-07-02"
            )
        )

        let result = await resolver.ttsByDate(for: .jpy, dates: [date])

        #expect(try result == [date: Self.decimal("904.76")])
    }

    @Test("빈 캐시는 번들 시드 하한 날짜의 CNY tts로 폴백한다")
    func resolvesBundledSeedLowerBoundOnCacheMiss() async throws {
        let resolver = try BaseRateResolver(
            cache: FakeExchangeRateCache(),
            seedRateProvider: RateProvider(seedData: SeedLoader().load())
        )

        let result = await resolver.ttsByDate(for: .cny, dates: ["2024-07-29"])

        #expect(try result["2024-07-29"] == (Self.decimal("193.010000")))
    }

    @Test("캐시와 시드 양쪽에 환율이 없으면 해당 날짜를 제외한다")
    func excludesDateWhenBothSourcesMiss() async {
        let resolver = BaseRateResolver(
            cache: FakeExchangeRateCache(),
            seedRateProvider: Self.emptySeedRateProvider()
        )

        let result = await resolver.ttsByDate(for: .usd, dates: ["2026-07-02"])

        #expect(result.isEmpty)
    }

    @Test("한 날짜의 캐시 read 오류가 다른 날짜 결과를 지우지 않고 시드 폴백도 계속한다")
    func isolatesCacheReadFailureByDate() async throws {
        let failedDate = "2026-07-02"
        let cachedDate = "2026-07-03"
        let failedLookup = ExchangeRateCacheLookup(currencyCode: "USD", localDate: failedDate)
        let cachedLookup = ExchangeRateCacheLookup(currencyCode: "USD", localDate: cachedDate)
        let cache = try FakeExchangeRateCache(
            ratesByLookup: [
                cachedLookup: CachedExchangeRate(
                    currencyCode: "USD",
                    baseDate: cachedDate,
                    tts: Self.decimal("1500.00")
                )
            ],
            failingLookups: [failedLookup]
        )
        let resolver = try BaseRateResolver(
            cache: cache,
            seedRateProvider: Self.seedRateProvider(
                currency: .usd,
                tts: Self.decimal("1400.00"),
                baseDate: failedDate
            )
        )

        let result = await resolver.ttsByDate(for: .usd, dates: [failedDate, cachedDate])

        #expect(try result == [
            failedDate: Self.decimal("1400.00"),
            cachedDate: Self.decimal("1500.00")
        ])
        #expect(Set(cache.lookupSnapshots()) == [failedLookup, cachedLookup])
    }

    @Test("0·음수 tts는 캐시와 시드 어느 쪽에서도 결과에 포함하지 않는다")
    func excludesNonPositiveRates() async {
        let zeroDate = "2026-07-02"
        let negativeDate = "2026-07-03"
        let zeroLookup = ExchangeRateCacheLookup(currencyCode: "USD", localDate: zeroDate)
        let cache = FakeExchangeRateCache(ratesByLookup: [
            zeroLookup: CachedExchangeRate(
                currencyCode: "USD",
                baseDate: zeroDate,
                tts: Decimal(0)
            )
        ])
        let resolver = BaseRateResolver(
            cache: cache,
            seedRateProvider: Self.seedRateProvider(
                currency: .usd,
                tts: Decimal(-1),
                baseDate: negativeDate
            )
        )

        let result = await resolver.ttsByDate(for: .usd, dates: [zeroDate, negativeDate])

        #expect(result.isEmpty)
    }

    @Test("base가 KRW면 캐시를 조회하지 않고 빈 결과를 반환한다")
    func returnsEmptyImmediatelyForKRW() async {
        let cache = FakeExchangeRateCache()
        let resolver = BaseRateResolver(
            cache: cache,
            seedRateProvider: Self.emptySeedRateProvider()
        )

        let result = await resolver.ttsByDate(for: .krw, dates: ["2026-07-02"])

        #expect(result.isEmpty)
        #expect(cache.lookupSnapshots().isEmpty)
    }
}

private extension BaseRateResolverTests {
    static func decimal(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
    }

    static func seedRateProvider(
        currency: CurrencyCode,
        tts: Decimal,
        baseDate: String
    ) -> RateProvider {
        RateProvider(seedData: SeedData(
            exchangeRates: [
                SeedExchangeRate(
                    currencyCode: currency,
                    currencyName: currency.rawValue,
                    tts: tts,
                    baseDate: baseDate,
                    stale: false
                )
            ],
            expenseCategories: [],
            incomeCategories: [],
            assets: []
        ))
    }

    static func emptySeedRateProvider() -> RateProvider {
        RateProvider(seedData: SeedData(
            exchangeRates: [],
            expenseCategories: [],
            incomeCategories: [],
            assets: []
        ))
    }
}
