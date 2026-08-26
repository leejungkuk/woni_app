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
    @Test("load는 시드 카탈로그를 로드하되 카테고리·자산을 자동 선택하지 않는다")
    func loadReadsSeedCatalogWithoutSelectingItems() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        await viewModel.load()

        #expect(viewModel.catalogError == nil)
        #expect(viewModel.isLoadingCatalog == false)
        #expect(viewModel.expenseCategories.map(\.id) == [10, 11])
        #expect(viewModel.incomeCategories.map(\.id) == [30, 31])
        #expect(viewModel.assets.map(\.id) == [20, 21])
        #expect(viewModel.selectedCategoryId == nil)
        #expect(viewModel.selectedAssetId == nil)
    }

    @Test("탭 전환은 카테고리·자산 선택을 모두 비운다")
    func tabSwitchClearsCategoryAndAssetSelection() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        await viewModel.load()
        #expect(viewModel.selectedTab == .expense)
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20

        viewModel.selectedTab = .income

        #expect(viewModel.visibleCategories.map(\.id) == [30, 31])
        #expect(viewModel.selectedCategoryId == nil)
        #expect(viewModel.selectedAssetId == nil)

        viewModel.selectedCategoryId = 30
        viewModel.selectedAssetId = 21
        viewModel.selectedTab = .expense

        #expect(viewModel.visibleCategories.map(\.id) == [10, 11])
        #expect(viewModel.selectedCategoryId == nil)
        #expect(viewModel.selectedAssetId == nil)
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
        #expect(viewModel.selectedToBaseRate != nil)
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
        #expect(viewModel.selectedToBaseRate == nil)
        #expect(viewModel.isCurrentRateStale == false)
        #expect(viewModel.isCurrentRateEstimated == false)
    }

    @Test("save 성공은 pending 외화 거래를 저장하고 폼 입력값을 정리하되 저장 통화를 유지한다")
    func saveSuccessInsertsPendingLocalTransactionAndKeepsCurrency() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        await viewModel.load()
        viewModel.amount = 1234
        viewModel.selectedCurrency = .usd
        viewModel.selectedCategoryId = 11
        viewModel.selectedAssetId = 21
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)
        viewModel.memo = "  라떼  "
        await viewModel.fetchRate()

        await viewModel.save()

        let stored = try #require(try await transactions(in: harness.repository, year: 2026, month: 7).first)
        let expectedAmount = Decimal(1234)

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
        #expect(stored.appliedRate == decimalLiteral("1400.00"))
        #expect(stored.rateBaseDate == "2026-07-02")
        #expect(stored.krwAmount == decimalLiteral("1727600.00"))

        #expect(viewModel.isSaving == false)
        #expect(viewModel.saveSucceeded == true)
        #expect(viewModel.saveError == nil)
        #expect(viewModel.amount == 0)
        #expect(viewModel.memo.isEmpty)
        #expect(viewModel.selectedCurrency == .usd)
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

        viewModel.selectedCurrency = .usd
        viewModel.amount = try decimal("0.01")
        #expect(viewModel.canSave == true)

        viewModel.amount = try decimal("99999999.00")
        #expect(viewModel.canSave == true)

        viewModel.amount = try decimal("99999999.01")
        #expect(viewModel.canSave == false)

        viewModel.selectedCurrency = .krw
        viewModel.amount = try decimal("1.01")
        #expect(viewModel.canSave == false)

        viewModel.selectedCurrency = .usd
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

        viewModel.selectedCurrency = .usd
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
}

extension AddExpenseViewModelTests {
    @Test("load 직후 신규 입력은 금액만 채워도 저장할 수 없다")
    func loadedCreateWithoutSelectionCannotSave() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        await viewModel.load()
        viewModel.amount = 5000

        #expect(viewModel.canSave == false)

        await viewModel.save()

        #expect(try await harness.repository.count() == 0)
        #expect(viewModel.saveSucceeded == false)
        #expect(viewModel.saveError == .missingSelection)
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

    private static func withLastUsedCurrencyStore(
        _ body: (LastUsedCurrencyStore) async throws -> Void
    ) async throws {
        let suiteName = "woni_appTests.AddExpenseViewModelTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await body(LastUsedCurrencyStore(userDefaults: userDefaults))
    }

    @Test("마지막 사용 통화가 없으면 신규 입력은 기준 통화로 시작한다")
    func createDefaultsToBaseCurrencyWithoutLastUsedCurrency() async throws {
        try await Self.withLastUsedCurrencyStore { store in
            let viewModel = try makeAddExpenseHarness(
                baseCurrency: .usd,
                lastUsedCurrencyStore: store
            ).viewModel

            #expect(store.lastUsedCurrency == nil)
            #expect(viewModel.selectedCurrency == .usd)
        }
    }

    @Test("신규 입력은 기준 통화보다 마지막 사용 통화를 우선한다")
    func createPrefersLastUsedCurrencyOverBaseCurrency() async throws {
        try await Self.withLastUsedCurrencyStore { store in
            store.record(.thb)

            let viewModel = try makeAddExpenseHarness(
                baseCurrency: .usd,
                lastUsedCurrencyStore: store
            ).viewModel

            #expect(viewModel.selectedCurrency == .thb)
        }
    }

    @Test("create 저장 성공은 사용한 통화를 마지막 사용 통화로 기록한다")
    func createSaveSuccessRecordsSelectedCurrency() async throws {
        try await Self.withLastUsedCurrencyStore { store in
            let harness = try makeAddExpenseHarness(lastUsedCurrencyStore: store)
            let viewModel = harness.viewModel
            await viewModel.load()
            viewModel.selectedCurrency = .thb
            viewModel.amount = 100
            viewModel.selectedCategoryId = 10
            viewModel.selectedAssetId = 20

            await viewModel.save()

            #expect(viewModel.saveSucceeded)
            #expect(viewModel.selectedCurrency == .thb)
            #expect(store.lastUsedCurrency == .thb)
        }
    }

