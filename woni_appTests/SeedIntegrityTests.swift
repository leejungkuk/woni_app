//
//  SeedIntegrityTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@MainActor
struct SeedIntegrityTests {
    @Test("번들 시드 4개 JSON은 ApiResponse 봉투로 디코딩된다")
    func decodesAllSeedJSONEnvelopes() throws {
        let seedData = try SeedLoader().load()

        #expect(seedData.exchangeRates.count == 4)
        #expect(seedData.expenseCategories.count == 13)
        #expect(seedData.incomeCategories.count == 8)
        #expect(seedData.assets.count == 6)
    }

    @Test("환율 시드는 tts 계약 필드와 KRW/CNY 불변식을 만족한다")
    func exchangeRateSeedMatchesSnapshotContract() throws {
        let seedData = try SeedLoader().load()
        let provider = RateProvider(seedData: seedData)
        let snapshotDate = "2026-07-02"

        let seedCurrencyCodes = Set(seedData.exchangeRates.map(\.currencyCode))
        let expectedCurrencyCodes: Set<CurrencyCode> = [.usd, .eur, .jpy, .gbp]
        #expect(seedCurrencyCodes == expectedCurrencyCodes)
        // KRW는 base 통화라 SelectableCurrency.exchangeCode == nil로 처리되어 시드 환율에 포함되지 않는다.
        #expect(!seedData.exchangeRates.contains { $0.currencyCode == .cny })

        for rate in seedData.exchangeRates {
            #expect(!rate.baseDate.isEmpty)
            #expect(rate.baseDate == snapshotDate)
            #expect(rate.tts > 0)
        }

        #expect(provider.rate(for: .krw, on: snapshotDate) == Decimal(1))
        #expect(provider.rate(for: .cny, on: snapshotDate) == nil)
    }

    @Test("RateProvider는 요청일 이하 최신 baseDate의 tts를 반환한다")
    func rateProviderReturnsLatestRateOnOrBeforeRequestedDate() throws {
        let seedData = try SeedLoader().load()
        let provider = RateProvider(seedData: seedData)

        #expect(provider.rate(for: .usd, on: "2026-07-02") == decimal("1569.94"))
        #expect(provider.rate(for: .usd, on: "2026-07-03") == decimal("1569.94"))
        #expect(provider.rate(for: .usd, on: "2026-07-01") == nil)
        #expect(provider.rate(for: .jpy, on: "2026-07-02") == decimal("965.88"))
    }

    @Test("환율 시드 4통화는 계약 tts 값을 문자열 기반 Decimal로 정확히 보존한다")
    func exchangeRateSeedPreservesExactTts() throws {
        let seedData = try SeedLoader().load()
        // uniqueKeysWithValues는 통화 중복 시 trap → 통화 유일성도 함께 보증한다.
        let ttsByCurrency = Dictionary(
            uniqueKeysWithValues: seedData.exchangeRates.map { ($0.currencyCode, $0.tts) }
        )

        #expect(ttsByCurrency.count == 4)
        #expect(ttsByCurrency[.usd] == decimal("1569.94"))
        #expect(ttsByCurrency[.eur] == decimal("1786.43"))
        #expect(ttsByCurrency[.jpy] == decimal("965.88"))
        #expect(ttsByCurrency[.gbp] == decimal("2084.81"))
    }

    @Test("JPY wire 값은 관측된 enum 이름 그대로 매핑된다")
    func jpyWireValueMapsToCurrencyCode() throws {
        let seedData = try SeedLoader().load()
        let jpy = try #require(seedData.exchangeRates.first { $0.currencyCode == .jpy })

        #expect(jpy.currencyCode.rawValue == "JPY")
        #expect(jpy.tts == decimal("965.88"))
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
