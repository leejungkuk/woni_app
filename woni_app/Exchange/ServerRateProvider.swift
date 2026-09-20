//
//  ServerRateProvider.swift
//  woni_app
//

import Foundation
import OSLog

/// 서버 환율을 우선 조회하고, 조회 실패 시 캐시와 번들 시드 중 `baseDate`가 더 최신인 쪽으로 폴백한다(같으면 캐시).
struct ServerRateProvider: RateProviding {
    nonisolated static let logger = Logger(subsystem: "woni_app", category: "Exchange")

    /// 서버 `ExchangeErrorCode.INVALID_DATE`. 에러 봉투(`ErrorResponse`)는 성공 봉투와 레코드가 달라
    /// `data` 키가 **아예 없다** — `APIEnvelope.data` 가 Optional 이라 그대로 디코딩되고 이 코드가 살아온다.
    static let rejectedDateCode = "INVALID_DATE"

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
            // 서버가 계약으로 **거부**한 것은 전송 실패가 아니다. "이 날짜에는 환율이 없다"는 판정이므로
            // 폴백하면 서버가 거부한 값을 시드로 덮어 화면에 그럴듯하게 내보내게 된다. 기기 시계가
            // 서버보다 앞선 기기에서만 그렇게 되므로 같은 입력이 기기마다 다른 금액이 된다.
            if isRejectedByContract(error) {
                Self.logRejectedDate(exchangeCode: exchangeCode, localDate: localDate)
                return nil
            }
            return await fallbackQuote(
                for: currency,
                exchangeCode: exchangeCode,
                localDate: localDate
            )
        }
    }

    /// 백엔드 `ExchangeRateController.getRate` 가 오늘(서버 KST)+365 초과를 `INVALID_DATE` 로 막는다.
    /// `openapi.json` 에는 없다 — springdoc 이 애노테이션 없는 예외를 싣지 않아, 계약만 읽어선 모른다.
    private func isRejectedByContract(_ error: any Error) -> Bool {
        guard case let APIError.server(code, _) = error else {
            return false
        }
        return code == Self.rejectedDateCode
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
        let seedQuote = seedRateProvider.quote(for: currency, on: localDate)
        if let cache {
            do {
                if let cachedRate = try await cache.latestRate(
                    for: exchangeCode.rawValue,
                    onOrBefore: localDate
                ), !cachedRate.isOlder(than: seedQuote?.baseDate) {
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
        return seedQuote
    }

    nonisolated static func logRejectedDate(exchangeCode: CurrencyCode, localDate: String) {
        logger.warning(
            "Rate rejected currency=\(exchangeCode.rawValue, privacy: .public) date=\(localDate, privacy: .public)"
        )
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
