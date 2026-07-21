//
//  AddExpenseViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct AddExpenseViewModelTests {
    @Test("load는 시드 카탈로그를 로드하고 sortOrder 첫 항목을 기본 선택한다")
    func loadReadsSeedCatalogAndSelectsFirstItems() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        await viewModel.load()

        #expect(viewModel.catalogError == nil)
        #expect(viewModel.isLoadingCatalog == false)
        #expect(viewModel.expenseCategories.map(\.id) == [10, 11])
        #expect(viewModel.incomeCategories.map(\.id) == [30, 31])
        #expect(viewModel.assets.map(\.id) == [20, 21])
        #expect(viewModel.selectedCategoryId == 10)
        #expect(viewModel.selectedAssetId == 20)
    }

    @Test("탭 전환은 캐시된 시드 카테고리에서 기본 선택을 바꾼다")
    func tabSwitchSelectsSeedCategoryForVisibleTab() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        await viewModel.load()
        #expect(viewModel.selectedTab == .expense)
        viewModel.selectedTab = .income

        #expect(viewModel.visibleCategories.map(\.id) == [30, 31])
        #expect(viewModel.selectedCategoryId == 30)
        #expect(viewModel.selectedAssetId == 20)

        viewModel.selectedTab = .expense

        #expect(viewModel.visibleCategories.map(\.id) == [10, 11])
        #expect(viewModel.selectedCategoryId == 10)
        #expect(viewModel.selectedAssetId == 20)
    }

    @Test("updateDate는 날짜를 세팅하고 표시 환율을 재조회한다")
    func updateDateSetsDateAndRefreshesRate() async throws {
        let seedData = try SeedData(
            exchangeRates: addExpenseExchangeRates() + [
                SeedExchangeRate(
                    currencyCode: .usd,
                    currencyName: "미국 달러",
                    tts: decimal("1500.00"),
                    baseDate: "2026-07-04",
                    stale: false
                )
            ],
            expenseCategories: addExpenseExpenseCategories(),
            incomeCategories: addExpenseIncomeCategories(),
            assets: addExpenseAssets()
        )
        let harness = try makeAddExpenseHarness(seedData: seedData)
        let viewModel = harness.viewModel

        viewModel.selectedCurrency = .usd
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)
        await viewModel.fetchRate()

        let initialRate = try decimal("1400.00")
        #expect(viewModel.currentRate == initialRate)

        let newDate = try makeSeoulDate(year: 2026, month: 7, day: 4)
        let refreshTask = viewModel.updateDate(newDate)
        await refreshTask.value

        let refreshedRate = try decimal("1500.00")
        #expect(viewModel.date == newDate)
        #expect(viewModel.currentRate == refreshedRate)
    }

    @Test("서버 quote 성공은 tts 프리뷰와 stale 상태를 보존한다")
    func serverQuoteSuccessDrivesTtsPreviewAndStaleState() async throws {
        let tts = try decimal("1411.23")
        let quote = try RateQuote(
            tts: tts,
            baseDate: makeSeoulDate(year: 2026, month: 7, day: 15),
            isStale: true,
            source: .server
        )
        let viewModel = try makeAddExpenseHarness(rateProvider: StubRateProvider(quote: quote)).viewModel

        viewModel.amount = 10
        viewModel.selectedCurrency = .usd
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 16)
        await viewModel.fetchRate()

        #expect(viewModel.currentQuote == quote)
        #expect(viewModel.currentRate == tts)
        #expect(viewModel.convertedBaseAmount == decimalLiteral("14112.30"))
        #expect(viewModel.krwToForeignRate != nil)
        #expect(viewModel.isCurrentRateStale)
    }

    @Test("서버 폴백 quote는 시드 tts로 프리뷰를 표시한다")
    func fallbackSeedQuoteDrivesTtsPreview() async throws {
        let tts = try decimal("1400.00")
        let quote = try RateQuote(
            tts: tts,
            baseDate: makeSeoulDate(year: 2026, month: 7, day: 2),
            isStale: false,
            source: .seed
        )
        let viewModel = try makeAddExpenseHarness(rateProvider: StubRateProvider(quote: quote)).viewModel

        viewModel.amount = 10
        viewModel.selectedCurrency = .usd
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 3)
        await viewModel.fetchRate()

        #expect(viewModel.currentQuote == quote)
        #expect(viewModel.currentRate == tts)
        #expect(viewModel.convertedBaseAmount == decimalLiteral("14000.00"))
        #expect(viewModel.isCurrentRateStale == false)
    }

    @Test("quote가 없으면 환율 프리뷰 상태를 비운다")
    func nilQuoteClearsRatePreviewState() async throws {
        let viewModel = try makeAddExpenseHarness(rateProvider: StubRateProvider(quote: nil)).viewModel

        viewModel.amount = 10
        viewModel.selectedCurrency = .usd
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 3)
        await viewModel.fetchRate()

        #expect(viewModel.currentQuote == nil)
        #expect(viewModel.currentRate == nil)
        #expect(viewModel.convertedBaseAmount == nil)
        #expect(viewModel.krwToForeignRate == nil)
        #expect(viewModel.isCurrentRateStale == false)
    }

    @Test("AddEntry 통화 피커는 MVP 5종만 노출한다")
    func entryPickerOptionsExcludesCny() {
        #expect(SelectableCurrency.entryPickerOptions == [.krw, .usd, .eur, .jpy, .gbp])
        #expect(SelectableCurrency.krw.displayName(.en) == "South Korea")
        #expect(SelectableCurrency.usd.displayName(.en) == "United States")
        #expect(SelectableCurrency.eur.displayName(.en) == "Europe")
        #expect(SelectableCurrency.jpy.displayName(.en) == "Japan")
        #expect(SelectableCurrency.gbp.displayName(.en) == "United Kingdom")
    }

    @Test("save 성공은 로컬 repository에 pending KRW 거래를 저장하고 폼을 기본값으로 리셋한다")
    func saveSuccessInsertsPendingLocalTransactionAndResetsForm() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        await viewModel.load()
        viewModel.amount = try decimal("1234.56")
        viewModel.selectedCategoryId = 11
        viewModel.selectedAssetId = 21
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)
        viewModel.memo = "  라떼  "

        await viewModel.save()

        let stored = try #require(try await transactions(in: harness.repository, year: 2026, month: 7).first)
        let expectedAmount = try decimal("1234.56")

        #expect(try await harness.repository.count() == 1)
        #expect(stored.id != nil)
        #expect(stored.clientEntryID.uuidString.count == 36)
        #expect(stored.amount == expectedAmount)
        #expect(stored.currencyCode == "KRW")
        #expect(stored.categoryID == 11)
        #expect(stored.assetID == 21)
        #expect(stored.transactionType == .expense)
        #expect(stored.transactionDate == "2026-07-02")
        #expect(stored.memo == "라떼")
        #expect(stored.pending)
        #expect(stored.appliedRate == nil)
        #expect(stored.rateBaseDate == nil)
        #expect(stored.krwAmount == expectedAmount)

        #expect(viewModel.isSaving == false)
        #expect(viewModel.saveSucceeded == true)
        #expect(viewModel.saveError == nil)
        #expect(viewModel.amount == 0)
        #expect(viewModel.memo.isEmpty)
        #expect(viewModel.selectedCurrency == .krw)
        #expect(viewModel.selectedCategoryId == 10)
        #expect(viewModel.selectedAssetId == 20)
    }

    @Test("수입 탭 save는 선택된 income categoryId와 INCOME 타입을 저장한다")
    func saveFromIncomeTabStoresSelectedIncomeCategoryAndType() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        await viewModel.load()
        viewModel.selectedTab = .income
        viewModel.amount = 9000
        viewModel.selectedCategoryId = 31
        viewModel.selectedAssetId = 20
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)

        await viewModel.save()

        let stored = try #require(try await transactions(in: harness.repository, year: 2026, month: 7).first)

        #expect(stored.categoryID == 31)
        #expect(stored.assetID == 20)
        #expect(stored.currencyCode == "KRW")
        #expect(stored.transactionType == .income)
        #expect(stored.memo == nil)
    }

    @Test("canSave는 카테고리·자산 선택과 금액 범위·scale을 검증한다")
    func canSaveValidatesRequiredSelectionsAmountRangeAndScale() throws {
        let viewModel = try makeAddExpenseHarness().viewModel

        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20
        #expect(viewModel.canSave == false)

        viewModel.amount = try decimal("0.01")
        #expect(viewModel.canSave == true)

        viewModel.amount = try decimal("99999999.00")
        #expect(viewModel.canSave == true)

        viewModel.amount = try decimal("99999999.01")
        #expect(viewModel.canSave == false)

        viewModel.amount = try decimal("1.001")
        #expect(viewModel.canSave == false)

        viewModel.amount = 1
        viewModel.selectedCategoryId = nil
        #expect(viewModel.canSave == false)

        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = nil
        #expect(viewModel.canSave == false)
    }

    @Test("소수 3자리 amount는 저장하지 않고 인라인 에러를 노출한다")
    func saveRejectsAmountWithMoreThanTwoFractionDigits() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        viewModel.amount = try decimal("1.001")
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20

        await viewModel.save()

        #expect(try await harness.repository.count() == 0)
        #expect(viewModel.saveSucceeded == false)
        #expect(viewModel.saveError == .invalidAmount)
    }

    @Test("256자 memo는 저장하지 않고 인라인 에러를 노출한다")
    func saveRejectsMemoLongerThan255Characters() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        viewModel.amount = 100
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20
        viewModel.memo = String(repeating: "a", count: 256)

        await viewModel.save()

        #expect(try await harness.repository.count() == 0)
        #expect(viewModel.saveSucceeded == false)
        #expect(viewModel.saveError == .memoTooLong)
    }

    @Test("카테고리 또는 자산 미선택은 저장하지 않고 case 에러를 노출한다")
    func saveRejectsMissingCategoryOrAssetSelection() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        viewModel.amount = 100
        viewModel.selectedCategoryId = nil
        viewModel.selectedAssetId = 20

        await viewModel.save()

        #expect(try await harness.repository.count() == 0)
        #expect(viewModel.saveSucceeded == false)
        #expect(viewModel.saveError == .missingSelection)
    }

    @Test("외화 미래일은 저장하지 않고 KRW 미래일은 허용한다")
    func saveRejectsForeignFutureDateButAllowsKrwFutureDate() async throws {
        let foreignHarness = try makeAddExpenseHarness()
        let foreignViewModel = foreignHarness.viewModel

        foreignViewModel.amount = 100
        foreignViewModel.selectedCurrency = .usd
        foreignViewModel.selectedCategoryId = 10
        foreignViewModel.selectedAssetId = 20
        foreignViewModel.date = try makeRelativeSeoulDate(daysFromToday: 1)

        await foreignViewModel.save()

        #expect(try await foreignHarness.repository.count() == 0)
        #expect(foreignViewModel.saveSucceeded == false)
        #expect(foreignViewModel.saveError == .invalidFutureDate)

        let krwHarness = try makeAddExpenseHarness()
        let krwViewModel = krwHarness.viewModel

        krwViewModel.amount = 100
        krwViewModel.selectedCurrency = .krw
        krwViewModel.selectedCategoryId = 10
        krwViewModel.selectedAssetId = 20
        krwViewModel.date = try makeRelativeSeoulDate(daysFromToday: 1)

        await krwViewModel.save()

        #expect(try await krwHarness.repository.count() == 1)
        #expect(krwViewModel.saveSucceeded == true)
        #expect(krwViewModel.saveError == nil)
    }

    @Test("잠정 원화 환산은 JPY unit=100, USD unit=1, KRW rate=1을 적용한다")
    func provisionalConversionUsesCurrencyUnitAndTts() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)

        viewModel.amount = 10000
        viewModel.selectedCurrency = .jpy
        await viewModel.fetchRate()

        let expectedJPYRate = try decimal("950.00")
        let expectedJPYAmount = try decimal("95000.00")
        #expect(viewModel.currentRate == expectedJPYRate)
        #expect(viewModel.convertedBaseAmount == expectedJPYAmount)

        viewModel.amount = 10
        viewModel.selectedCurrency = .usd
        await viewModel.fetchRate()

        let expectedUSDRate = try decimal("1400.00")
        let expectedUSDAmount = try decimal("14000.00")
        #expect(viewModel.currentRate == expectedUSDRate)
        #expect(viewModel.convertedBaseAmount == expectedUSDAmount)

        viewModel.amount = try decimal("1234.56")
        viewModel.selectedCurrency = .krw
        await viewModel.fetchRate()

        let expectedKRWAmount = try decimal("1234.56")
        #expect(viewModel.currentRate == Decimal(1))
        #expect(viewModel.convertedBaseAmount == expectedKRWAmount)
    }

    @Test("동시 save 호출은 로컬 repository에 1건만 저장한다")
    func concurrentSaveCallsInsertSingleLocalTransaction() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        viewModel.amount = 5000
        viewModel.selectedCurrency = .krw
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20

        async let first: Void = viewModel.save()
        async let second: Void = viewModel.save()
        _ = await(first, second)

        #expect(try await harness.repository.count() == 1)
        #expect(viewModel.saveSucceeded == true)
        #expect(viewModel.isSaving == false)
    }
}