    @Test("create 저장 실패는 마지막 사용 통화를 변경하지 않는다")
    func createSaveFailureDoesNotRecordSelectedCurrency() async throws {
        try await Self.withLastUsedCurrencyStore { store in
            store.record(.thb)
            let harness = try makeAddExpenseHarness(lastUsedCurrencyStore: store)
            let viewModel = harness.viewModel
            viewModel.selectedCurrency = .usd
            viewModel.amount = 0
            viewModel.selectedCategoryId = 10
            viewModel.selectedAssetId = 20

            await viewModel.save()

            #expect(try await harness.repository.count() == 0)
            #expect(viewModel.saveSucceeded == false)
            #expect(viewModel.saveError == .invalidAmount)
            #expect(store.lastUsedCurrency == .thb)
        }
    }

    /// 위 테스트는 금액 검증에서 막혀 저장 분기에 진입조차 못 하므로, record가 쓰기 앞으로
    /// 옮겨져도 통과한다. 이 테스트는 저장 분기에 진입시킨 뒤 실패시켜, record가 쓰기 시도
    /// 전체보다 앞으로 옮겨지는 회귀를 고정한다.
    /// 단, FailingLocalWriteSyncTrigger는 operation을 실행하지 않으므로 record가 closure 안
    /// insert 직전으로 옮겨지는 회귀까지는 잡지 못한다.
    @Test("create 저장이 로컬 쓰기에서 실패하면 마지막 사용 통화를 변경하지 않는다")
    func createSaveFailureDuringLocalWriteDoesNotRecordSelectedCurrency() async throws {
        try await Self.withLastUsedCurrencyStore { store in
            store.record(.thb)
            let trigger = FailingLocalWriteSyncTrigger()
            let harness = try makeAddExpenseHarness(
                rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
                lastUsedCurrencyStore: store,
                syncTrigger: trigger
            )
            let viewModel = harness.viewModel
            await viewModel.load()
            viewModel.selectedCurrency = .usd
            viewModel.amount = 100
            viewModel.selectedCategoryId = 10
            viewModel.selectedAssetId = 20

            await viewModel.save()

            #expect(trigger.scheduleCount == 1)
            #expect(viewModel.saveSucceeded == false)
            #expect(try await harness.repository.count() == 0)
            #expect(store.lastUsedCurrency == .thb)
        }
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
    @Test("AddEntry 통화 피커는 CNY를 포함한 13종을 노출한다")
    func entryPickerOptionsIncludeAllThirteenCurrencies() {
        #expect(SelectableCurrency.entryPickerOptions.contains(.cny))
        #expect(SelectableCurrency.entryPickerOptions.count == 13)
    }

    @Test("JPY 소수 금액은 저장 경계에서 거부한다")
    func saveRejectsFractionalJpyAmount() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        viewModel.selectedCurrency = .jpy
        viewModel.amount = try decimal("12.5")
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20

        #expect(viewModel.canSave == false)

        await viewModel.save()

        #expect(try await harness.repository.count() == 0)
        #expect(viewModel.saveSucceeded == false)
        #expect(viewModel.saveError == .invalidAmount)
    }

    @Test("JPY edit 모드는 원본 소수 금액을 허용 자릿수로 절삭한다")
    func editModeTruncatesFractionalJpyAmount() throws {
        let original = try makeEditableTransaction(
            amount: decimal("12.5"),
            currencyCode: "JPY"
        )
        let viewModel = try makeAddExpenseHarness(
            mode: .edit(original: original)
        ).viewModel

        #expect(viewModel.selectedCurrency == .jpy)
        #expect(viewModel.amount == Decimal(12))
    }

    @Test("USD 두 자리 소수 금액은 저장한다")
    func saveAcceptsTwoFractionDigitUsdAmount() async throws {
        let harness = try makeAddExpenseHarness()
        let viewModel = harness.viewModel

        viewModel.selectedCurrency = .usd
        viewModel.amount = try decimal("12.34")
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)

        #expect(viewModel.canSave)

        await viewModel.save()

