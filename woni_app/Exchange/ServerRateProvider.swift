//
//  ServerRateProvider.swift
//  woni_app
//

import Foundation
import OSLog

/// 서버 환율을 우선 조회하고, 조회 실패 시 번들 시드 환율로 폴백한다.
struct ServerRateProvider: RateProviding {
    nonisolated static let logger = Logger(subsystem: "woni_app", category: "Exchange")

    private let service: ExchangeRateService
    private let seedRateProvider: RateProvider
    private let onFallback: @Sendable (_ currency: SelectableCurrency, _ localDate: String) -> Void

    init(
        service: ExchangeRateService = ExchangeRateService(),
        seedRateProvider: RateProvider,
        onFallback: @escaping @Sendable (_ currency: SelectableCurrency, _ localDate: String)
            -> Void = Self.logFallback
    ) {
        self.service = service
        self.seedRateProvider = seedRateProvider
        self.onFallback = onFallback
    }

    init(
        service: ExchangeRateService = ExchangeRateService(),
        seedData: SeedData,
        onFallback: @escaping @Sendable (_ currency: SelectableCurrency, _ localDate: String)
            -> Void = Self.logFallback
    ) {
        self.init(
            service: service,
            seedRateProvider: RateProvider(seedData: seedData),
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
            return RateQuote(
                tts: rate.tts,
                baseDate: rate.baseDate,
                isStale: rate.isStale,
                source: .server
            )
        } catch {
            onFallback(currency, localDate)
            return seedRateProvider.quote(for: currency, on: localDate)
        }
    }

    nonisolated static func logFallback(currency: SelectableCurrency, localDate: String) {
        logger.warning(
            "Rate seed fallback currency=\(currency.rawValue, privacy: .public) date=\(localDate, privacy: .public)"
        )
    }
}
