//
//  ExchangeRatePrefetcherTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

// swiftlint:disable file_length
@Suite(.serialized)
@MainActor
struct ExchangeRatePrefetcherTests {
    @Test("갭이 0일이면 range 요청을 보내지 않는다")
    func zeroGapSkipsNetworkRequest() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in emptyRangeResponse() }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage(initial: "2026-07-29")
        defer { coverage.cleanup() }
        let cache = PrefetchExchangeRateCacheSpy()
        let today = try prefetchDate("2026-07-29")
        let prefetcher = makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: "2026-07-28",
            today: today
        )

        await prefetcher.backfillMissingRates()

        #expect(recorder.snapshot().isEmpty)
        #expect(cache.upsertSnapshots().isEmpty)
        #expect(coverage.store.coveredThrough == "2026-07-29")
    }

    @Test("정확히 400일 갭은 양끝 포함 한 번의 요청으로 백필한다")
    func exactlyFourHundredDaysUsesOneRequest() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in emptyRangeResponse() }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage()
        defer { coverage.cleanup() }
        let cache = PrefetchExchangeRateCacheSpy()
        let today = try prefetchDate("2026-07-29")
        let seedDate = try prefetchAddingDays(-400, to: today)
        let startDate = try prefetchAddingDays(1, to: seedDate)
        let prefetcher = makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: prefetchDateText(seedDate),
            today: today
        )

        await prefetcher.backfillMissingRates()

        #expect(recorder.snapshot() == [
            PrefetchRangeRequest(
                from: prefetchDateText(startDate),
                to: prefetchDateText(today)
            )
        ])
        #expect(cache.upsertSnapshots() == [[]])
    }

    @Test("401일 갭은 경계가 겹치거나 벌어지지 않는 두 요청으로 나눈다")
    func fourHundredOneDaysUsesTwoContiguousRequests() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in emptyRangeResponse() }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage()
        defer { coverage.cleanup() }
        let today = try prefetchDate("2026-07-29")
        let seedDate = try prefetchAddingDays(-401, to: today)
        let startDate = try prefetchAddingDays(1, to: seedDate)
        let firstEnd = try prefetchAddingDays(399, to: startDate)
        let secondStart = try prefetchAddingDays(1, to: firstEnd)
        let prefetcher = makePrefetcher(
            cache: PrefetchExchangeRateCacheSpy(),
            coverageStore: coverage.store,
            seedCoveredThrough: prefetchDateText(seedDate),
            today: today
        )

        await prefetcher.backfillMissingRates()

        #expect(recorder.snapshot() == [
            PrefetchRangeRequest(
                from: prefetchDateText(startDate),
                to: prefetchDateText(firstEnd)
            ),
            PrefetchRangeRequest(
                from: prefetchDateText(secondStart),
                to: prefetchDateText(today)
            )
        ])
    }

    @Test("빈 응답이어도 커서를 전진시켜 다음 청크를 요청한다")
    func emptyResponseContinuesToNextChunk() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in emptyRangeResponse() }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage()
        defer { coverage.cleanup() }
        let today = try prefetchDate("2026-07-29")
        let seedDate = try prefetchAddingDays(-401, to: today)
        let cache = PrefetchExchangeRateCacheSpy()
        let prefetcher = makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: prefetchDateText(seedDate),
            today: today
        )

        await prefetcher.backfillMissingRates()

        #expect(recorder.snapshot().count == 2)
        #expect(cache.upsertSnapshots() == [[], []])
        #expect(coverage.store.coveredThrough == nil)
    }
}

// MARK: - 마커 전진 규칙