@MainActor
private final class FakeLocalWriteSyncTrigger: LocalWriteSyncTriggering {
    private(set) var scheduleCount = 0

    func performLocalWrite(_ operation: @escaping () async throws -> Void) async throws {
        try await operation()
        scheduleCount += 1
    }
}

extension AddExpenseViewModelTests {
    @Test("save 성공은 로컬 쓰기 뒤 동기화 디바운스 트리거를 1회 요청한다")
    func saveSuccessSchedulesOneSyncTrigger() async throws {
        let trigger = FakeLocalWriteSyncTrigger()
        let harness = try makeAddExpenseHarness(
            rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            syncTrigger: trigger
        )
        let viewModel = harness.viewModel
        await viewModel.load()
        viewModel.amount = 1000

        await viewModel.save()

        #expect(viewModel.saveSucceeded)
        #expect(trigger.scheduleCount == 1)
    }

    @Test("외화 save는 fetched quote 기반 환율 필드를 저장한다")
    func foreignSavePersistsFetchedQuoteRateFields() async throws {
        let tts = try decimal("1411.23")
        let quote = try RateQuote(
            tts: tts,
            baseDate: makeSeoulDate(year: 2026, month: 7, day: 15),
            isStale: true,
            source: .server
        )
        let harness = try makeAddExpenseHarness(rateProvider: StubRateProvider(quote: quote))
        let viewModel = harness.viewModel

        await viewModel.load()
        viewModel.amount = 10
        viewModel.selectedCurrency = .usd
        viewModel.selectedCategoryId = 11
        viewModel.selectedAssetId = 21
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 16)
        await viewModel.fetchRate()

