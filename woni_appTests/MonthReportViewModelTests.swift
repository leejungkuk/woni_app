//
//  MonthReportViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct MonthReportViewModelTests {
    @Test("start는 진입 selector와 오류를 즉시 초기화한다")
    func startResetsEntrySelectorsAndError() async throws {
        let loader = MutableMonthReportLoader()
        loader.error = MonthReportViewModelTestError.loadFailure
        let viewModel = try makeViewModel(loadTransactions: loader.load)

        await viewModel.reload()
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.isLoading)
        viewModel.setKind(.income)
        viewModel.setSort(field: .amount)
        viewModel.setSort(field: .amount)

        loader.error = nil
        viewModel.start(
            month: MainMonth(year: 2026, month: 2),
            language: .en,
            baseCurrency: .usd,
            revision: 4
        )

        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.selectedKind == .expense)
        #expect(viewModel.sortField == .date)
        #expect(viewModel.isDescending)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.baseCurrency == .usd)
        await waitUntil { !viewModel.isLoading }
    }

    @Test("start는 이전 집계를 첫 프레임에 남기지 않고 빈 로딩 골격을 즉시 커밋한다")
    func startSynchronouslyCommitsEmptyLoadingSkeleton() async throws {
        let transactions = [makeTransaction(amount: 120, transactionDate: "2026-01-15")]
        let viewModel = try makeViewModel(loadTransactions: { _ in transactions })
        await viewModel.reload()
        #expect(viewModel.summary.expense == 120)
        #expect(!viewModel.expenseCategoryItems.isEmpty)

        viewModel.start(
            month: MainMonth(year: 2026, month: 2),
            language: .ko,
            baseCurrency: .krw,
            revision: 0
        )

        #expect(viewModel.isLoading)
        #expect(viewModel.summary == .empty)
        #expect(viewModel.expenseCategoryItems.isEmpty)
        #expect(viewModel.incomeCategoryItems.isEmpty)
        #expect(viewModel.categoryItems.isEmpty)
        #expect(viewModel.donutSlices.isEmpty)
        await waitUntil { !viewModel.isLoading }
    }

    @Test("모드 전환은 지출 수입 합계별 소계와 선택 합계를 바꾼다")
    func kindSelectionChangesCategorySubtotalsAndSelectedTotal() async throws {
        let transactions = [
            makeTransaction(amount: 100, categoryID: 10, transactionType: .expense),
            makeTransaction(amount: 50, categoryID: 11, transactionType: .expense),
            makeTransaction(amount: 400, categoryID: 30, transactionType: .income)
        ]
        let viewModel = try makeViewModel(loadTransactions: { _ in transactions })
        await viewModel.reload()

        #expect(viewModel.categoryItems.map(\.amount) == [100, 50])
        #expect(viewModel.selectedTotal == 150)
        #expect(viewModel.donutSlices.count == 2)

        viewModel.setKind(.income)
        #expect(viewModel.categoryItems.map(\.amount) == [400])
        #expect(viewModel.selectedTotal == 400)
        #expect(viewModel.donutSlices.count == 1)

        viewModel.setKind(.total)
        #expect(viewModel.categoryItems.isEmpty)
        #expect(viewModel.donutSlices.isEmpty)
        #expect(viewModel.selectedTotal == 250)
        #expect(viewModel.expenseCategoryItems.map(\.amount) == [100, 50])
        #expect(viewModel.incomeCategoryItems.map(\.amount) == [400])
    }
}

extension MonthReportViewModelTests {
    @Test("같은 달의 낡은 로드는 새 결과를 덮거나 현재 로딩을 끝내지 않는다")
    func staleSameMonthLoadCannotOverwriteOrFinishCurrentLoad() async throws {
        let loader = DeferredMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load)
        let month = LedgerMonth(year: 2026, month: 1)

        let staleLoad = Task { await viewModel.reload() }
        await loader.waitForRequestCount(1)
        let newerLoad = Task { await viewModel.reload() }
        await loader.waitForRequestCount(2)

        loader.resumeLast(
            month: month,
            returning: [makeTransaction(amount: 200)]
        )
        await newerLoad.value
        #expect(viewModel.summary.expense == 200)