extension ExchangeRatePrefetcherTests {
    @Test("오늘이 부분 적재면 받은 행은 저장하되 마커는 오늘로 전진하지 않는다")
    func partialTodayUpsertsRowsWithoutAdvancingMarker() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in
            rangeResponse(rows: [rateRow(.usd, baseDate: "2026-07-29", tts: "1411.23")])
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage(initial: "2026-07-28")
        defer { coverage.cleanup() }
        let cache = PrefetchExchangeRateCacheSpy()
        let prefetcher = try makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: "2026-07-01",
            today: prefetchDate("2026-07-29")
        )

        await prefetcher.backfillMissingRates()

        #expect(try cache.upsertSnapshots() == [[
            CachedExchangeRate(
                currencyCode: "USD",
                baseDate: "2026-07-29",
                tts: #require(Decimal(string: "1411.23"))
            )
        ]])
        #expect(coverage.store.coveredThrough == "2026-07-28")
    }

    @Test("KST 자정이 아닌 시각에도 오늘 부분 적재는 마커를 전진시키지 않는다")
    func nonMidnightNowStillProtectsPartialToday() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in
            rangeResponse(rows: [rateRow(.usd, baseDate: "2026-07-30", tts: "1411.23")])
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage(initial: "2026-07-29")
        defer { coverage.cleanup() }
        let cache = PrefetchExchangeRateCacheSpy()
        // 수집(11:05 KST) 이전인 2026-07-30 08:30 KST. 자정으로 절삭하지 않으면 오늘 행이
        // `D < today`로 분류돼 마커가 오늘로 올라가고 그날 환율을 하루 종일 놓친다.
        let beforeCollection = try prefetchDate("2026-07-30").addingTimeInterval(8.5 * 3600)
        let prefetcher = makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: nil,
            today: beforeCollection
        )

        await prefetcher.backfillMissingRates()

        #expect(recorder.snapshot() == [
            PrefetchRangeRequest(from: "2026-07-30", to: "2026-07-30")
        ])
        #expect(cache.upsertSnapshots().first?.count == 1)
        #expect(coverage.store.coveredThrough == "2026-07-29")
    }

    @Test("오늘 외화 12종이 완비되면 마커를 오늘로 전진한다")
    func completeTodayAdvancesMarkerToToday() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in
            rangeResponse(rows: completeForeignCurrencyRows(baseDate: "2026-07-29"))
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage(initial: "2026-07-28")
        defer { coverage.cleanup() }
        let cache = PrefetchExchangeRateCacheSpy()
        let prefetcher = try makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: nil,
            today: prefetchDate("2026-07-29")
        )

        await prefetcher.backfillMissingRates()

        #expect(cache.upsertSnapshots().first?.count == 12)
        #expect(coverage.store.coveredThrough == "2026-07-29")
    }

    @Test("과거 부분 적재일은 이후 청크와 마커 전진을 막지 않는다")
    func partialPastDateDoesNotDeadlockLaterChunks() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { request in
            if request.to == "2026-07-28" {
                return rangeResponse(rows: [rateRow(.usd, baseDate: "2026-07-28")])
            }
            return rangeResponse(rows: completeForeignCurrencyRows(baseDate: "2026-07-29"))
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage()
        defer { coverage.cleanup() }
        let today = try prefetchDate("2026-07-29")
        let seedDate = try prefetchAddingDays(-401, to: today)
        let cache = PrefetchExchangeRateCacheSpy()
        let prefetcher = makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: prefetchDateText(seedDate),
            today: today
        )

        await prefetcher.backfillMissingRates()

        #expect(recorder.snapshot().count == 2)
        #expect(cache.upsertSnapshots().map(\.count) == [1, 12])
        #expect(coverage.store.coveredThrough == "2026-07-29")
    }

    @Test("KRW 행이 섞여도 오늘 외화 12종 완비 판정이 성립한다")
    func krwRowDoesNotPreventCompleteTodayMarker() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in
            rangeResponse(
                rows: completeForeignCurrencyRows(baseDate: "2026-07-29")
                    + [rateRow(.krw, baseDate: "2026-07-29", tts: "1")]
            )
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage(initial: "2026-07-28")
        defer { coverage.cleanup() }
        let cache = PrefetchExchangeRateCacheSpy()
        let prefetcher = try makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: nil,
            today: prefetchDate("2026-07-29")
        )

        await prefetcher.backfillMissingRates()

        #expect(cache.upsertSnapshots().first?.count == 13)
        #expect(coverage.store.coveredThrough == "2026-07-29")
    }

    @Test("baseDate 파싱 실패 행이 있으면 유효행만 저장하고 마커는 보류한다")
    func invalidBaseDateUpsertsValidRowsWithoutAdvancingMarker() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in
            rangeResponse(rows: [
                rateRow(.usd, baseDate: "invalid-date"),
                rateRow(.eur, baseDate: "2026-07-28", tts: "1619.45")
            ])
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage(initial: "2026-07-26")
        defer { coverage.cleanup() }
        let cache = PrefetchExchangeRateCacheSpy()
        let prefetcher = try makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: nil,
            today: prefetchDate("2026-07-29")
        )

        await prefetcher.backfillMissingRates()

        #expect(try cache.upsertSnapshots() == [[
            CachedExchangeRate(
                currencyCode: "EUR",
                baseDate: "2026-07-28",
                tts: #require(Decimal(string: "1619.45"))
            )
        ]])
        #expect(coverage.store.coveredThrough == "2026-07-26")
    }

    @Test("두 번째 청크 실패 시 첫 결과를 유지하고 같은 청크를 재시도하지 않는다")
    func secondChunkFailureKeepsFirstChunkAndStopsLoop() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        let today = try prefetchDate("2026-07-29")
        let seedDate = try prefetchAddingDays(-801, to: today)
        let firstStart = try prefetchAddingDays(1, to: seedDate)
        let firstEnd = try prefetchAddingDays(399, to: firstStart)
        let secondStart = try prefetchAddingDays(1, to: firstEnd)
        let secondEnd = try prefetchAddingDays(399, to: secondStart)
        stubRangeRequests(recorder: recorder) { request in
            if request.from == prefetchDateText(secondStart) {
                throw PrefetchExchangeRateTestError.transport
            }
            return rangeResponse(rows: [rateRow(.usd, baseDate: request.to)])
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage()
        defer { coverage.cleanup() }
        let cache = PrefetchExchangeRateCacheSpy()
        let prefetcher = makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: prefetchDateText(seedDate),
            today: today
        )

        await prefetcher.backfillMissingRates()

        #expect(recorder.snapshot() == [
            PrefetchRangeRequest(
                from: prefetchDateText(firstStart),
                to: prefetchDateText(firstEnd)
            ),
            PrefetchRangeRequest(
                from: prefetchDateText(secondStart),
                to: prefetchDateText(secondEnd)
            )
        ])
        #expect(cache.upsertSnapshots().count == 1)
        #expect(cache.upsertSnapshots().first?.first?.baseDate == prefetchDateText(firstEnd))
        #expect(coverage.store.coveredThrough == prefetchDateText(firstEnd))
    }

    @Test("캐시 upsert 실패 시 마커를 전진시키지 않는다")
    func upsertFailureKeepsMarkerUnchanged() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in
            rangeResponse(rows: [rateRow(.usd, baseDate: "2026-07-28")])
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage(initial: "2026-07-27")
        defer { coverage.cleanup() }
        let cache = PrefetchExchangeRateCacheSpy(failingUpsertCall: 1)
        let prefetcher = try makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: nil,
            today: prefetchDate("2026-07-29")
        )

        await prefetcher.backfillMissingRates()

        #expect(recorder.snapshot().count == 1)
        #expect(coverage.store.coveredThrough == "2026-07-27")
    }

    @Test("시드와 마커가 모두 없으면 백필을 생략한다")
    func missingSeedAndMarkerSkipsBackfill() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in emptyRangeResponse() }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage()
        defer { coverage.cleanup() }
        let cache = PrefetchExchangeRateCacheSpy()
        let prefetcher = try makePrefetcher(
            cache: cache,
            coverageStore: coverage.store,
            seedCoveredThrough: nil,
            today: prefetchDate("2026-07-29")
        )

        await prefetcher.backfillMissingRates()

        #expect(recorder.snapshot().isEmpty)
        #expect(cache.upsertSnapshots().isEmpty)
    }

    @Test("백필 실패를 삼켜 포그라운드 활성화 체인의 signal 갱신을 막지 않는다")
    func backfillFailureDoesNotStopForegroundActivation() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in
            throw PrefetchExchangeRateTestError.transport
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage(initial: "2026-07-28")
        defer { coverage.cleanup() }
        let prefetcher = try makePrefetcher(
            cache: PrefetchExchangeRateCacheSpy(),
            coverageStore: coverage.store,
            seedCoveredThrough: nil,
            today: prefetchDate("2026-07-29")
        )
        let signal = ForegroundActivationSignal()
        let sync = PrefetchForegroundSyncSpy()
        let coordinator = makeTestSessionCoordinator(
            authProvider: FakeAuthService(probeSessionValidityHandler: { true })
        )

        await AppDependencies.handleForegroundActivation(
            sync: sync,
            coordinator: coordinator,
            prefetchRates: { await prefetcher.backfillMissingRates() },
            signal: signal
        )

        #expect(recorder.snapshot().count == 1)
        #expect(signal.revision == 1)
    }

    @Test("프로덕션 환율 배선은 synthetic 시드 상한부터 백필해 cache fallback으로 잇는다")
    func productionExchangeRateWiringFeedsProviderCacheFallback() async throws {
        let recorder = PrefetchRangeRequestRecorder()
        stubRangeRequests(recorder: recorder) { _ in
            rangeResponse(rows: [
                rateRow(.usd, baseDate: "2026-07-17", tts: "1411.23")
            ])
        }
        defer { PrefetchExchangeRateURLProtocol.handler = nil }
        let coverage = try makePrefetchCoverage()
        defer { coverage.cleanup() }
        let database = try AppDatabase.inMemory()
        let sunday = try prefetchDate("2026-07-19")
        let exchangeRate = try AppDependencyFactory.makeExchangeRateDependencies(
            database: database,
            seedRateProvider: RateProvider(
                seedData: syntheticPrefetchSeedData(latestBaseDate: "2026-07-16")
            ),
            service: ExchangeRateService(client: makePrefetchClient()),
            coverageStore: coverage.store,
            now: { sunday }
        )
        await exchangeRate.prefetchRates()

        PrefetchExchangeRateURLProtocol.handler = { _ in
            throw PrefetchExchangeRateTestError.transport
        }

        let quote = try #require(await exchangeRate.rateProvider.quote(for: .usd, on: sunday))

        #expect(recorder.snapshot() == [
            PrefetchRangeRequest(from: "2026-07-17", to: "2026-07-19")
        ])
        #expect(quote.tts == Decimal(string: "1411.23"))
        #expect(try quote.baseDate == prefetchDate("2026-07-17"))
        #expect(quote.isStale)
        #expect(quote.source == .cache)
    }
}

