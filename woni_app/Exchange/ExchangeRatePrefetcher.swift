//
//  ExchangeRatePrefetcher.swift
//  woni_app
//

import Foundation
import OSLog

// swiftformat:disable redundantSendable
/// 시드 또는 이전 백필 마커 이후의 환율을 로컬 캐시에 best-effort로 저장한다.
struct ExchangeRatePrefetcher: Sendable {
    nonisolated static let logger = Logger(subsystem: "woni_app", category: "Exchange")

    private let service: ExchangeRateService
    private let cache: any ExchangeRateCaching
    private let coverageStore: RateBackfillCoverageStore
    private let seedCoveredThrough: String?
    private let now: @Sendable () -> Date

    init(
        service: ExchangeRateService,
        cache: any ExchangeRateCaching,
        coverageStore: RateBackfillCoverageStore,
        seedCoveredThrough: String?,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.cache = cache
        self.coverageStore = coverageStore
        self.seedCoveredThrough = seedCoveredThrough
        self.now = now
    }

    /// 미커버 구간을 양끝 포함 최대 400일 청크로 나눠 range API에서 가져온다.
    /// 네트워크·디코딩·캐시 오류는 다음 포그라운드 진입에서 자연 재시도되도록 전파하지 않는다.
    func backfillMissingRates() async {
        guard
            let timeZone = TimeZone(identifier: "Asia/Seoul"),
            let coveredThrough = coverageStore.coveredThrough ?? seedCoveredThrough,
            let coveredDate = ServerDateFormatter.localDate.date(from: coveredThrough),
            let today = normalizedLocalDate(now())
        else {
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard var cursor = calendar.date(byAdding: .day, value: 1, to: coveredDate) else {
            return
        }

        while cursor <= today {
            guard let maximumChunkEnd = calendar.date(byAdding: .day, value: 399, to: cursor) else {
                return
            }
            let chunkEnd = min(maximumChunkEnd, today)

            do {
                let rates = try await service.fetchRange(from: cursor, to: chunkEnd)
                let hasInvalidBaseDate = rates.contains { $0.baseDate == nil }
                let cachedRates = rates.compactMap(Self.makeCachedRate)
                try await cache.upsert(cachedRates)

                if !hasInvalidBaseDate, let marker = Self.markerCandidate(in: rates, today: today) {
                    coverageStore.record(marker)
                }
            } catch {
                Self.logFailure(error)
                break
            }

            guard let nextCursor = calendar.date(byAdding: .day, value: 1, to: chunkEnd) else {
                return
            }
            cursor = nextCursor
        }
    }

    nonisolated static func logFailure(_ error: any Error) {
        let message = String(describing: error)
        logger.error("Rate range backfill failed error=\(message, privacy: .public)")
    }
}

private extension ExchangeRatePrefetcher {
    /// 기기 시각을 Asia/Seoul 기준 날짜의 자정으로 절삭한다.
    /// 절삭하지 않으면 오늘 행이 `D < today`로 분류돼 마커가 전진하고, 수집(11:05 KST) 전
    /// 부분 적재를 오늘로 확정해 그날 환율을 하루 종일 받지 못한다.
    func normalizedLocalDate(_ date: Date) -> Date? {
        let localDate = ServerDateFormatter.localDate.string(from: date)
        return ServerDateFormatter.localDate.date(from: localDate)
    }

    static func makeCachedRate(_ rate: ExchangeRate) -> CachedExchangeRate? {
        guard let baseDate = rate.baseDate else {
            return nil
        }
        return CachedExchangeRate(
            currencyCode: rate.currency.rawValue,
            baseDate: ServerDateFormatter.localDate.string(from: baseDate),
            tts: rate.tts
        )
    }

    static func markerCandidate(in rates: [ExchangeRate], today: Date) -> String? {
        var currenciesByDate: [Date: Set<CurrencyCode>] = [:]
        for rate in rates {
            guard let baseDate = rate.baseDate else {
                continue
            }
            currenciesByDate[baseDate, default: []].insert(rate.currency)
        }

        let expectedCurrencies = Set(CurrencyCode.allCases.filter { $0 != .krw })
        var candidate: Date?
        for baseDate in currenciesByDate.keys.sorted() {
            if baseDate < today {
                candidate = baseDate
                continue
            }
            if baseDate == today {
                guard currenciesByDate[baseDate, default: []].isSuperset(
                    of: expectedCurrencies
                ) else {
                    break
                }
                candidate = baseDate
            }
        }
        return candidate.map(ServerDateFormatter.localDate.string(from:))
    }
}

// swiftformat:enable redundantSendable