        let stored = try #require(
            try await transactions(in: harness.repository, year: 2026, month: 7).first
        )
        let expectedAmount = try decimal("12.34")
        #expect(stored.amount == expectedAmount)
        #expect(stored.currencyCode == "USD")
        #expect(viewModel.saveSucceeded)
        #expect(viewModel.saveError == nil)
    }

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
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20

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

    @Test("edit load는 카탈로그에 없는 원본 카테고리·자산 id도 덮어쓰지 않는다")
    func editLoadKeepsSelectionsMissingFromCatalog() async throws {
        let original = makeEditableTransaction(categoryID: 999, assetID: 998)
        let viewModel = try makeAddExpenseHarness(mode: .edit(original: original)).viewModel

        await viewModel.load()

        // 칩은 미선택으로 보이지만 원본 id는 살아 있어야 저장 시 사용자 데이터가 바뀌지 않는다.
        #expect(viewModel.selectedCategoryId == 999)
        #expect(viewModel.selectedAssetId == 998)
        // 선택 id는 유지하되 목록에 없는 카테고리로는 저장할 수 없다(⑧ 가드) — 재선택 전 저장 비활성.
        #expect(viewModel.canSave == false)
    }

    @Test("edit 탭 전환도 신규와 동일하게 카테고리·자산 선택을 비운다")
    func editTabSwitchClearsCategoryAndAssetSelection() async throws {
        let original = makeEditableTransaction(categoryID: 11, assetID: 21)
        let viewModel = try makeAddExpenseHarness(mode: .edit(original: original)).viewModel
        await viewModel.load()

        viewModel.selectedTab = .income

        #expect(viewModel.selectedCategoryId == nil)
        #expect(viewModel.selectedAssetId == nil)
        #expect(viewModel.canSave == false)

        // 되돌아와도 원본 선택은 복원되지 않는다.
        viewModel.selectedTab = .expense

        #expect(viewModel.selectedCategoryId == nil)
        #expect(viewModel.selectedAssetId == nil)
    }

    @Test("카탈로그 로드 전 edit 탭 전환도 선택을 비우고 이후 load가 되살리지 않는다")
    func editTabSwitchBeforeLoadClearsSelectionAndLoadKeepsItEmpty() async throws {
        let original = makeEditableTransaction(categoryID: 11, assetID: 21)
        let viewModel = try makeAddExpenseHarness(mode: .edit(original: original)).viewModel

        viewModel.selectedTab = .income
        #expect(viewModel.selectedCategoryId == nil)
        #expect(viewModel.selectedAssetId == nil)

        await viewModel.load()

        #expect(viewModel.selectedCategoryId == nil)
        #expect(viewModel.selectedAssetId == nil)
    }

    @Test("edit save는 update와 로컬 쓰기 트리거를 거쳐 식별자와 생성 시각을 보존한다")
    func editSaveUpdatesOriginalAndPreservesIdentity() async throws {
        try await Self.withLastUsedCurrencyStore { store in
            store.record(.thb)
            let original = makeEditableTransaction()
            let trigger = FakeLocalWriteSyncTrigger()
            let harness = try makeAddExpenseHarness(
                rateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
                lastUsedCurrencyStore: store,
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
            #expect(store.lastUsedCurrency == .thb)
        }
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
}

/// base 프리뷰·저장 트랙 파생(AddExpenseViewModel+Rate.swift)의 계약을 검증한다.
extension AddExpenseViewModelTests {
    @Test("base=JPY 프리뷰는 크로스 환율을 쓰고 저장 필드는 KRW 계약을 유지한다")
    func jpyBasePreviewUsesCrossRateWhileSaveKeepsKrwContract() async throws {
        let usdQuote = try makeAddExpenseQuote(tts: "1000", source: .server)
        let jpyQuote = try makeAddExpenseQuote(tts: "1000", source: .cache)
        let provider = CurrencyAwareRateProvider(quotes: [
            .usd: usdQuote,
            .jpy: jpyQuote
        ])
        let harness = try makeAddExpenseHarness(
            rateProvider: provider,
            baseCurrency: .jpy
        )
        let viewModel = harness.viewModel
        viewModel.amount = 10
        viewModel.selectedCurrency = .usd
        viewModel.selectedCategoryId = 11
        viewModel.selectedAssetId = 21
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)

        await viewModel.fetchRate()

        #expect(viewModel.currentQuote == usdQuote)
        #expect(viewModel.currentBaseQuote == jpyQuote)
        #expect(viewModel.convertedBaseAmount == decimalLiteral("1000"))
        #expect(viewModel.selectedToBaseRate == decimalLiteral("100"))
        #expect(try CurrencyFormat.string(
            #require(viewModel.convertedBaseAmount),
            currencyCode: "JPY"
        ) == "1,000")
        #expect(try CurrencyFormat.rateString(
            #require(viewModel.selectedToBaseRate)
        ) == "100")

        await viewModel.save()

        let stored = try #require(
            try await transactions(in: harness.repository, year: 2026, month: 7).first
        )
        #expect(stored.currencyCode == "USD")
        #expect(stored.appliedRate == decimalLiteral("1000"))
        #expect(stored.rateBaseDate == "2026-07-02")
        #expect(stored.krwAmount == decimalLiteral("10000.00"))
    }

    @Test("선택 quote 성공과 base quote 실패는 프리뷰만 숨기고 저장은 정상 진행한다")
    func selectedQuoteSuccessAndBaseQuoteFailureStillSavesSelectedRate() async throws {
        let usdQuote = try makeAddExpenseQuote(tts: "1000", source: .server)
        let provider = CurrencyAwareRateProvider(quotes: [.usd: usdQuote])
        let harness = try makeAddExpenseHarness(
            rateProvider: provider,
            baseCurrency: .jpy
        )
        let viewModel = harness.viewModel
        viewModel.amount = 10
        viewModel.selectedCurrency = .usd
        viewModel.selectedCategoryId = 11
        viewModel.selectedAssetId = 21
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)

        await viewModel.fetchRate()

        #expect(viewModel.currentQuote == usdQuote)
        #expect(viewModel.currentBaseQuote == nil)
        #expect(viewModel.convertedBaseAmount == nil)
        #expect(viewModel.selectedToBaseRate == nil)

        await viewModel.save()

        let stored = try #require(
            try await transactions(in: harness.repository, year: 2026, month: 7).first
        )
        #expect(stored.appliedRate == decimalLiteral("1000"))
        #expect(stored.rateBaseDate == "2026-07-02")
        #expect(stored.krwAmount == decimalLiteral("10000.00"))
    }

    @Test("base quote 성공과 선택 quote 실패는 edit 저장 필드를 오염시키지 않는다")
    func baseQuoteSuccessAndSelectedQuoteFailureDoesNotPolluteEditSave() async throws {
        let jpyQuote = try makeAddExpenseQuote(tts: "1000", source: .cache)
        let provider = CurrencyAwareRateProvider(quotes: [.jpy: jpyQuote])
        let original = makeEditableTransaction()
        let harness = try makeAddExpenseHarness(
            rateProvider: provider,
            baseCurrency: .jpy,
            mode: .edit(original: original)
        )
        _ = try await harness.repository.applyServerEntry(original, fullReplace: true)
        let viewModel = harness.viewModel
        viewModel.amount = 10

        await viewModel.fetchRate()

        #expect(viewModel.currentQuote == nil)
        #expect(viewModel.currentBaseQuote == jpyQuote)
        #expect(viewModel.convertedBaseAmount == nil)

        await viewModel.save()

        let stored = try #require(
            try await harness.repository.transaction(clientEntryID: original.clientEntryID)
        )
        #expect(stored.appliedRate == nil)
        #expect(stored.rateBaseDate == nil)
        #expect(stored.krwAmount == nil)
    }

    @Test("선택 quote와 base quote의 stale 및 estimated 상태를 OR 결합한다")
    func selectedAndBaseQuoteFlagsAreCombined() async throws {
        let usdQuote = try makeAddExpenseQuote(
            tts: "1000",
            isStale: true,
            source: .server
        )
        let jpyQuote = try makeAddExpenseQuote(
            tts: "1000",
            isStale: true,
            source: .seed
        )
        let provider = CurrencyAwareRateProvider(quotes: [
            .usd: usdQuote,
            .jpy: jpyQuote
        ])
        let viewModel = try makeAddExpenseHarness(
            rateProvider: provider,
            baseCurrency: .jpy
        ).viewModel
        viewModel.selectedCurrency = .usd

        await viewModel.fetchRate()

        #expect(viewModel.isCurrentRateStale)
        #expect(viewModel.isCurrentRateEstimated)
    }

    @Test("선택 통화가 base면 프리뷰를 숨기고 KRW 선택은 JPY 프리뷰를 표시한다")
    func previewVisibilityIsSymmetricAroundBaseCurrency() async throws {
        let krwQuote = try makeAddExpenseQuote(tts: "1", source: .server)
        let jpyQuote = try makeAddExpenseQuote(tts: "1000", source: .cache)
        let provider = CurrencyAwareRateProvider(quotes: [
            .krw: krwQuote,
            .jpy: jpyQuote
        ])
        let viewModel = try makeAddExpenseHarness(
            rateProvider: provider,
            baseCurrency: .jpy
        ).viewModel
        viewModel.amount = 1000
        viewModel.selectedCurrency = .jpy

        await viewModel.fetchRate()

        #expect(viewModel.selectedToBaseRate == nil)
        // 동일 통화 환산은 identity로 유지한다(KRW base의 provisionalConversion 계약과 대칭).
        // rate가 nil이면 View가 프리뷰 행을 숨기므로 identity 값은 노출되지 않는다.
        #expect(viewModel.convertedBaseAmount == decimalLiteral("1000"))

        viewModel.selectedCurrency = .krw
        await viewModel.fetchRate()

        #expect(viewModel.convertedBaseAmount == decimalLiteral("100"))
        #expect(viewModel.selectedToBaseRate == decimalLiteral("0.1"))
    }

    @Test("base 환율 프리뷰 라벨은 방향·통화 코드·유효숫자 표기를 조합한다")
    func baseRatePreviewComposesDirectionalLabels() async throws {
        let usdQuote = try makeAddExpenseQuote(tts: "1000", source: .server)
        let jpyQuote = try makeAddExpenseQuote(tts: "1000", source: .cache)
        let provider = CurrencyAwareRateProvider(quotes: [
            .usd: usdQuote,
            .jpy: jpyQuote
        ])
        let viewModel = try makeAddExpenseHarness(
            rateProvider: provider,
            baseCurrency: .jpy
        ).viewModel
        viewModel.amount = 10
        viewModel.selectedCurrency = .usd

        await viewModel.fetchRate()

        #expect(viewModel.baseRatePreview(language: .ko) == BaseRatePreview(
            rateLabel: "USD 1.00 = JPY 100",
            convertedLabel: "JPY 1,000",
            staleDateLabel: nil
        ))
    }

    @Test("stale 환율 프리뷰는 선택 통화 quote의 기준일을 우선해 조립한다")
    func staleRatePreviewUsesSelectedQuoteBaseDateFirst() async throws {
        let selectedQuote = try RateQuote(
            tts: decimal("1406.93"),
            baseDate: makeSeoulDate(year: 2026, month: 5, day: 22),
            isStale: true,
            source: .server
        )
        let baseQuote = try RateQuote(
            tts: decimal("1000"),
            baseDate: makeSeoulDate(year: 2026, month: 5, day: 21),
            isStale: true,
            source: .cache
        )
        let viewModel = try makeAddExpenseHarness(
            rateProvider: CurrencyAwareRateProvider(quotes: [
                .usd: selectedQuote,
                .jpy: baseQuote
            ]),
            baseCurrency: .jpy
        ).viewModel
        viewModel.amount = 1
        viewModel.selectedCurrency = .usd

        await viewModel.fetchRate()

        #expect(viewModel.baseRatePreview(language: .ko)?.staleDateLabel == "기준일 5월 22일")
        #expect(viewModel.baseRatePreview(language: .en)?.staleDateLabel == "Rate date May 22")
    }

    @Test("stale quote의 기준일이 없으면 기존 문구를 유지한다")
    func staleRatePreviewWithoutBaseDateKeepsPreviousLabel() async throws {
        // 실제 provider가 만들 수 없는 isStale=true + baseDate=nil 방어 분기를 검증한다.
        let quote = RateQuote(
            tts: decimalLiteral("1406.93"),
            baseDate: nil,
            isStale: true,
            source: .server
        )
        let viewModel = try makeAddExpenseHarness(
            rateProvider: CurrencyAwareRateProvider(quotes: [.usd: quote])
        ).viewModel
        viewModel.amount = 1
        viewModel.selectedCurrency = .usd

        await viewModel.fetchRate()

        #expect(viewModel.baseRatePreview(language: .ko)?.staleDateLabel == "기준일 다름")
    }

    @Test("동일 통화 선택과 base quote 실패는 프리뷰 라벨을 만들지 않는다")
    func baseRatePreviewIsNilWithoutCrossRate() async throws {
        let jpyQuote = try makeAddExpenseQuote(tts: "1000", source: .cache)
        let sameCurrency = try makeAddExpenseHarness(
            rateProvider: CurrencyAwareRateProvider(quotes: [.jpy: jpyQuote]),
            baseCurrency: .jpy
        ).viewModel
        sameCurrency.amount = 1000
        sameCurrency.selectedCurrency = .jpy

        await sameCurrency.fetchRate()

        #expect(sameCurrency.baseRatePreview(language: .ko) == nil)

        let usdQuote = try makeAddExpenseQuote(tts: "1000", source: .server)
        let missingBase = try makeAddExpenseHarness(
            rateProvider: CurrencyAwareRateProvider(quotes: [.usd: usdQuote]),
            baseCurrency: .jpy
        ).viewModel
        missingBase.amount = 10
        missingBase.selectedCurrency = .usd

        await missingBase.fetchRate()

        #expect(missingBase.baseRatePreview(language: .ko) == nil)
    }

    @Test("프리뷰는 반올림 없는 원시 KRW를 쓰고 저장은 2자리 반올림 KRW를 쓴다")
    func previewUsesRawKrwWhileSaveRoundsToTwoDigits() async throws {
        let usdQuote = try makeAddExpenseQuote(tts: "1411.23", source: .server)
        let jpyQuote = try makeAddExpenseQuote(tts: "1000", source: .cache)
        let provider = CurrencyAwareRateProvider(quotes: [
            .usd: usdQuote,
            .jpy: jpyQuote
        ])
        let harness = try makeAddExpenseHarness(
            rateProvider: provider,
            baseCurrency: .jpy
        )
        let viewModel = harness.viewModel
        viewModel.amount = decimalLiteral("11.15")
        viewModel.selectedCurrency = .usd
        viewModel.selectedCategoryId = 11
        viewModel.selectedAssetId = 21
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)

        await viewModel.fetchRate()

        // 원시 KRW 11.15×1411.23=15735.2145 ÷ krwPerUnit(JPY)=10.
        // 저장용 2자리 반올림(15735.21)을 재사용하면 1573.521이 되어 실패한다.
        #expect(viewModel.convertedBaseAmount == decimalLiteral("1573.52145"))

        await viewModel.save()

        let stored = try #require(
            try await transactions(in: harness.repository, year: 2026, month: 7).first
        )
        #expect(stored.appliedRate == decimalLiteral("1411.23"))
        #expect(stored.krwAmount == decimalLiteral("15735.21"))
    }

    @Test("날짜 D1→D2 변경과 역순 완료에서도 최신 날짜 generation 두 quote만 원자 commit한다")
    func dateGenerationRejectsSupersededAndReverseCompletion() async throws {
        let provider = CurrencyAwareRateProvider(defersResponses: true)
        let viewModel = try makeAddExpenseHarness(
            rateProvider: provider,
            baseCurrency: .jpy
        ).viewModel
        viewModel.selectedCurrency = .usd

        // 세 세대 모두 updateDate로 구동해 반환 Task를 barrier로 쓴다.
        // 이전 세대 fetchRate 완료를 value로 확정해야 단언 이후 stale commit이 불가능하다.
        let firstTask = try viewModel.updateDate(makeSeoulDate(year: 2026, month: 7, day: 1))
        await provider.waitForRequestCount(2)
        let firstGeneration = await provider.requests()

        let secondTask = try viewModel.updateDate(makeSeoulDate(year: 2026, month: 7, day: 2))
        await provider.waitForRequestCount(4)
        let secondGeneration = Array((await provider.requests()).suffix(2))

        let thirdTask = try viewModel.updateDate(makeSeoulDate(year: 2026, month: 7, day: 3))
        await provider.waitForRequestCount(6)
        let thirdGeneration = Array((await provider.requests()).suffix(2))
        let latestUSDQuote = try makeAddExpenseQuote(tts: "1300", source: .server)
        let latestJPYQuote = try makeAddExpenseQuote(tts: "900", source: .cache)

        for request in thirdGeneration {
            await provider.resume(
                requestID: request.id,
                with: request.currency == .usd ? latestUSDQuote : latestJPYQuote
            )
        }
        await thirdTask.value
        #expect(viewModel.currentQuote == latestUSDQuote)
        #expect(viewModel.currentBaseQuote == latestJPYQuote)

        let supersededUSDQuote = try makeAddExpenseQuote(tts: "1200", source: .server)
        let supersededJPYQuote = try makeAddExpenseQuote(tts: "800", source: .seed)
        for request in secondGeneration.reversed() {
            await provider.resume(
                requestID: request.id,
                with: request.currency == .usd ? supersededUSDQuote : supersededJPYQuote
            )
        }
        await secondTask.value

        let oldestUSDQuote = try makeAddExpenseQuote(tts: "1100", source: .server)
        let oldestJPYQuote = try makeAddExpenseQuote(tts: "700", source: .cache)
        for request in firstGeneration.reversed() {
            await provider.resume(
                requestID: request.id,
                with: request.currency == .usd ? oldestUSDQuote : oldestJPYQuote
            )
        }
        await firstTask.value

        #expect(viewModel.currentQuote == latestUSDQuote)
        #expect(viewModel.currentBaseQuote == latestJPYQuote)
        #expect(viewModel.currentRate == latestUSDQuote.tts)
    }

    @Test("USD→JPY→USD ABA와 역순 완료에서도 최신 generation 두 quote만 원자 commit한다")
    func rateGenerationRejectsAbaAndReverseCompletion() async throws {
        let provider = CurrencyAwareRateProvider(defersResponses: true)
        let viewModel = try makeAddExpenseHarness(
            rateProvider: provider,
            baseCurrency: .jpy
        ).viewModel
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)

        viewModel.updateCurrency(.usd)
        await provider.waitForRequestCount(2)
        let firstGeneration = await provider.requests()

        viewModel.updateCurrency(.jpy)
        await provider.waitForRequestCount(4)
        let secondGeneration = Array((await provider.requests()).suffix(2))

        viewModel.updateCurrency(.usd)
        await provider.waitForRequestCount(6)
        let thirdGeneration = Array((await provider.requests()).suffix(2))
        let latestUSDQuote = try makeAddExpenseQuote(tts: "1300", source: .server)
        let latestJPYQuote = try makeAddExpenseQuote(tts: "900", source: .cache)
        let latestSelectedRequest = try #require(
            thirdGeneration.first { $0.currency == .usd }
        )
        let latestBaseRequest = try #require(
            thirdGeneration.first { $0.currency == .jpy }
        )

        await provider.resume(requestID: latestSelectedRequest.id, with: latestUSDQuote)
        await yieldSeveralTimes()
        #expect(viewModel.currentQuote == nil)
        #expect(viewModel.currentBaseQuote == nil)

        await provider.resume(requestID: latestBaseRequest.id, with: latestJPYQuote)
        await yieldUntil { viewModel.currentQuote == latestUSDQuote }
        #expect(viewModel.currentQuote == latestUSDQuote)
        #expect(viewModel.currentBaseQuote == latestJPYQuote)

        let supersededJPYQuote = try makeAddExpenseQuote(tts: "800", source: .seed)
        for request in secondGeneration.reversed() {
            await provider.resume(requestID: request.id, with: supersededJPYQuote)
        }
        let oldestUSDQuote = try makeAddExpenseQuote(tts: "1100", source: .server)
        let oldestJPYQuote = try makeAddExpenseQuote(tts: "700", source: .cache)
        for request in firstGeneration.reversed() {
            await provider.resume(
                requestID: request.id,
                with: request.currency == .usd ? oldestUSDQuote : oldestJPYQuote
            )
        }
        await yieldSeveralTimes()

        #expect(viewModel.currentQuote == latestUSDQuote)
        #expect(viewModel.currentBaseQuote == latestJPYQuote)
        #expect(viewModel.currentRate == latestUSDQuote.tts)
    }

    @Test("상태 변경 직후 이전 요청만 완료돼도 동기 generation 증가가 commit을 차단한다")
    func synchronousGenerationInvalidationRejectsImmediatelyCompletedOldRequest() async throws {
        let provider = CurrencyAwareRateProvider(defersResponses: true)
        let viewModel = try makeAddExpenseHarness(
            rateProvider: provider,
            baseCurrency: .jpy
        ).viewModel

        viewModel.updateCurrency(.usd)
        await provider.waitForRequestCount(2)
        let oldRequests = await provider.requests()

        viewModel.updateCurrency(.eur)

        let oldUSDQuote = try makeAddExpenseQuote(tts: "1100", source: .server)
        let oldJPYQuote = try makeAddExpenseQuote(tts: "700", source: .cache)
        for request in oldRequests {
            await provider.resume(
                requestID: request.id,
                with: request.currency == .usd ? oldUSDQuote : oldJPYQuote
            )
        }
        await yieldSeveralTimes()
        #expect(viewModel.currentQuote == nil)
        #expect(viewModel.currentBaseQuote == nil)

        await provider.waitForRequestCount(4)
        let newRequests = Array((await provider.requests()).suffix(2))
        let eurQuote = try makeAddExpenseQuote(tts: "1600", source: .server)
        let jpyQuote = try makeAddExpenseQuote(tts: "1000", source: .cache)
        for request in newRequests {
            await provider.resume(
                requestID: request.id,
                with: request.currency == .eur ? eurQuote : jpyQuote
            )
        }
        await yieldUntil { viewModel.currentQuote == eurQuote }

        #expect(viewModel.currentQuote == eurQuote)
        #expect(viewModel.currentBaseQuote == jpyQuote)
    }
}

