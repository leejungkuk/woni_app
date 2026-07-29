//
//  SeedIntegrityTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@MainActor
struct SeedIntegrityTests {
    private static let earliestBaseDateText = "2024-07-29"
    private static let latestBaseDateText = "2026-07-28"
    private static let representativeBaseDateText = "2026-07-27"
    /// 2024-07-29~2026-07-28 영업일 수. 날짜 수를 고정하지 않으면 특정 기준일의 12행이 통째로
    /// 빠져도 그리드 관계식(행수 == 날짜수 × 통화수)이 그대로 성립해 거짓 통과한다.
    private static let expectedBaseDateCount = 486

    @Test("번들 시드 4개 JSON은 ApiResponse 봉투로 디코딩된다")
    func decodesAllSeedJSONEnvelopes() throws {
        let seedData = try SeedLoader().load()

        #expect(!seedData.exchangeRates.isEmpty)
        #expect(seedData.expenseCategories.count == 13)
        #expect(seedData.incomeCategories.count == 8)
        #expect(seedData.assets.count == 6)
    }

    @Test("환율 시드는 비-KRW 12종의 중복 없는 연속 날짜 그리드를 만족한다")
    func exchangeRateSeedMatchesSnapshotContract() throws {
        let seedData = try SeedLoader().load()
        let provider = RateProvider(seedData: seedData)
        let dateFormatter = ServerDateFormatter.localDate

        let seedCurrencyCodes = Set(seedData.exchangeRates.map(\.currencyCode))
        let expectedCurrencyCodes: Set<CurrencyCode> = [
            .usd, .eur, .jpy, .cny, .gbp, .thb,
            .hkd, .sgd, .idr, .myr, .aud, .nzd
        ]
        #expect(seedCurrencyCodes == expectedCurrencyCodes)
        let distinctBaseDateTexts = Set(seedData.exchangeRates.map(\.baseDate))
        #expect(distinctBaseDateTexts.count == Self.expectedBaseDateCount)
        #expect(
            seedData.exchangeRates.count
                == Self.expectedBaseDateCount * expectedCurrencyCodes.count
        )
        #expect(distinctBaseDateTexts.min() == Self.earliestBaseDateText)
        #expect(distinctBaseDateTexts.max() == Self.latestBaseDateText)
        #expect(seedData.exchangeRates.allSatisfy { !$0.stale })

        for rate in seedData.exchangeRates {
            #expect(rate.tts > 0)
            let baseDate = try #require(dateFormatter.date(from: rate.baseDate))
            #expect(dateFormatter.string(from: baseDate) == rate.baseDate)
        }

        let ratesByCurrency = Dictionary(grouping: seedData.exchangeRates, by: \.currencyCode)
        for rates in ratesByCurrency.values {
            let baseDates = rates.map(\.baseDate)
            #expect(Set(baseDates).count == baseDates.count)
        }

