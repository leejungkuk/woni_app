//
//  ServerRateProvider.swift
//  woni_app
//

import Foundation
import OSLog

/// 서버 환율을 우선 조회하고, 조회 실패 시 캐시와 번들 시드 순서로 폴백한다.
struct ServerRateProvider: RateProviding {
    nonisolated static let logger = Logger(subsystem: "woni_app", category: "Exchange")

    private let service: ExchangeRateService
    private let seedRateProvider: RateProvider
    private let cache: (any ExchangeRateCaching)?
    private let onFallback: @Sendable (_ currency: SelectableCurrency, _ localDate: String) -> Void

    init(
        service: ExchangeRateService = ExchangeRateService(),
        seedRateProvider: RateProvider,
        cache: (any ExchangeRateCaching)? = nil,
        onFallback: @escaping @Sendable (_ currency: SelectableCurrency, _ localDate: String)
            -> Void = Self.logFallback
    ) {
        self.service = service
        self.seedRateProvider = seedRateProvider
        self.cache = cache
        self.onFallback = onFallback
    }

    init(
        service: ExchangeRateService = ExchangeRateService(),
        seedData: SeedData,
        cache: (any ExchangeRateCaching)? = nil,
        onFallback: @escaping @Sendable (_ currency: SelectableCurrency, _ localDate: String)
            -> Void = Self.logFallback
    ) {
        self.init(
            service: service,
            seedRateProvider: RateProvider(seedData: seedData),
            cache: cache,
            onFallback: onFallback
        )
    }

    func quote(for currency: SelectableCurrency, on date: Date) async -> RateQuote? {
        guard let exchangeCode = currency.exchangeCode else {
            return RateQuote(
                tts: Decimal(1),
                baseDate: nil,
                isStale: false,
                source: .server
            )
        }

        let localDate = ServerDateFormatter.localDate.string(from: date)

        do {
            let rate = try await service.fetchRate(for: exchangeCode, on: date)
            let quote = RateQuote(
                tts: rate.tts,
                baseDate: rate.baseDate,
                isStale: rate.isStale,
                source: .server
            )
            await cacheServerRate(rate, exchangeCode: exchangeCode)
            return quote
        } catch {
            return await fallbackQuote(
                for: currency,
                exchangeCode: exchangeCode,
                localDate: localDate
            )
        }
    }

    private func cacheServerRate(_ rate: ExchangeRate, exchangeCode: CurrencyCode) async {
        guard let cache, let baseDate = rate.baseDate else {
            return
        }

        let cachedRate = CachedExchangeRate(
            currencyCode: exchangeCode.rawValue,
            baseDate: ServerDateFormatter.localDate.string(from: baseDate),
            tts: rate.tts
        )
        do {
            try await cache.upsert([cachedRate])
        } catch {
            Self.logCacheWriteFailure(exchangeCode: exchangeCode, error: error)
        }
    }

    private func fallbackQuote(
        for currency: SelectableCurrency,
        exchangeCode: CurrencyCode,
        localDate: String
    ) async -> RateQuote? {
        if let cache {
            do {
                if let cachedRate = try await cache.latestRate(
                    for: exchangeCode.rawValue,
                    onOrBefore: localDate
                ) {
                    Self.logCacheHit(exchangeCode: exchangeCode, localDate: localDate)
                    return RateQuote(
                        tts: cachedRate.tts,
                        baseDate: ServerDateFormatter.localDate.date(from: cachedRate.baseDate),
                        isStale: cachedRate.baseDate != localDate,
                        source: .cache
                    )
                }
            } catch {
                Self.logCacheReadFailure(
                    exchangeCode: exchangeCode,
                    error: error
                )
            }
        }

        onFallback(currency, localDate)
        return seedRateProvider.quote(for: currency, on: localDate)
    }

    nonisolated static func logFallback(currency: SelectableCurrency, localDate: String) {
        logger.warning(
            "Rate seed fallback currency=\(currency.rawValue, privacy: .public) date=\(localDate, privacy: .public)"
        )
    }

    nonisolated static func logCacheHit(
        exchangeCode: CurrencyCode,
        localDate: String
    ) {
        logger.info(
            "Rate cache hit currency=\(exchangeCode.rawValue, privacy: .public) date=\(localDate, privacy: .public)"
        )
    }

    nonisolated static func logCacheWriteFailure(
        exchangeCode: CurrencyCode,
        error: any Error
    ) {
        let message = String(describing: error)
        logger.error(
            "Rate cache write failed currency=\(exchangeCode.rawValue, privacy: .public) error=\(message)"
        )
    }

    nonisolated static func logCacheReadFailure(
        exchangeCode: CurrencyCode,
        error: any Error
    ) {
        let message = String(describing: error)
        logger.error(
            "Rate cache read failed currency=\(exchangeCode.rawValue, privacy: .public) error=\(message)"
        )
    }
}