        await viewModel.save()

        let stored = try #require(try await transactions(in: harness.repository, year: 2026, month: 7).first)

        #expect(stored.currencyCode == "USD")
        #expect(stored.pending)
        #expect(stored.appliedRate == tts)
        #expect(stored.rateBaseDate == "2026-07-15")
        #expect(stored.krwAmount == decimalLiteral("14112.30"))
    }

    @Test("quote 없는 외화 save는 환율 필드를 nil로 저장한다")
    func foreignSaveWithoutQuotePersistsNilRateFields() async throws {
        let harness = try makeAddExpenseHarness(rateProvider: StubRateProvider(quote: nil))
        let viewModel = harness.viewModel

        await viewModel.load()
        viewModel.amount = 10
        viewModel.selectedCurrency = .usd
        viewModel.selectedCategoryId = 11
        viewModel.selectedAssetId = 21
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 16)
        await viewModel.fetchRate()

        await viewModel.save()

        let stored = try #require(try await transactions(in: harness.repository, year: 2026, month: 7).first)

        #expect(stored.currencyCode == "USD")
        #expect(stored.pending)
        #expect(stored.appliedRate == nil)
        #expect(stored.rateBaseDate == nil)
        #expect(stored.krwAmount == nil)
    }

    @Test("updateDate는 새 quote 로드 전 이전 환율 프리뷰를 즉시 비운다")
    func updateDateClearsRatePreviewBeforeRefetch() async throws {
        let tts = try decimal("1400.00")
        let quote = try RateQuote(
            tts: tts,
            baseDate: makeSeoulDate(year: 2026, month: 7, day: 2),
            isStale: false,
            source: .seed
        )
        let viewModel = try makeAddExpenseHarness(rateProvider: StubRateProvider(quote: quote)).viewModel

        viewModel.selectedCurrency = .usd
        await viewModel.fetchRate()
        #expect(viewModel.currentRate == tts)
        #expect(viewModel.currentQuote == quote)

        // 재fetch 전(동기 시점)에 이전 context의 프리뷰가 즉시 비워진다.
        let refreshTask = try viewModel.updateDate(makeSeoulDate(year: 2026, month: 7, day: 10))
        #expect(viewModel.currentRate == nil)
        #expect(viewModel.currentQuote == nil)

        // 새 quote 로드 후 다시 채워진다.
        await refreshTask.value
        #expect(viewModel.currentRate == tts)
        #expect(viewModel.currentQuote == quote)
    }
}
