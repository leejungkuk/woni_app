//
//  SeedIntegrityTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@MainActor
struct SeedIntegrityTests {
    // 시드 재생성 시 세 값을 함께 갱신한다(스냅샷 기준일과 그 전·후일).
    private static let snapshotDateText = "2026-07-27"
    private static let dayBeforeSnapshotText = "2026-07-26"
    private static let dayAfterSnapshotText = "2026-07-28"

    @Test("번들 시드 4개 JSON은 ApiResponse 봉투로 디코딩된다")
    func decodesAllSeedJSONEnvelopes() throws {
        let seedData = try SeedLoader().load()

        #expect(seedData.exchangeRates.count == 12)
        #expect(seedData.expenseCategories.count == 13)
        #expect(seedData.incomeCategories.count == 8)
        #expect(seedData.assets.count == 6)
    }

    @Test("환율 시드는 비-KRW 12종 집합과 날짜·tts 계약을 만족한다")
    func exchangeRateSeedMatchesSnapshotContract() throws {
        let seedData = try SeedLoader().load()
        let provider = RateProvider(seedData: seedData)
        let dateFormatter = ServerDateFormatter.localDate
        let snapshotDate = try #require(dateFormatter.date(from: Self.snapshotDateText))

        let seedCurrencyCodes = Set(seedData.exchangeRates.map(\.currencyCode))
        let expectedCurrencyCodes: Set<CurrencyCode> = [
            .usd, .eur, .jpy, .cny, .gbp, .thb,
            .hkd, .sgd, .idr, .myr, .aud, .nzd
        ]
        #expect(seedCurrencyCodes == expectedCurrencyCodes)
        #expect(seedData.exchangeRates.count == expectedCurrencyCodes.count)

        for rate in seedData.exchangeRates {
            #expect(rate.tts > 0)
            let baseDate = try #require(dateFormatter.date(from: rate.baseDate))
            #expect(dateFormatter.string(from: baseDate) == rate.baseDate)
            #expect(baseDate <= snapshotDate)
        }

        // KRW는 base 통화라 시드 환율 없이 1로 처리된다.
        #expect(provider.rate(for: .krw, on: Self.snapshotDateText) == Decimal(1))
    }

    @Test("RateProvider는 요청일 이하 최신 baseDate의 tts를 반환한다")
    func rateProviderReturnsLatestRateOnOrBeforeRequestedDate() throws {
        let seedData = try SeedLoader().load()
        let provider = RateProvider(seedData: seedData)

        #expect(provider.rate(for: .usd, on: Self.snapshotDateText) == decimal("1480.960000"))
        #expect(provider.rate(for: .usd, on: Self.dayAfterSnapshotText) == decimal("1480.960000"))
        #expect(provider.rate(for: .usd, on: Self.dayBeforeSnapshotText) == nil)
        #expect(provider.rate(for: .jpy, on: Self.snapshotDateText) == decimal("904.760000"))
    }

    @Test("환율 시드는 대표 tts 값을 문자열 기반 Decimal로 정확히 보존한다")
    func exchangeRateSeedPreservesExactTts() throws {
        let seedData = try SeedLoader().load()
        // 중복은 집합·count 계약 테스트에서 명시적으로 보고하고, 여기서는 대표값만 비교한다.
        let ttsByCurrency = Dictionary(
            seedData.exchangeRates.map { ($0.currencyCode, $0.tts) },
            uniquingKeysWith: { current, _ in current }
        )

        #expect(ttsByCurrency.count == 12)
        #expect(ttsByCurrency[.usd] == decimal("1480.960000"))
        #expect(ttsByCurrency[.jpy] == decimal("904.760000"))
    }

    @Test("JPY wire 값은 관측된 enum 이름 그대로 매핑된다")
    func jpyWireValueMapsToCurrencyCode() throws {
        let seedData = try SeedLoader().load()
        let jpy = try #require(seedData.exchangeRates.first { $0.currencyCode == .jpy })

        #expect(jpy.currencyCode.rawValue == "JPY")
        #expect(jpy.tts == decimal("904.760000"))
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

    private func decimal(_ text: String) -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            Issue.record("Invalid decimal literal: \(text)")
            return 0
        }
        return value
    }
}
