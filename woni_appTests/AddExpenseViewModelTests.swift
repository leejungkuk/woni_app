//
//  AddExpenseViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

// swiftlint:disable file_length

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
        #expect(viewModel.isCurrentRateEstimated == false)
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
        #expect(viewModel.isCurrentRateEstimated)
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
        #expect(viewModel.isCurrentRateEstimated == false)
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
    private(set) var invocationCount = 0
    private(set) var scheduleCount = 0

    func performLocalWrite(_ operation: @escaping () async throws -> Void) async throws {
        invocationCount += 1
        try await operation()
        scheduleCount += 1
    }
}

@MainActor
private final class FailingLocalWriteSyncTrigger: LocalWriteSyncTriggering {
    enum Failure: Error {
        case expected
    }

    private(set) var scheduleCount = 0

    func performLocalWrite(_: @escaping () async throws -> Void) async throws {
        scheduleCount += 1
        throw Failure.expected
    }
}

@MainActor
private final class BlockingLocalWriteSyncTrigger: LocalWriteSyncTriggering {
    private(set) var scheduleCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func performLocalWrite(_ operation: @escaping () async throws -> Void) async throws {
        scheduleCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        try await operation()
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

extension AddExpenseViewModelTests {
    @Test("캐시 quote는 추정 환율 상태를 표시하지 않는다")
    func cacheQuoteIsNotEstimated() async throws {
        let quote = try RateQuote(
            tts: decimal("1400.00"),
            baseDate: makeSeoulDate(year: 2026, month: 7, day: 2),
            isStale: false,
            source: .cache
        )
        let viewModel = try makeAddExpenseHarness(rateProvider: StubRateProvider(quote: quote)).viewModel

        viewModel.selectedCurrency = .usd
        await viewModel.fetchRate()

        #expect(viewModel.isCurrentRateEstimated == false)
    }

    @Test("stale 시드 quote는 추정 상태만 표시한다")
    func staleSeedQuoteShowsOnlyEstimatedState() async throws {
        let quote = try RateQuote(
            tts: decimal("1400.00"),
            baseDate: makeSeoulDate(year: 2026, month: 7, day: 2),
            isStale: true,
            source: .seed
        )
        let viewModel = try makeAddExpenseHarness(rateProvider: StubRateProvider(quote: quote)).viewModel

        viewModel.selectedCurrency = .usd
        await viewModel.fetchRate()

        #expect(viewModel.isCurrentRateEstimated)
        #expect(viewModel.isCurrentRateStale == false)
    }

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
        #expect(viewModel.isCurrentRateEstimated)

        // 재fetch 전(동기 시점)에 이전 context의 프리뷰가 즉시 비워진다.
        let refreshTask = try viewModel.updateDate(makeSeoulDate(year: 2026, month: 7, day: 10))
        #expect(viewModel.currentRate == nil)
        #expect(viewModel.currentQuote == nil)
        #expect(viewModel.isCurrentRateEstimated == false)

        // 새 quote 로드 후 다시 채워진다.
        await refreshTask.value
        #expect(viewModel.currentRate == tts)
        #expect(viewModel.currentQuote == quote)
        #expect(viewModel.isCurrentRateEstimated)
    }
}

extension AddExpenseViewModelTests {
    @Test("edit init은 원본 거래 필드를 즉시 프리필한다")
    func editInitPrefillsOriginalTransaction() throws {
        let original = makeEditableTransaction(
            amount: decimalLiteral("456.78"),
            currencyCode: "CNY",
            categoryID: 31,
            assetID: 21,
            transactionType: .income,
            transactionDate: "2026-07-03",
            memo: "income memo"
        )
        let viewModel = try makeAddExpenseHarness(mode: .edit(original: original)).viewModel

        #expect(viewModel.mode == .edit(original: original))
        #expect(viewModel.selectedTab == .income)
        #expect(viewModel.amount == decimalLiteral("456.78"))
        #expect(viewModel.selectedCurrency == .cny)
        #expect(viewModel.selectedCategoryId == 31)
        #expect(viewModel.selectedAssetId == 21)
        #expect(ServerDateFormatter.localDate.string(from: viewModel.date) == "2026-07-03")
        #expect(viewModel.memo == "income memo")
    }

    @Test("edit init 프리필은 didSet 부수효과 없이 수행된다")
    func editInitPrefillDoesNotTriggerObserverSideEffects() async throws {
        let original = makeEditableTransaction(categoryID: 31, transactionType: .income)
        let viewModel = try makeAddExpenseHarness(mode: .edit(original: original)).viewModel

        // init 중 selectedTab didSet이 발동했다면 카탈로그 load Task가 스케줄됐을 것이다.
        await Task.yield()
        await Task.yield()

        #expect(viewModel.incomeCategories.isEmpty)
        #expect(viewModel.expenseCategories.isEmpty)
        #expect(viewModel.isLoadingCatalog == false)
        #expect(viewModel.selectedCategoryId == 31)
        #expect(viewModel.currentRate == nil)
    }