// MARK: - 커스텀 카테고리 병합·⑧ 수정 화면 가드

extension AddExpenseViewModelTests {
    @Test("visibleCategories는 커스텀(최신 우선)을 기본 카탈로그 앞에 탭별로 병합한다")
    func visibleCategoriesPrependCustomBeforeBaseCatalog() async throws {
        let store = try makeCustomCategoryStore([
            CachedCustomCategory(id: 100, transactionType: .expense, name: "🍕 야식"),
            CachedCustomCategory(id: 90, transactionType: .expense, name: "🚕 택시"),
            CachedCustomCategory(id: -1, transactionType: .expense, name: "로컬 이전"),
            CachedCustomCategory(id: -2, transactionType: .expense, name: "로컬 최신"),
            CachedCustomCategory(id: 200, transactionType: .income, name: "💰 용돈")
        ])
        let viewModel = try makeAddExpenseHarness(customCategoryStore: store).viewModel

        await viewModel.load()

        #expect(viewModel.visibleCategories.map(\.id) == [-2, -1, 100, 90, 10, 11])

        viewModel.selectedTab = .income

        #expect(viewModel.visibleCategories.map(\.id) == [200, 30, 31])
    }

    @Test("칩 목록은 관리 화면에서 확정한 재정렬 순서를 그대로 따른다")
    func visibleCategoriesFollowReorderedStoreOrder() async throws {
        let store = try makeCustomCategoryStore([
            CachedCustomCategory(id: 100, transactionType: .expense, name: "🍕 야식"),
            CachedCustomCategory(id: 90, transactionType: .expense, name: "🚕 택시"),
            CachedCustomCategory(id: 80, transactionType: .expense, name: "☕️ 커피")
        ])
        let viewModel = try makeAddExpenseHarness(customCategoryStore: store).viewModel
        await viewModel.load()
        #expect(viewModel.visibleCategories.map(\.id) == [100, 90, 80, 10, 11])

        try await store.reorder(orderedIDs: [90, 80, 100], type: .expense)

        // 재정렬 순서가 그대로 오고(id 내림차순으로 되돌아가지 않고), 기본 카탈로그는 뒤에 시드 순서로 남는다.
        #expect(viewModel.visibleCategories.map(\.id) == [90, 80, 100, 10, 11])
    }

