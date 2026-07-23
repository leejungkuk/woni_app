//
//  ExchangeRatePrefetcher.swift
//  woni_app
//

import Foundation
import OSLog

// swiftformat:disable redundantSendable
/// 당일 as-of 환율 snapshot을 로컬 캐시에 best-effort로 저장한다.
struct ExchangeRatePrefetcher: Sendable {
    nonisolated static let logger = Logger(subsystem: "woni_app", category: "Exchange")

    private let service: ExchangeRateService
    private let cache: any ExchangeRateCaching
    private let now: @Sendable () -> Date

    init(
        service: ExchangeRateService,
        cache: any ExchangeRateCaching,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.cache = cache
        self.now = now
    }

    /// 당일 snapshot에서 baseDate를 파싱할 수 있는 행만 저장한다.
    /// 네트워크·디코딩·캐시 오류는 다음 포그라운드 진입에서 자연 재시도되도록 전파하지 않는다.
    func prefetchToday() async {
        do {
            let rates = try await service.fetchSnapshot(on: now())
            let cachedRates = rates.compactMap { rate -> CachedExchangeRate? in
                guard let baseDate = rate.baseDate else {
                    return nil
                }
                return CachedExchangeRate(
                    currencyCode: rate.currency.rawValue,
                    baseDate: ServerDateFormatter.localDate.string(from: baseDate),
                    tts: rate.tts
                )
            }
            try await cache.upsert(cachedRates)
        } catch {
            Self.logFailure(error)
        }
    }

    nonisolated static func logFailure(_ error: any Error) {
        let message = String(describing: error)
        logger.error("Rate snapshot prefetch failed error=\(message, privacy: .public)")
    }
}

// swiftformat:enable redundantSendable
