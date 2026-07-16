//
//  RateProvider.swift
//  woni_app
//

import Foundation

protocol RateProviding {
    func rate(for currency: SelectableCurrency, on localDate: String) async -> Decimal?
}

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
        guard let code = currency.exchangeCode else {
            return Decimal(1)
        }

        return ratesByCurrency[code]?.first { rate in
            rate.baseDate <= localDate
        }?.tts
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

    func rate(for currency: SelectableCurrency, on localDate: String) async -> Decimal? {
        rateProvider.rate(for: currency, on: localDate)
    }
}