@MainActor
private final class PrefetchForegroundSyncSpy: ForegroundSyncing {
    func pushPending() async {}
    func pullChanges() async throws {}
}

private final class PrefetchExchangeRateCacheSpy: ExchangeRateCaching, @unchecked Sendable {
    private let lock = NSLock()
    private let failingUpsertCall: Int?
    private var upserts: [[CachedExchangeRate]] = []

    init(failingUpsertCall: Int? = nil) {
        self.failingUpsertCall = failingUpsertCall
    }

    func upsert(_ rates: [CachedExchangeRate]) async throws {
        let callCount = lock.withLock { () -> Int in
            upserts.append(rates)
            return upserts.count
        }
        if callCount == failingUpsertCall {
            throw PrefetchExchangeRateTestError.cacheWrite
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

private struct PrefetchRangeRequest: Equatable {
    let from: String
    let to: String
}

private final class PrefetchRangeRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [PrefetchRangeRequest] = []

    func record(_ request: PrefetchRangeRequest) {
        lock.withLock {
            requests.append(request)
        }
    }

    func snapshot() -> [PrefetchRangeRequest] {
        lock.withLock { requests }
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
    case invalidRequest
    case invalidResponse
    case transport
    case cacheWrite
}

@MainActor
private struct PrefetchCoverageFixture {
    let suiteName: String
    let userDefaults: UserDefaults
    let store: RateBackfillCoverageStore

    func cleanup() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private func makePrefetchCoverage(initial: String? = nil) throws -> PrefetchCoverageFixture {
    let suiteName = "woni_appTests.ExchangeRatePrefetcherTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    let store = RateBackfillCoverageStore(userDefaults: userDefaults)
    if let initial {
        store.record(initial)
    }
    return PrefetchCoverageFixture(
        suiteName: suiteName,
        userDefaults: userDefaults,
        store: store
    )
}

@MainActor
private func makePrefetcher(
    cache: any ExchangeRateCaching,
    coverageStore: RateBackfillCoverageStore,
    seedCoveredThrough: String?,
    today: Date
) -> ExchangeRatePrefetcher {
    ExchangeRatePrefetcher(
        service: ExchangeRateService(client: makePrefetchClient()),
        cache: cache,
        coverageStore: coverageStore,
        seedCoveredThrough: seedCoveredThrough,
        now: { today }
    )
}

private func makePrefetchClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PrefetchExchangeRateURLProtocol.self]
    return APIClient(session: URLSession(configuration: configuration))
}

private func stubRangeRequests(
    recorder: PrefetchRangeRequestRecorder,
    response: @escaping (PrefetchRangeRequest) throws -> Data
) {
    PrefetchExchangeRateURLProtocol.handler = { request in
        let rangeRequest = try parseRangeRequest(request)
        recorder.record(rangeRequest)
        return try makePrefetchResponse(for: request, data: response(rangeRequest))
    }
}

private func parseRangeRequest(_ request: URLRequest) throws -> PrefetchRangeRequest {
    guard
        let url = request.url,
        url.path == "/api/v1/exchange-rates/range",
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        let queryItems = components.queryItems,
        let from = queryItems.first(where: { $0.name == "from" })?.value,
        let to = queryItems.first(where: { $0.name == "to" })?.value
    else {
        throw PrefetchExchangeRateTestError.invalidRequest
    }
    return PrefetchRangeRequest(from: from, to: to)
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

private func emptyRangeResponse() -> Data {
    rangeResponse(rows: [])
}

private func rangeResponse(rows: [String]) -> Data {
    Data(
        """
        {
            "success": true,
            "data": [\(rows.joined(separator: ","))]
        }
        """.utf8
    )
}

private func rateRow(
    _ currency: CurrencyCode,
    baseDate: String,
    tts: String = "1.25"
) -> String {
    """
    {
        "currencyCode": "\(currency.rawValue)",
        "currencyName": "\(currency.rawValue)",
        "tts": \(tts),
        "baseDate": "\(baseDate)",
        "stale": false
    }
    """
}

private func completeForeignCurrencyRows(baseDate: String) -> [String] {
    CurrencyCode.allCases
        .filter { $0 != .krw }
        .map { rateRow($0, baseDate: baseDate) }
}

private func prefetchDate(_ localDate: String) throws -> Date {
    try #require(ServerDateFormatter.localDate.date(from: localDate))
}

private func prefetchDateText(_ date: Date) -> String {
    ServerDateFormatter.localDate.string(from: date)
}

private func prefetchAddingDays(_ days: Int, to date: Date) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
    return try #require(calendar.date(byAdding: .day, value: days, to: date))
}

private func syntheticPrefetchSeedData(latestBaseDate: String) throws -> SeedData {
    try SeedData(
        exchangeRates: [
            SeedExchangeRate(
                currencyCode: .usd,
                currencyName: "미국 달러",
                tts: #require(Decimal(string: "1400.00")),
                baseDate: latestBaseDate,
                stale: false
            )
        ],
        expenseCategories: [],
        incomeCategories: [],
        assets: []
    )
}

// swiftlint:enable file_length