    @Test("복귀 연동: 추가한 타입 탭으로 전환하고 새 카테고리를 선택한다")
    func adoptCreatedCategorySwitchesTabAndSelects() async throws {
        let store = try makeCustomCategoryStore([
            CachedCustomCategory(id: 300, transactionType: .income, name: "💰 용돈")
        ])
        let viewModel = try makeAddExpenseHarness(customCategoryStore: store).viewModel
        await viewModel.load()
        #expect(viewModel.selectedTab == .expense)

        viewModel.adoptCreatedCategory(id: 300, type: .income)

        #expect(viewModel.selectedTab == .income)
        #expect(viewModel.selectedCategoryId == 300)
    }

    @Test("복귀 연동: 같은 탭이면 전환 없이 선택만 바꾼다")
    func adoptCreatedCategorySameTabJustSelects() async throws {
        let store = try makeCustomCategoryStore([
            CachedCustomCategory(id: 90, transactionType: .expense, name: "🚕 택시")
        ])
        let viewModel = try makeAddExpenseHarness(customCategoryStore: store).viewModel
        await viewModel.load()
        viewModel.selectedAssetId = 20

        viewModel.adoptCreatedCategory(id: 90, type: .expense)

        #expect(viewModel.selectedTab == .expense)
        #expect(viewModel.selectedCategoryId == 90)
        // 같은 탭 채택은 didSet 전환을 타지 않아 자산 선택이 유지된다.
        #expect(viewModel.selectedAssetId == 20)
    }