        let currentLoad = Task { await viewModel.reload() }
        await loader.waitForRequestCount(3)
        loader.resumeFirst(
            month: month,
            returning: [makeTransaction(amount: 999)]
        )
        await staleLoad.value

        #expect(viewModel.summary.expense == 200)
        #expect(viewModel.isLoading)

        loader.resumeFirst(month: month, returning: [makeTransaction(amount: 300)])
        await currentLoad.value
        #expect(viewModel.summary.expense == 300)
        #expect(!viewModel.isLoading)
    }

    @Test("월을 바꾼 뒤 늦게 성공한 이전 로드는 새 월 골격과 로딩을 덮지 않는다")
    func staleSuccessfulLoadCannotOverwriteNewMonth() async throws {
        let loader = DeferredMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load)

        let januaryLoad = Task { await viewModel.reload() }
        await loader.waitForRequestCount(1)
        viewModel.setMonth(MainMonth(year: 2026, month: 2))
        await loader.waitForRequestCount(2)

        loader.resumeFirst(
            month: LedgerMonth(year: 2026, month: 1),
            returning: [makeTransaction(amount: 999, transactionDate: "2026-01-15")]
        )
        await januaryLoad.value

        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.summary == .empty)
        #expect(viewModel.expenseCategoryItems.isEmpty)
        #expect(viewModel.isLoading)
        #expect(viewModel.errorMessage == nil)

        loader.resumeFirst(
            month: LedgerMonth(year: 2026, month: 2),
            returning: [makeTransaction(amount: 200, transactionDate: "2026-02-01")]
        )
        await waitUntil { !viewModel.isLoading }

        #expect(viewModel.summary.expense == 200)
        #expect(viewModel.expenseCategoryItems.map(\.amount) == [200])
    }

    @Test("월을 바꾼 뒤 늦게 실패한 이전 로드는 새 로딩을 끄거나 오류를 넣지 않는다")
    func staleFailedLoadCannotFinishOrSetError() async throws {
        let loader = DeferredMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load)

        let januaryLoad = Task { await viewModel.reload() }
        await loader.waitForRequestCount(1)
        viewModel.setMonth(MainMonth(year: 2026, month: 2))
        await loader.waitForRequestCount(2)

        loader.resumeFirst(
            month: LedgerMonth(year: 2026, month: 1),
            throwing: MonthReportViewModelTestError.loadFailure
        )
        await januaryLoad.value

        #expect(viewModel.isLoading)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.summary == .empty)

        loader.resumeFirst(month: LedgerMonth(year: 2026, month: 2), returning: [])
        await waitUntil { !viewModel.isLoading }
        #expect(viewModel.errorMessage == nil)
    }

    @Test("상세 파생은 선택 모드와 무관하게 categoryID만으로 필터한다")
    func detailDerivationFiltersOnlyByCategoryID() async throws {
        let includedID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000000"))
        let otherID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000000"))
        let transactions = [
            makeTransaction(
                clientEntryID: includedID,
                amount: 100,
                categoryID: 10,
                transactionType: .expense,
                memo: " lunch "
            ),
            makeTransaction(
                clientEntryID: otherID,
                amount: 300,
                categoryID: 30,
                transactionType: .income,
                memo: "salary"
            )
        ]
        let viewModel = try makeViewModel(loadTransactions: { _ in transactions })
        await viewModel.reload()
        viewModel.setKind(.total)

        #expect(viewModel.entryRows(categoryID: 10) == [
            ReportEntryRow(
                id: includedID,
                transactionDate: "2026-01-15",
                amount: 100,
                memo: "lunch"
            )
        ])
        #expect(viewModel.categoryTotal(categoryID: 10) == 100)
        #expect(viewModel.categoryDisplayName(categoryID: 10) == "fork.knife 식비")
        #expect(viewModel.transaction(clientEntryID: includedID)?.clientEntryID == includedID)
        #expect(viewModel.transaction(clientEntryID: UUID()) == nil)

        viewModel.applyLanguage(.en)
        #expect(viewModel.categoryDisplayName(categoryID: 10) == "fork.knife Food")
    }

    @Test("상세 행 날짜는 현재 언어로 표시되고 파싱할 수 없는 값은 원문을 유지한다")
    func entryDateTextFollowsLanguage() throws {
        let viewModel = try makeViewModel()

        #expect(viewModel.entryDateText("2026-01-15") == "1월 15일")

        viewModel.applyLanguage(.en)
        #expect(viewModel.entryDateText("2026-01-15") == "Jan 15")
        #expect(viewModel.entryDateText("2026-01") == "2026-01")
    }

    @Test("정렬 칩은 활성 재탭 시 방향을 뒤집고 비활성 탭 시 내림차순으로 시작한다")
    func sortSelectionFollowsChipRules() throws {
        let viewModel = try makeViewModel()

        viewModel.setSort(field: .date)
        #expect(viewModel.sortField == .date)
        #expect(!viewModel.isDescending)

        viewModel.setSort(field: .amount)
        #expect(viewModel.sortField == .amount)
        #expect(viewModel.isDescending)

        viewModel.setSort(field: .amount)
        #expect(viewModel.sortField == .amount)
        #expect(!viewModel.isDescending)

        viewModel.setSort(field: .date)
        #expect(viewModel.sortField == .date)
        #expect(viewModel.isDescending)
    }

    @Test("reload는 수정된 원장으로 상세와 리포트 파생을 함께 갱신한다")
    func reloadRebuildsReportAndDetailDerivations() async throws {
        let loader = MutableMonthReportLoader()
        let firstID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000000"))
        let secondID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000000"))
        loader.transactions = [makeTransaction(clientEntryID: firstID, amount: 100)]
        let viewModel = try makeViewModel(loadTransactions: loader.load)
        await viewModel.reload()

        #expect(viewModel.summary.expense == 100)
        #expect(viewModel.entryRows(categoryID: 10).map(\.amount) == [100])

        loader.transactions = [
            makeTransaction(clientEntryID: firstID, amount: 250),
            makeTransaction(clientEntryID: secondID, amount: 50, transactionDate: "2026-01-16")
        ]
        await viewModel.reload()

        #expect(viewModel.summary.expense == 300)
        #expect(viewModel.expenseCategoryItems.map(\.amount) == [300])
        #expect(viewModel.entryRows(categoryID: 10).map(\.amount) == [50, 250])
    }

    @Test(arguments: [SelectableCurrency.krw, .usd])
    func reportSummaryExactlyMatchesHomeSummary(baseCurrency: SelectableCurrency) async throws {
        let transactions = currencyFixture
        let home = try makeMainViewModel(
            baseCurrency: baseCurrency,
            loadTransactions: { _ in transactions }
        )
        let report = try makeViewModel(
            baseCurrency: baseCurrency,
            loadTransactions: { _ in transactions }
        )

        await home.load()
        await report.reload()

        #expect(report.summary.expense > 0)
        #expect(report.summary == home.summary)
        #expect(report.summaryItems == home.summaryItems)
    }

    @Test("start의 baseCurrency 인자는 재진입 집계 통화를 바꾼다")
    func startAppliesBaseCurrencyArgument() async throws {
        let transactions = [
            makeTransaction(
                amount: 1400,
                currencyCode: "KRW",
                transactionDate: "2026-07-15"
            )
        ]
        let viewModel = try makeViewModel(loadTransactions: { _ in transactions })
        await viewModel.reload()
        #expect(viewModel.summary.expense == 1400)

        viewModel.start(
            month: MainMonth(year: 2026, month: 7),
            language: .ko,
            baseCurrency: .usd,
            revision: 0
        )
        await waitUntil { !viewModel.isLoading }

        #expect(viewModel.baseCurrency == .usd)
        #expect(viewModel.summary.expense == 1)
    }

    @Test("start가 seed한 revision과 같으면 observer catch-up은 재로드하지 않는다")
    func seededRevisionMakesObserverCatchUpNoOp() async throws {
        let loader = MutableMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load)
        viewModel.start(
            month: MainMonth(year: 2026, month: 1),
            language: .ko,
            baseCurrency: .krw,
            revision: 7
        )
        await waitUntil { !viewModel.isLoading }
        #expect(loader.loadCount == 1)
        let finishedEvents = AsyncStream<Void> { $0.finish() }

        await viewModel.observeLedgerChanges(finishedEvents, revision: { 7 })

        #expect(loader.loadCount == 1)
    }

    @Test("증가한 원장 revision은 한 번 재로드하고 같은 revision 재이벤트는 무시한다")
    func increasedLedgerRevisionReloadsOnceAndRepeatedRevisionIsNoOp() async throws {
        let loader = MutableMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load)
        viewModel.start(
            month: MainMonth(year: 2026, month: 1),
            language: .ko,
            baseCurrency: .krw,
            revision: 7
        )
        await waitUntil { !viewModel.isLoading }
        #expect(loader.loadCount == 1)

        var revision = 7
        var revisionReadCount = 0
        let (events, continuation) = AsyncStream<Void>.makeStream()
        let observer = Task {
            await viewModel.observeLedgerChanges(events) {
                revisionReadCount += 1
                return revision
            }
        }
        await waitUntil { revisionReadCount == 1 }

        revision = 8
        continuation.yield()
        await waitUntil { loader.loadCount == 2 && revisionReadCount == 2 }

        continuation.yield()
        await waitUntil { revisionReadCount == 3 }
        #expect(loader.loadCount == 2)

        continuation.finish()
        await observer.value
    }

    @Test("환산이 전부 실패한 총합 0 달은 빈 상태와 경고로 수렴한다")
    func fullyUnconvertedZeroTotalMonthConvergesToEmptyState() async throws {
        let seedData = SeedData(
            exchangeRates: [],
            expenseCategories: addExpenseExpenseCategories(),
            incomeCategories: addExpenseIncomeCategories(),
            assets: addExpenseAssets()
        )
        let transactions = [makeTransaction(amount: 1400, currencyCode: "KRW")]
        let viewModel = try makeViewModel(
            seedData: seedData,
            baseCurrency: .usd,
            loadTransactions: { _ in transactions }
        )

        await viewModel.reload()

        #expect(viewModel.summary == .empty)
        #expect(viewModel.expenseCategoryItems.isEmpty)
        #expect(viewModel.incomeCategoryItems.isEmpty)
        #expect(viewModel.categoryItems.isEmpty)
        #expect(viewModel.donutSlices.isEmpty)
        #expect(viewModel.conversionWarningText != nil)
        #expect(!viewModel.isLoading)
    }
}

