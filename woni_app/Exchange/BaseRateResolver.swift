import Foundation

/// 서버 요청 없이 로컬 캐시와 번들 시드에서 날짜별 base 환율을 해석한다.
struct BaseRateResolver {
    private let cache: any ExchangeRateCaching
    private let seedRateProvider: RateProvider

    init(
        cache: any ExchangeRateCaching,
        seedRateProvider: RateProvider
    ) {
        self.cache = cache
        self.seedRateProvider = seedRateProvider
    }

    func ttsByDate(
        for base: SelectableCurrency,
        dates: Set<String>
    ) async -> [String: Decimal] {
        guard base != .krw, let currencyCode = base.exchangeCode?.rawValue else {
            return [:]
        }

        var resolvedRates: [String: Decimal] = [:]
        for date in dates {
            let cachedRate: CachedExchangeRate?
            do {
                cachedRate = try await cache.latestRate(
                    for: currencyCode,
                    onOrBefore: date
                )
            } catch {
                cachedRate = nil
            }

            let seedQuote = seedRateProvider.quote(for: base, on: date)
            guard let tts = Self.resolvedTTS(cached: cachedRate, seed: seedQuote),
                  NSDecimalNumber(decimal: tts).compare(NSDecimalNumber(value: 0))
                  == .orderedDescending
            else {
                continue
            }
            resolvedRates[date] = tts
        }

        return resolvedRates
    }

    /// 캐시와 시드 중 `baseDate`가 더 최신인 쪽의 tts. 같으면 캐시를 우선한다.
    private static func resolvedTTS(cached: CachedExchangeRate?, seed: RateQuote?) -> Decimal? {
        guard let cached else { return seed?.tts }
        return cached.isOlder(than: seed?.baseDate) ? seed?.tts : cached.tts
    }
}