    @Test("재매핑된 생성 id는 선택 가드·저장 payload·칩 하이라이트에 새 id로 반영된다")
    func remappedCategoryIDRemainsSelectedAndSavesResolvedID() async throws {
        // 오프라인에서 만든 음수 id를 먼저 선택한 뒤, 그 상태로 큐가 도는 순서를 재현한다.
        // 순서를 뒤집어 remap을 먼저 기록하면 선택 시점에 이미 새 id로 치환돼,
        // 읽는 쪽이 resolve하지 않아도 통과하는 무력한 테스트가 된다.
        let store = try makeCustomCategoryStore(
            [CachedCustomCategory(id: -1, transactionType: .expense, name: "온라인", syncState: .pendingCreate)],
            service: CreatingCustomCategoryServiceStub(createdID: 40)
        )
        let harness = try makeAddExpenseHarness(customCategoryStore: store)
        let viewModel = harness.viewModel
        await viewModel.load()
        viewModel.adoptCreatedCategory(id: -1, type: .expense)
        #expect(viewModel.selectedCategoryId == -1)

        await store.flushPending()
        #expect(store.resolvedID(for: -1) == 40)
        // 선택 상태는 옛 음수 id를 그대로 들고 있어야 회귀를 검증할 수 있다.
        #expect(viewModel.selectedCategoryId == -1)

        viewModel.amount = 100
        viewModel.selectedAssetId = 20
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)