private extension MonthReportViewModelTests {
    var currencyFixture: [LocalTransaction] {
        [
            makeTransaction(
                amount: 14000,
                currencyCode: "KRW",
                transactionType: .expense,
                transactionDate: "2026-07-15"
            ),
            makeTransaction(
                amount: 10,
                currencyCode: "USD",
                categoryID: 11,
                transactionType: .expense,
                transactionDate: "2026-07-15",
                krwAmount: 14000
            ),
            makeTransaction(
                amount: 28000,
                currencyCode: "KRW",
                categoryID: 30,
                transactionType: .income,
                transactionDate: "2026-07-15"
            )
        ]
    }

    func makeViewModel(
        seedData: SeedData = addExpenseSeedData(),
        baseCurrency: SelectableCurrency = .krw,
        loadTransactions: ((LedgerMonth) async throws -> [LocalTransaction])? = nil
    ) throws -> MonthReportViewModel {
        let rateProvider = RateProvider(seedData: seedData)
        return try MonthReportViewModel(
            transactionRepository: TransactionRepository(database: AppDatabase.inMemory()),
            catalogProvider: CatalogProvider(seedData: seedData),
            customCategoryStore: makeCustomCategoryStore(),
            rateProvider: rateProvider,
            baseRateResolver: BaseRateResolver(
                cache: FakeExchangeRateCache(),
                seedRateProvider: rateProvider
            ),
            baseCurrency: baseCurrency,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: loadTransactions
        )
    }

