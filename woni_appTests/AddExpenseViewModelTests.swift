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
        let _: EntryType = viewModel.selectedTab
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
        viewModel.updateDate(newDate)
        try await Task.sleep(nanoseconds: 50_000_000)

        let refreshedRate = try decimal("1500.00")
        #expect(viewModel.date == newDate)
        #expect(viewModel.currentRate == refreshedRate)
    }

    @Test("AddEntry 통화 피커는 MVP 5종만 노출한다")
    func entryPickerOptionsExcludesCny() {
        #expect(SelectableCurrency.entryPickerOptions == [.krw, .usd, .eur, .jpy, .gbp])
    }

    @Test("save 성공은 로컬 repository에 pending 거래를 저장하고 폼을 기본값으로 리셋한다")
    func saveSuccessInsertsPendingLocalTransactionAndResetsForm() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        await viewModel.load()
        viewModel.amount = try decimal("1234.56")
        viewModel.selectedCurrency = .usd
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
        #expect(stored.currencyCode == "USD")
        #expect(stored.categoryID == 11)
        #expect(stored.assetID == 21)
        #expect(stored.transactionType == .expense)
        #expect(stored.transactionDate == "2026-07-02")
        #expect(stored.memo == "라떼")
        #expect(stored.pending)
        #expect(stored.appliedRate == nil)
        #expect(stored.rateBaseDate == nil)
        #expect(stored.krwAmount == nil)

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
        #expect(viewModel.saveError != nil)
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
        #expect(viewModel.saveError != nil)
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
        #expect(foreignViewModel.saveError != nil)

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
