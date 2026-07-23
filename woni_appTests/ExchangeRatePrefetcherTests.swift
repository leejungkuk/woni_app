//
//  ExchangeRatePrefetcherTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct ExchangeRatePrefetcherTests {
    @Test("프리페치는 당일 snapshot의 유효한 baseDate 환율만 캐시에 저장한다")
    func prefetchTodayUpsertsRatesWithValidBaseDate() async throws {
        PrefetchExchangeRateURLProtocol.handler = { request in
            try makePrefetchResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": true,
                        "data": [
                            {
                                "currencyCode": "USD",
                                "currencyName": "미국 달러",
                                "tts": 1411.23,
                                "baseDate": "2026-07-17",
                                "stale": true
                            },
                            {
                                "currencyCode": "EUR",
                                "currencyName": "유로",
                                "tts": 1619.45,
                                "baseDate": "invalid-date",
                                "stale": true
                            }
                        ]
                    }
                    """.utf8
                )
            )
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let cache = PrefetchExchangeRateCacheSpy()
        let today = try prefetchSeoulDate(year: 2026, month: 7, day: 19)
        let prefetcher = ExchangeRatePrefetcher(
            service: ExchangeRateService(client: makePrefetchClient()),
            cache: cache,
            now: { today }
        )

        await prefetcher.prefetchToday()

        #expect(try cache.upsertSnapshots() == [[
            CachedExchangeRate(
                currencyCode: "USD",
                baseDate: "2026-07-17",
                tts: #require(Decimal(string: "1411.23"))
            )
        ]])
    }

    @Test("프리페치는 서비스 실패를 외부로 전파하지 않는다")
    func prefetchTodaySwallowsServiceFailure() async {
        PrefetchExchangeRateURLProtocol.handler = { _ in
            throw PrefetchExchangeRateTestError.transport
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let cache = PrefetchExchangeRateCacheSpy()
        let prefetcher = ExchangeRatePrefetcher(
            service: ExchangeRateService(client: makePrefetchClient()),
            cache: cache
        )

        await prefetcher.prefetchToday()

        #expect(cache.upsertSnapshots().isEmpty)
    }

    @Test("프로덕션 환율 배선은 프리페치 캐시를 서버 실패 시 cache quote로 잇는다")
    func productionExchangeRateWiringFeedsProviderCacheFallback() async throws {
        PrefetchExchangeRateURLProtocol.handler = { request in
            try makePrefetchResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": true,
                        "data": [{
                            "currencyCode": "USD",
                            "currencyName": "미국 달러",
                            "tts": 1411.23,
                            "baseDate": "2026-07-17",
                            "stale": true
                        }]
                    }
                    """.utf8
                )
            )
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let database = try AppDatabase.inMemory()
        let sunday = try prefetchSeoulDate(year: 2026, month: 7, day: 19)
        let exchangeRate = AppDependencyFactory.makeExchangeRateDependencies(
            database: database,
            seedRateProvider: RateProvider(seedData: emptyPrefetchSeedData()),
            service: ExchangeRateService(client: makePrefetchClient()),
            now: { sunday }
        )
        await exchangeRate.prefetchRates()

        PrefetchExchangeRateURLProtocol.handler = { _ in
            throw PrefetchExchangeRateTestError.transport
        }

        let quote = try #require(await exchangeRate.rateProvider.quote(for: .usd, on: sunday))

        #expect(quote.tts == Decimal(string: "1411.23"))
        #expect(try quote.baseDate == prefetchSeoulDate(year: 2026, month: 7, day: 17))
        #expect(quote.isStale)
        #expect(quote.source == .cache)
    }
}

private final class PrefetchExchangeRateCacheSpy: ExchangeRateCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var upserts: [[CachedExchangeRate]] = []

    func upsert(_ rates: [CachedExchangeRate]) async throws {
        lock.withLock {
            upserts.append(rates)
        }
    }

    func latestRate(
        for _: String,
        onOrBefore _: String
    ) async throws -> CachedExchangeRate? {
        nil
    }

    func upsertSnapshots() -> [[CachedExchangeRate]] {
        lock.withLock { upserts }
    }
}

private final class PrefetchExchangeRateURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: PrefetchExchangeRateTestError.missingHandler)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum PrefetchExchangeRateTestError: Error {
    case missingHandler
    case invalidResponse
    case transport
}

private func makePrefetchClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PrefetchExchangeRateURLProtocol.self]
    return APIClient(session: URLSession(configuration: configuration))
}

private func makePrefetchResponse(
    for request: URLRequest,
    data: Data
) throws -> (HTTPURLResponse, Data) {
    guard
        let url = request.url,
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
    else {
        throw PrefetchExchangeRateTestError.invalidResponse
    }
    return (response, data)
}

private func prefetchSeoulDate(year: Int, month: Int, day: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
    return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
}

private func emptyPrefetchSeedData() -> SeedData {
    SeedData(exchangeRates: [], expenseCategories: [], incomeCategories: [], assets: [])
}