    func makeMainViewModel(
        baseCurrency: SelectableCurrency,
        loadTransactions: @escaping (LedgerMonth) async throws -> [LocalTransaction]
    ) throws -> MainViewModel {
        let seedData = addExpenseSeedData()
        let rateProvider = RateProvider(seedData: seedData)
        return try MainViewModel(
            transactionRepository: TransactionRepository(database: AppDatabase.inMemory()),
            catalogProvider: CatalogProvider(seedData: seedData),
            customCategoryStore: makeCustomCategoryStore(),
            rateProvider: rateProvider,
            baseRateResolver: BaseRateResolver(
                cache: FakeExchangeRateCache(),
                seedRateProvider: rateProvider
            ),
            baseCurrency: baseCurrency,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: loadTransactions,
            pauseForMonthTransition: {},
            prefetchesNeighborMonths: false
        )
    }

    func makeCustomCategoryStore() throws -> CustomCategoryStore {
        try CustomCategoryStore(
            service: CustomCategoryService(),
            cache: CustomCategoryCacheRepository(database: AppDatabase.inMemory()),
            authProvider: FakeAuthService()
        )
    }

    func makeTransaction(
        clientEntryID: UUID = UUID(),
        amount: Decimal,
        currencyCode: String = "KRW",
        categoryID: Int = 10,
        transactionType: LocalTransaction.TransactionType = .expense,
        transactionDate: String = "2026-01-15",
        memo: String? = nil,
        krwAmount: Decimal? = nil
    ) -> LocalTransaction {
        LocalTransaction(
            clientEntryID: clientEntryID,
            amount: amount,
            currencyCode: currencyCode,
            categoryID: categoryID,
            assetID: 20,
            transactionType: transactionType,
            transactionDate: transactionDate,
            memo: memo,
            krwAmount: krwAmount
        )
    }
}