    @Test("edit init은 원본 날짜 파싱 실패 시 오늘 날짜를 유지한다")
    func editInitFallsBackToTodayWhenDateParsingFails() throws {
        let original = makeEditableTransaction(transactionDate: "not-a-date")
        let beforeInit = ServerDateFormatter.localDate.string(from: Date())
        let viewModel = try makeAddExpenseHarness(mode: .edit(original: original)).viewModel
        let afterInit = ServerDateFormatter.localDate.string(from: Date())

        // 자정 경계에서 init 전후 날짜가 다를 수 있으므로 둘 중 하나면 통과.
        let prefilled = ServerDateFormatter.localDate.string(from: viewModel.date)
        #expect(prefilled == beforeInit || prefilled == afterInit)
    }

    @Test("edit load는 유효한 원본 카테고리와 자산 선택을 보존한다")
    func editLoadPreservesOriginalSelections() async throws {
        let original = makeEditableTransaction(categoryID: 11, assetID: 21)
        let viewModel = try makeAddExpenseHarness(mode: .edit(original: original)).viewModel

        await viewModel.load()

        #expect(viewModel.selectedCategoryId == 11)
        #expect(viewModel.selectedAssetId == 21)
    }

    @Test("edit 탭 전환은 새 탭의 기본 카테고리를 선택한다")
    func editTabSwitchSelectsDefaultCategoryForNewTab() async throws {
        let original = makeEditableTransaction(categoryID: 11)
        let viewModel = try makeAddExpenseHarness(mode: .edit(original: original)).viewModel
        await viewModel.load()

        viewModel.selectedTab = .income

        #expect(viewModel.selectedCategoryId == 30)
        #expect(viewModel.selectedAssetId == 21)
    }

    @Test("카탈로그 로드 전 edit 탭 전환도 원본 자산을 보존하고 새 기본 카테고리를 선택한다")
    func editTabSwitchBeforeLoadPreservesAssetAndLoadsNewCategory() async throws {
        let original = makeEditableTransaction(categoryID: 11, assetID: 21)
        let viewModel = try makeAddExpenseHarness(mode: .edit(original: original)).viewModel

        viewModel.selectedTab = .income
        #expect(viewModel.selectedAssetId == 21)

        await viewModel.load()

        #expect(viewModel.selectedCategoryId == 30)
        #expect(viewModel.selectedAssetId == 21)
    }

    @Test("edit save는 update와 로컬 쓰기 트리거를 거쳐 식별자와 생성 시각을 보존한다")
    func editSaveUpdatesOriginalAndPreservesIdentity() async throws {
        let original = makeEditableTransaction()
        let trigger = FakeLocalWriteSyncTrigger()
        let harness = try makeAddExpenseHarness(
            rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            syncTrigger: trigger,
            mode: .edit(original: original)
        )
        _ = try await harness.repository.applyServerEntry(original, fullReplace: true)
        let viewModel = harness.viewModel
        await viewModel.load()
        viewModel.amount = decimalLiteral("999.99")
        viewModel.memo = " updated "

        await viewModel.save()

        let stored = try #require(
            try await harness.repository.transaction(clientEntryID: original.clientEntryID)
        )
        #expect(try await harness.repository.count() == 1)
        #expect(trigger.scheduleCount == 1)
        #expect(stored.clientEntryID == original.clientEntryID)
        #expect(stored.createdAt == original.createdAt)
        #expect(stored.amount == decimalLiteral("999.99"))
        #expect(stored.memo == "updated")
        #expect(stored.syncState == .pendingPush)
    }