        // 읽는 세 지점이 모두 resolvedID를 거쳐야 통과한다 — raw 비교로 되돌리면 전부 깨진다.
        #expect(viewModel.isSelectedCategoryMissing == false)
        #expect(viewModel.isCategorySelected(id: 40))
        #expect(viewModel.isCategorySelected(id: -1) == false)

        await viewModel.save()

        let stored = try #require(
            try await transactions(in: harness.repository, year: 2026, month: 7).first
        )
        #expect(stored.categoryID == 40)
    }

    @Test("탭 전환은 커스텀 카테고리 선택도 비운다")
    func tabSwitchClearsCustomCategorySelection() async throws {
        let store = try makeCustomCategoryStore([
            CachedCustomCategory(id: 90, transactionType: .expense, name: "🚕 택시")
        ])
        let viewModel = try makeAddExpenseHarness(customCategoryStore: store).viewModel
        await viewModel.load()
        let custom = try #require(viewModel.visibleCategories.first { $0.id == 90 })
        viewModel.selectCategory(custom)
        #expect(viewModel.selectedCategoryId == 90)

        viewModel.selectedTab = .income

        #expect(viewModel.selectedCategoryId == nil)
    }

    @Test("⑧ 가드: 목록에 없는 원본 카테고리는 저장을 막고 재선택하면 푼다")
    func editGuardDisablesSaveForMissingCategoryUntilReselection() async throws {
        let original = makeEditableTransaction(categoryID: 999)
        let viewModel = try makeAddExpenseHarness(mode: .edit(original: original)).viewModel

        // 카탈로그 로드 전에는 빈 목록을 "삭제됨"으로 오판하지 않는다.
        #expect(viewModel.isSelectedCategoryMissing == false)

        await viewModel.load()

        #expect(viewModel.isSelectedCategoryMissing == true)
        #expect(viewModel.canSave == false)

        let replacement = try #require(viewModel.visibleCategories.first)
        viewModel.selectCategory(replacement)

        #expect(viewModel.isSelectedCategoryMissing == false)
        #expect(viewModel.canSave == true)
    }

    @Test("⑧ 가드 토스트 문구는 ko/en 쌍으로 제공된다")
    func categoryDeletedToastStringsProvideKoreanAndEnglish() {
        #expect(WoniStrings.categoryDeletedReselectToast(.ko)
            == "쓰던 카테고리가 삭제됐어요. 다시 선택해 주세요.")
        #expect(WoniStrings.categoryDeletedReselectToast(.en)
            == "The category you were using was deleted. Please select another one.")
    }

    @Test("⑧ 가드: store 목록 변경 시 선택 유효성을 재평가한다")
    func editGuardReevaluatesWhenStoreListChanges() async throws {
        let store = try makeCustomCategoryStore([
            CachedCustomCategory(id: 90, transactionType: .expense, name: "🚕 택시")
        ])
        let original = makeEditableTransaction(categoryID: 90)
        let viewModel = try makeAddExpenseHarness(
            customCategoryStore: store,
            mode: .edit(original: original)
        ).viewModel
        await viewModel.load()
        #expect(viewModel.isSelectedCategoryMissing == false)
        #expect(viewModel.canSave == true)

        // 수정 화면 위에서 관리 화면이 현재 선택 카테고리를 지운 것과 동일한 목록 변경.
        try await store.clear()

        #expect(viewModel.isSelectedCategoryMissing == true)
        #expect(viewModel.canSave == false)
        // 선택 id는 비우지 않는다 — 기존 "원본 id 유지" 계약과 공존해야 한다.
        #expect(viewModel.selectedCategoryId == 90)
    }

    @Test("커스텀 카테고리 선택도 기존 저장 경로로 그대로 기록된다")
    func saveWithCustomCategoryPersistsThroughExistingPath() async throws {
        let store = try makeCustomCategoryStore([
            CachedCustomCategory(id: 90, transactionType: .expense, name: "🚕 택시")
        ])
        let harness = try makeAddExpenseHarness(customCategoryStore: store)
        let viewModel = harness.viewModel
        await viewModel.load()
        viewModel.amount = 5000
        viewModel.selectedCategoryId = 90
        viewModel.selectedAssetId = 20
        viewModel.date = try makeSeoulDate(year: 2026, month: 7, day: 2)

        await viewModel.save()

        #expect(viewModel.saveSucceeded == true)
        let stored = try #require(
            try await transactions(in: harness.repository, year: 2026, month: 7).first
        )
        #expect(stored.categoryID == 90)
    }

    @Test("id 자동 선택은 현재 목록에 있는 것만 반영하고 없는 id는 무시한다")
    func selectCategoryByIDIgnoresUnknownID() async throws {
        let store = try makeCustomCategoryStore([
            CachedCustomCategory(id: 90, transactionType: .expense, name: "🚕 택시")
        ])
        let viewModel = try makeAddExpenseHarness(customCategoryStore: store).viewModel
        await viewModel.load()

        // 폐기된 id를 선택 상태로 만들지 않는다(결정 10의 stale 방어).
        viewModel.selectCategory(id: 9999)
        #expect(viewModel.selectedCategoryId == nil)

        viewModel.selectCategory(id: 90)
        #expect(viewModel.selectedCategoryId == 90)
    }

    @Test("카테고리 관리는 세션 없음 익명 회원 모두 진입할 수 있다")
    func canManageCategoriesForEverySessionType() async throws {
        let guestAuth = FakeAuthService()
        let guest = try makeAddExpenseHarness(
            customCategoryStore: makeCustomCategoryStore(authProvider: guestAuth)
        )
        #expect(guest.viewModel.canManageCategories)

        try await guestAuth.ensureIdentity()
        #expect(guest.viewModel.canManageCategories)

        let memberAuth = FakeAuthService()
        try await memberAuth.signIn(.google)
        let member = try makeAddExpenseHarness(
            customCategoryStore: makeCustomCategoryStore(authProvider: memberAuth)
        )
        #expect(member.viewModel.canManageCategories)
    }
}

private func makeAddExpenseQuote(
    tts: String,
    isStale: Bool = false,
    source: RateQuote.Source
) throws -> RateQuote {
    try RateQuote(
        tts: decimal(tts),
        baseDate: makeSeoulDate(year: 2026, month: 7, day: 2),
        isStale: isStale,
        source: source
    )
}

@MainActor
private func yieldSeveralTimes() async {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
}

/// yield 횟수가 아니라 실제 시간으로 상한을 둔다. CI의 병렬 시뮬레이터 부하에서는
/// 고정 횟수 yield가 대상 Task 스케줄 전에 소진돼 거짓 실패를 만든다.
@MainActor
private func yieldUntil(_ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    Issue.record("비동기 환율 상태가 제한 시간 내 commit되지 않았습니다")
}