private enum MonthReportViewModelTestError: LocalizedError {
    case loadFailure

    var errorDescription: String? {
        "load failure"
    }
}

@MainActor
private final class MutableMonthReportLoader {
    var transactions: [LocalTransaction] = []
    var error: Error?
    private(set) var loadCount = 0

    func load(month _: LedgerMonth) async throws -> [LocalTransaction] {
        loadCount += 1
        if let error {
            throw error
        }
        return transactions
    }
}

@MainActor
private final class DeferredMonthReportLoader {
    private struct Request {
        let month: LedgerMonth
        let continuation: CheckedContinuation<[LocalTransaction], Error>
    }

    private var requests: [Request] = []
    private var requestCount = 0
    private struct CountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private static var waiterTimeoutNanoseconds: UInt64 {
        10_000_000_000
    }

    private var waiters: [Int: CountWaiter] = [:]
    private var nextWaiterID = 0

    func load(month: LedgerMonth) async throws -> [LocalTransaction] {
        try await withCheckedThrowingContinuation { continuation in
            requestCount += 1
            requests.append(Request(month: month, continuation: continuation))
            resumeSatisfiedWaiters()
        }
    }

    func waitForRequestCount(_ count: Int) async {
        guard requestCount < count else {
            return
        }

        let waiterID = nextWaiterID
        nextWaiterID += 1
        let watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.waiterTimeoutNanoseconds)
            self?.failWaiter(id: waiterID)
        }
        defer { watchdog.cancel() }

        await withCheckedContinuation { continuation in
            waiters[waiterID] = CountWaiter(
                expectedCount: count,
                continuation: continuation
            )
        }
    }

    func resumeFirst(month: LedgerMonth, returning transactions: [LocalTransaction]) {
        guard let index = requests.firstIndex(where: { $0.month == month }) else {
            Issue.record("대기 중인 \(month.year)-\(month.month) 요청이 없습니다.")
            return
        }
        requests.remove(at: index).continuation.resume(returning: transactions)
    }

    func resumeFirst(month: LedgerMonth, throwing error: Error) {
        guard let index = requests.firstIndex(where: { $0.month == month }) else {
            Issue.record("대기 중인 \(month.year)-\(month.month) 요청이 없습니다.")
            return
        }
        requests.remove(at: index).continuation.resume(throwing: error)
    }

    func resumeLast(month: LedgerMonth, returning transactions: [LocalTransaction]) {
        guard let index = requests.lastIndex(where: { $0.month == month }) else {
            Issue.record("대기 중인 \(month.year)-\(month.month) 요청이 없습니다.")
            return
        }
        requests.remove(at: index).continuation.resume(returning: transactions)
    }

    private func resumeSatisfiedWaiters() {
        for (id, waiter) in waiters where requestCount >= waiter.expectedCount {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    private func failWaiter(id: Int) {
        guard let waiter = waiters.removeValue(forKey: id) else {
            return
        }
        Issue.record("waitForRequestCount(\(waiter.expectedCount)) 미충족: 현재 \(requestCount)건")
        waiter.continuation.resume()
    }
}