    @Test("edit save는 외화 환산 필드를 생성과 동일 규칙으로 재계산한다")
    func editSaveRecomputesRateFieldsLikeCreate() async throws {
        let tts = try decimal("1411.23")
        let quote = try RateQuote(
            tts: tts,
            baseDate: makeSeoulDate(year: 2026, month: 7, day: 15),
            isStale: true,
            source: .server
        )
        let original = makeEditableTransaction()
        let harness = try makeAddExpenseHarness(
            rateProvider: StubRateProvider(quote: quote),
            mode: .edit(original: original)
        )
        _ = try await harness.repository.applyServerEntry(original, fullReplace: true)
        let viewModel = harness.viewModel
        await viewModel.load()
        viewModel.amount = 10

        await viewModel.save()

        let stored = try #require(
            try await harness.repository.transaction(clientEntryID: original.clientEntryID)
        )
        #expect(stored.currencyCode == "USD")
        #expect(stored.pending)
        #expect(stored.appliedRate == tts)
        #expect(stored.rateBaseDate == "2026-07-15")
        #expect(stored.krwAmount == decimalLiteral("14112.30"))
        #expect(stored.syncState == .pendingPush)
    }

    @Test("동시 edit save 호출은 update를 1회만 수행한다")
    func concurrentEditSaveCallsUpdateSingleTime() async throws {
        let original = makeEditableTransaction()
        let trigger = FakeLocalWriteSyncTrigger()
        let harness = try makeAddExpenseHarness(
            rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            syncTrigger: trigger,
            mode: .edit(original: original)
        )
        _ = try await harness.repository.applyServerEntry(original, fullReplace: true)
        let viewModel = harness.viewModel
        await viewModel.load()
        viewModel.amount = 321

        async let first: Void = viewModel.save()
        async let second: Void = viewModel.save()
        _ = await(first, second)

        #expect(try await harness.repository.count() == 1)
        #expect(trigger.scheduleCount == 1)
        #expect(viewModel.saveSucceeded == true)
        #expect(viewModel.isSaving == false)
    }

    @Test("edit update 대상이 사라졌으면 transactionNotFound를 노출한다")
    func editSaveReportsTransactionNotFound() async throws {
        let original = makeEditableTransaction()
        let trigger = FakeLocalWriteSyncTrigger()
        let harness = try makeAddExpenseHarness(
            rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            syncTrigger: trigger,
            mode: .edit(original: original)
        )

        await harness.viewModel.save()

        #expect(harness.viewModel.saveSucceeded == false)
        #expect(harness.viewModel.saveError == .transactionNotFound)
        let didMatchTransactionNotFound: Bool
        switch harness.viewModel.saveError {
        case .transactionNotFound:
            didMatchTransactionNotFound = true
        default:
            didMatchTransactionNotFound = false
        }
        #expect(didMatchTransactionNotFound)
        #expect(trigger.invocationCount == 1)
        #expect(trigger.scheduleCount == 0)
        #expect(try await harness.repository.count() == 0)
    }

    @Test("edit save 성공은 폼을 리셋하지 않고 완료 신호만 설정한다")
    func editSaveDoesNotResetForm() async throws {
        let original = makeEditableTransaction()
        let harness = try makeAddExpenseHarness(mode: .edit(original: original))
        _ = try await harness.repository.applyServerEntry(original, fullReplace: true)
        let viewModel = harness.viewModel
        await viewModel.load()

        await viewModel.save()

        #expect(viewModel.saveSucceeded)
        #expect(viewModel.amount == original.amount)
        #expect(viewModel.memo == original.memo)
        #expect(viewModel.selectedCurrency == .usd)
        #expect(viewModel.selectedCategoryId == original.categoryID)
        #expect(viewModel.selectedAssetId == original.assetID)
    }

    @Test("edit 재저장은 create 전용 리셋 폼 중복 가드를 적용하지 않는다")
    func editResaveDoesNotUseCreateDuplicateGuard() async throws {
        let original = makeEditableTransaction()
        let harness = try makeAddExpenseHarness(mode: .edit(original: original))
        _ = try await harness.repository.applyServerEntry(original, fullReplace: true)
        let viewModel = harness.viewModel

        await viewModel.save()
        #expect(viewModel.saveSucceeded)

        viewModel.amount = 0
        viewModel.memo = ""
        await viewModel.save()

        #expect(viewModel.saveSucceeded == false)
        #expect(viewModel.saveError == .invalidAmount)
    }

    @Test("edit delete는 로컬 쓰기 트리거를 거쳐 행을 삭제하고 true를 반환한다")
    func editDeleteRemovesOriginalAndReturnsTrue() async throws {
        let original = makeEditableTransaction()
        let trigger = FakeLocalWriteSyncTrigger()
        let harness = try makeAddExpenseHarness(
            rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            syncTrigger: trigger,
            mode: .edit(original: original)
        )
        _ = try await harness.repository.applyServerEntry(original, fullReplace: true)

        let didDelete = await harness.viewModel.deleteEntry()

        #expect(didDelete)
        #expect(trigger.scheduleCount == 1)
        #expect(try await harness.repository.transaction(clientEntryID: original.clientEntryID) == nil)
        #expect(try await harness.repository.pendingDeleteClientEntryIDs() == [original.clientEntryID])
        #expect(harness.viewModel.deleteError == nil)
    }

    @Test("edit delete 실패는 오류를 기록하고 false를 반환한다")
    func editDeleteFailureReturnsFalseAndStoresError() async throws {
        let original = makeEditableTransaction()
        let trigger = FailingLocalWriteSyncTrigger()
        let harness = try makeAddExpenseHarness(
            rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            syncTrigger: trigger,
            mode: .edit(original: original)
        )

        let didDelete = await harness.viewModel.deleteEntry()

        #expect(didDelete == false)
        #expect(trigger.scheduleCount == 1)
        #expect(harness.viewModel.deleteError != nil)
        #expect(harness.viewModel.isDeleting == false)
    }

    @Test("delete 중복 실행은 isDeleting으로 차단한다")
    func editDeletePreventsConcurrentExecution() async throws {
        let original = makeEditableTransaction()
        let trigger = BlockingLocalWriteSyncTrigger()
        let harness = try makeAddExpenseHarness(
            rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            syncTrigger: trigger,
            mode: .edit(original: original)
        )
        _ = try await harness.repository.applyServerEntry(original, fullReplace: true)

        let firstDelete = Task { await harness.viewModel.deleteEntry() }
        while trigger.scheduleCount == 0 {
            await Task.yield()
        }

        let duplicateResult = await harness.viewModel.deleteEntry()
        #expect(duplicateResult == false)
        #expect(harness.viewModel.isDeleting)
        #expect(trigger.scheduleCount == 1)

        trigger.resume()
        #expect(await firstDelete.value)
        #expect(harness.viewModel.isDeleting == false)
    }

    @Test("edit 저장 중 삭제 실행은 차단한다")
    func editDeleteIsBlockedWhileSaveIsInFlight() async throws {
        let original = makeEditableTransaction()
        let trigger = BlockingLocalWriteSyncTrigger()
        let harness = try makeAddExpenseHarness(
            rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            syncTrigger: trigger,
            mode: .edit(original: original)
        )
        _ = try await harness.repository.applyServerEntry(original, fullReplace: true)

        let save = Task { await harness.viewModel.save() }
        while trigger.scheduleCount == 0 {
            await Task.yield()
        }

        #expect(await harness.viewModel.deleteEntry() == false)
        #expect(trigger.scheduleCount == 1)
        #expect(harness.viewModel.isSaving)

        trigger.resume()
        await save.value
        #expect(harness.viewModel.saveSucceeded)
        #expect(try await harness.repository.transaction(clientEntryID: original.clientEntryID) != nil)
    }

    @Test("edit 삭제 중 저장 실행은 차단한다")
    func editSaveIsBlockedWhileDeleteIsInFlight() async throws {
        let original = makeEditableTransaction()
        let trigger = BlockingLocalWriteSyncTrigger()
        let harness = try makeAddExpenseHarness(
            rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            syncTrigger: trigger,
            mode: .edit(original: original)
        )
        _ = try await harness.repository.applyServerEntry(original, fullReplace: true)

        let delete = Task { await harness.viewModel.deleteEntry() }
        while trigger.scheduleCount == 0 {
            await Task.yield()
        }

        await harness.viewModel.save()
        #expect(harness.viewModel.saveSucceeded == false)
        #expect(trigger.scheduleCount == 1)
        #expect(harness.viewModel.isDeleting)

        trigger.resume()
        #expect(await delete.value)
        #expect(try await harness.repository.transaction(clientEntryID: original.clientEntryID) == nil)
    }

    @Test("create 모드 delete는 로컬 쓰기 없이 false를 반환한다")
    func createDeleteIsNoOp() async throws {
        let trigger = FakeLocalWriteSyncTrigger()
        let harness = try makeAddExpenseHarness(
            rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            syncTrigger: trigger
        )

        #expect(await harness.viewModel.deleteEntry() == false)
        #expect(trigger.scheduleCount == 0)
        #expect(harness.viewModel.deleteError == nil)
    }

    @Test("edit CNY 원본만 기본 통화 옵션에 동적으로 추가한다")
    func editCurrencyOptionsIncludeUnsupportedOriginal() throws {
        let cnyViewModel = try makeAddExpenseHarness(
            mode: .edit(original: makeEditableTransaction(currencyCode: "CNY"))
        ).viewModel
        let usdViewModel = try makeAddExpenseHarness(
            mode: .edit(original: makeEditableTransaction(currencyCode: "USD"))
        ).viewModel

        #expect(cnyViewModel.currencyOptions == [.krw, .usd, .eur, .jpy, .gbp, .cny])
        #expect(usdViewModel.currencyOptions == SelectableCurrency.entryPickerOptions)
    }
}