        let sortedBaseDateTexts = distinctBaseDateTexts.sorted()
        // 날짜 문자열을 파싱한 formatter와 같은 타임존으로 날짜 산술을 해야 한다.
        // 시스템 타임존(DST 보유)으로 계산하면 fall-back 구간을 넘는 11일 간격이 10일로 계산돼 통과한다.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(dateFormatter.timeZone)
        for (earlierText, laterText) in zip(sortedBaseDateTexts, sortedBaseDateTexts.dropFirst()) {
            let earlierDate = try #require(dateFormatter.date(from: earlierText))
            let laterDate = try #require(dateFormatter.date(from: laterText))
            let gapInDays = try #require(
                calendar.dateComponents([.day], from: earlierDate, to: laterDate).day
            )
            #expect(gapInDays <= 10)
        }

        // 기준일은 전부 영업일이다. 날짜 수·행수·간격만 보면 영업일 하나를 빼고 주말 하나를
        // 채워 넣는 치환이 그대로 통과하므로, 날짜 집합의 정체성을 요일로 한 겹 더 고정한다.
        for baseDateText in sortedBaseDateTexts {
            let baseDate = try #require(dateFormatter.date(from: baseDateText))
            let weekday = calendar.component(.weekday, from: baseDate)
            #expect(weekday != 1 && weekday != 7, "주말 기준일: \(baseDateText)")
        }

        // KRW는 base 통화라 시드 환율 없이 1로 처리된다.
        #expect(provider.rate(for: .krw, on: Self.latestBaseDateText) == Decimal(1))
    }

    @Test("RateProvider는 주말과 7일 연휴에도 요청일 이하 최신 환율을 반환한다")
    func rateProviderReturnsLatestRateOnOrBeforeRequestedDate() throws {
        let seedData = try SeedLoader().load()
        let provider = RateProvider(seedData: seedData)
        let dateFormatter = ServerDateFormatter.localDate

        let weekendQuote = try #require(provider.quote(for: .usd, on: "2026-07-26"))
        let weekendBaseDate = try #require(weekendQuote.baseDate)
        #expect(dateFormatter.string(from: weekendBaseDate) == "2026-07-24")
        #expect(try weekendQuote.tts == (Self.seedTts(seedData, .usd, on: "2026-07-24")))

        let holidayQuote = try #require(provider.quote(for: .usd, on: "2025-10-09"))
        let holidayBaseDate = try #require(holidayQuote.baseDate)
        #expect(dateFormatter.string(from: holidayBaseDate) == "2025-10-02")
        #expect(try holidayQuote.tts == (Self.seedTts(seedData, .usd, on: "2025-10-02")))

        // 하한 이전은 해결하지 않는다(forward 폴백 미도입). 상한 이후는 최신 환율로 수렴한다.
        #expect(provider.rate(for: .usd, on: "1900-01-01") == nil)
        #expect(
            try provider.rate(for: .usd, on: "2099-12-31")
                == (Self.seedTts(seedData, .usd, on: Self.latestBaseDateText))
        )
    }

    @Test("환율 시드는 대표 tts 값을 문자열 기반 Decimal로 정확히 보존한다")
    func exchangeRateSeedPreservesExactTts() throws {
        let seedData = try SeedLoader().load()
        let usd = try Self.seedTts(seedData, .usd, on: Self.representativeBaseDateText)
        let jpy = try Self.seedTts(seedData, .jpy, on: Self.representativeBaseDateText)

        #expect(usd == decimal("1480.960000"))
        #expect(jpy == decimal("904.760000"))
    }

    @Test("JPY wire 값은 관측된 enum 이름 그대로 매핑된다")
    func jpyWireValueMapsToCurrencyCode() throws {
        let seedData = try SeedLoader().load()
        let jpy = try #require(seedData.exchangeRates.first { $0.currencyCode == .jpy })

        #expect(jpy.currencyCode.rawValue == "JPY")
    }

    @Test("카테고리 시드는 EXPENSE와 INCOME 파일에서 분리 로드되고 sortOrder로 정렬된다")
    func catalogProviderReturnsSeparatedSortedCategories() throws {
        let seedData = try SeedLoader().load()
        let provider = CatalogProvider(seedData: seedData)

        let expenseCategories = provider.categories(for: .expense)
        let incomeCategories = provider.categories(for: .income)

        #expect(!expenseCategories.isEmpty)
        #expect(!incomeCategories.isEmpty)
        #expect(expenseCategories.map(\.id).first == 1)
        #expect(incomeCategories.map(\.id).first == 14)
        #expect(expenseCategories.map(\.sortOrder) == expenseCategories.map(\.sortOrder).sorted())
        #expect(incomeCategories.map(\.sortOrder) == incomeCategories.map(\.sortOrder).sorted())

        // 같은 count의 누락/중복/오분류를 잡기 위한 완결성 검증(id·code 전역 유일 + 탭 간 비중첩).
        let expenseIDs = expenseCategories.map(\.id)
        let incomeIDs = incomeCategories.map(\.id)
        let allCodes = (expenseCategories + incomeCategories).map(\.code)
        let combinedIDs = expenseIDs + incomeIDs
        let uniqueIDCount = Set(combinedIDs).count
        let uniqueCodeCount = Set(allCodes).count
        #expect(uniqueIDCount == expenseIDs.count + incomeIDs.count)
        #expect(uniqueCodeCount == allCodes.count)
        #expect(Set(expenseIDs).isDisjoint(with: Set(incomeIDs)))

        for category in expenseCategories + incomeCategories {
            #expect(category.id > 0)
            #expect(!category.code.isEmpty)
            #expect(!category.displayNameKo.isEmpty)
            #expect(!category.displayNameEn.isEmpty)
        }
    }

    @Test("자산 시드는 비어있지 않고 PK와 표시명을 가진다")
    func catalogProviderReturnsAssetsWithRequiredFields() throws {
        let seedData = try SeedLoader().load()
        let provider = CatalogProvider(seedData: seedData)

        #expect(!provider.assets.isEmpty)
        #expect(provider.assets.map(\.id).first == 1)
        let assetSortOrders = provider.assets.map(\.sortOrder)
        let assetIDs = provider.assets.map(\.id)
        let assetCodes = provider.assets.map(\.code)
        let uniqueAssetIDCount = Set(assetIDs).count
        let uniqueAssetCodeCount = Set(assetCodes).count
        #expect(assetSortOrders == assetSortOrders.sorted())
        #expect(uniqueAssetIDCount == provider.assets.count)
        #expect(uniqueAssetCodeCount == provider.assets.count)

        for asset in provider.assets {
            #expect(asset.id > 0)
            #expect(!asset.code.isEmpty)
            #expect(!asset.displayNameKo.isEmpty)
            #expect(!asset.displayNameEn.isEmpty)
        }
    }

    /// RateProvider의 그룹화·정렬 인덱스와 독립한 시드 원본 조회.
    private static func seedTts(
        _ seedData: SeedData,
        _ currencyCode: CurrencyCode,
        on baseDate: String
    ) throws -> Decimal {
        try #require(seedData.exchangeRates.first {
            $0.currencyCode == currencyCode && $0.baseDate == baseDate
        }).tts
    }

    private func decimal(_ text: String) -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            Issue.record("Invalid decimal literal: \(text)")
            return 0
        }
        return value
    }
}
