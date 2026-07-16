//
//  RateProvider.swift
//  woni_app
//

import Foundation

struct RateProvider {
    private let ratesByCurrency: [CurrencyCode: [SeedExchangeRate]]

    init(seedData: SeedData) {
        ratesByCurrency = Dictionary(grouping: seedData.exchangeRates, by: \.currencyCode)
            .mapValues { rates in
                rates.sorted { $0.baseDate > $1.baseDate }
            }
    }

    init(loader: SeedLoader = SeedLoader()) throws {
        try self.init(seedData: loader.load())
    }

    func rate(for currency: SelectableCurrency, on date: Date) -> Decimal? {
        rate(for: currency, on: ServerDateFormatter.localDate.string(from: date))
    }

    /// base 통화(KRW)는 시드 없이 rate=1 불변식으로 처리(환산 없음),
    /// 비-base는 요청일 이하 최신 baseDate의 `tts`를 반환한다(시드 없으면 nil).
    func rate(for currency: SelectableCurrency, on localDate: String) -> Decimal? {
        quote(for: currency, on: localDate)?.tts
    }

    func quote(for currency: SelectableCurrency, on date: Date) -> RateQuote? {
        quote(for: currency, on: ServerDateFormatter.localDate.string(from: date))
    }

    func quote(for currency: SelectableCurrency, on localDate: String) -> RateQuote? {
        guard let code = currency.exchangeCode else {
            return RateQuote(
                tts: Decimal(1),
                baseDate: nil,
                isStale: false,
                source: .seed
            )
        }

        guard let seedRate = ratesByCurrency[code]?.first(where: { rate in
            rate.baseDate <= localDate
        }) else {
            return nil
        }

        return RateQuote(
            tts: seedRate.tts,
            baseDate: ServerDateFormatter.localDate.date(from: seedRate.baseDate),
            isStale: seedRate.stale,
            source: .seed
        )
    }
}

struct SeedRateProviderAdapter: RateProviding {
    private let rateProvider: RateProvider

    init(rateProvider: RateProvider) {
        self.rateProvider = rateProvider
    }

    init(seedData: SeedData) {
        rateProvider = RateProvider(seedData: seedData)
    }

    func quote(for currency: SelectableCurrency, on date: Date) async -> RateQuote? {
        rateProvider.quote(for: currency, on: date)
    }
}
