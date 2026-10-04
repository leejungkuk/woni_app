//
//  MonthReportViewModel.swift
//  woni_app
//

import Foundation
import Observation

struct MonthReportDisplaySnapshot {
    let baseCurrency: SelectableCurrency
    let baseTTSByDate: [String: Decimal]
    let transactions: [LocalTransaction]
    let expenseCategoryItems: [ReportCategoryItem]
    let incomeCategoryItems: [ReportCategoryItem]
    let categoryDisplayNames: [Int: String]
    let summary: MainMonthlySummary
    let hasUnconvertedTransactions: Bool
    /// 그 달 값이 아직 없는 자리표시. 거래 0건으로 읽은 달과 구분한다 — 칸의 "읽는 중"이 이것으로 정해진다.
    var isPlaceholder = false

    static func empty(baseCurrency: SelectableCurrency) -> MonthReportDisplaySnapshot {
        MonthReportDisplaySnapshot(
            baseCurrency: baseCurrency,
            baseTTSByDate: [:],
            transactions: [],
            expenseCategoryItems: [],
            incomeCategoryItems: [],
            categoryDisplayNames: [:],
            summary: .empty,
            hasUnconvertedTransactions: false,
            isPlaceholder: true
        )
    }
}

@Observable
@MainActor
final class MonthReportViewModel {
    private struct LoadRequest {
        let generation: Int
        let month: MainMonth
        let baseCurrency: SelectableCurrency
    }

    private(set) var selectedMonth: MainMonth
    private(set) var selectedKind: MainSummaryItem.Kind = .expense
    private(set) var sortField: ReportSortField = .date
    private(set) var isDescending = true
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// 직전 달 이동의 방향. 버튼·피커 이동을 그 방향으로 미끄러뜨린다.
    private(set) var monthChangeDirection: MainMonthChangeDirection = .next
    /// 직전에 떠난 달의 칸. 미끄러지는 동안 떠나는 쪽에 그린다 — 피커로 먼 달에 뛰어도 실제로 보던 달이다.
    private(set) var outgoingPage: MonthReportPage?

    let currentDate: Date
    let calendar: Calendar
    let assetsByID: [Int: Asset]
    private(set) var language: AppLanguage

    private let customCategoryStore: CustomCategoryStore
    private let rateProvider: RateProvider
    let baseRateResolver: BaseRateResolver
    private let categoriesByID: [Int: Category]
    let loadTransactions: (LedgerMonth) async throws -> [LocalTransaction]
    /// 옆 달 미리 읽기 사용 여부. 끄는 쪽은 테스트뿐이다 — 로더 요청 수를 세는 테스트가 배경 읽기에 흔들리면 안 된다.
    let prefetchesNeighborMonths: Bool
    private(set) var requestedBaseCurrency: SelectableCurrency
    private(set) var displaySnapshot: MonthReportDisplaySnapshot
    private var loadGeneration = 0
    private var lastAppliedRevision = 0
    /// 읽어 둔 달의 원자료(이번 달 ±1). 늘 요청 기준통화로 읽은 것이다. 쓰는 곳은 `+Paging` 이다.
    var monthCache: [MainMonth: MainMonthData] = [:]
    /// 캐시를 비울 때마다 올린다 — 그 전에 시작한 미리 읽기 결과를 버리는 기준이다.
    var monthCacheGeneration = 0

    var baseCurrency: SelectableCurrency {
        displaySnapshot.baseCurrency
    }

    var expenseCategoryItems: [ReportCategoryItem] {
        displaySnapshot.expenseCategoryItems
    }

    var incomeCategoryItems: [ReportCategoryItem] {
        displaySnapshot.incomeCategoryItems
    }

    var categoryItems: [ReportCategoryItem] {
        page(offset: 0).categoryItems
    }

    var summary: MainMonthlySummary {
        displaySnapshot.summary
    }

    var selectedTotal: Decimal {
        page(offset: 0).selectedTotal
    }

    var donutSlices: [ReportDonutSlice] {
        page(offset: 0).donutSlices
    }

    var summaryItems: [MainSummaryItem] {
        page(offset: 0).summaryItems
    }

    var monthTitle: String {
        WoniDateFormat.monthTitle(
            year: selectedMonth.year,
            month: selectedMonth.month,
            language: language,
            calendar: calendar
        )
    }

    var hasUnconvertedTransactions: Bool {
        displaySnapshot.hasUnconvertedTransactions
    }

    var conversionWarningText: String? {
        page(offset: 0).conversionWarningText
    }

    init(
        transactionRepository: TransactionRepository,
        catalogProvider: CatalogProvider,
        customCategoryStore: CustomCategoryStore,
        rateProvider: RateProvider,
        baseRateResolver: BaseRateResolver,
        baseCurrency: SelectableCurrency,
        currentDate: Date = Date(),
        calendar: Calendar = .woniSeoul,
        language: AppLanguage = AppLanguage.resolved(from: .current),
        loadTransactions: ((LedgerMonth) async throws -> [LocalTransaction])? = nil,
        prefetchesNeighborMonths: Bool = true
    ) {
        self.customCategoryStore = customCategoryStore
        self.rateProvider = rateProvider
        self.baseRateResolver = baseRateResolver
        self.currentDate = currentDate
        self.calendar = calendar
        self.language = language
        self.loadTransactions = loadTransactions ?? { month in
            try await transactionRepository.all(month: month)
        }
        self.prefetchesNeighborMonths = prefetchesNeighborMonths
        selectedMonth = MainMonth(date: currentDate, calendar: calendar)
        requestedBaseCurrency = baseCurrency
        displaySnapshot = .empty(baseCurrency: baseCurrency)

        let categories = catalogProvider.categories(for: .expense)
            + catalogProvider.categories(for: .income)
        categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        assetsByID = Dictionary(uniqueKeysWithValues: catalogProvider.assets.map { ($0.id, $0) })
    }

    func start(
        month: MainMonth,
        language: AppLanguage,
        baseCurrency: SelectableCurrency,
        revision: Int
    ) {
        selectedMonth = month
        selectedKind = .expense
        resetSort()
        self.language = language
        requestedBaseCurrency = baseCurrency
        lastAppliedRevision = revision
        displaySnapshot = .empty(baseCurrency: baseCurrency)
        errorMessage = nil
        monthChangeDirection = .next
        outgoingPage = nil
        invalidateMonthCache()
        launchLoad()
    }

    func setMonth(_ month: MainMonth) {
        guard month != selectedMonth,
              month.date(day: 1, calendar: calendar) != nil
        else {
            return
        }

        monthChangeDirection = (month.year, month.month)
            > (selectedMonth.year, selectedMonth.month) ? .next : .previous
        outgoingPage = page(offset: 0)
        selectedMonth = month
        // 읽어 둔 달이면 그 자리에서 채운다 — 다시 읽는 동안에도 "읽는 중"으로 바꾸지 않는다.
        displaySnapshot = cachedSnapshot(for: month) ?? .empty(baseCurrency: requestedBaseCurrency)
        errorMessage = nil
        launchLoad()
    }

    func setKind(_ kind: MainSummaryItem.Kind) {
        selectedKind = kind
    }

    /// 카테고리 상세 진입 시점의 기본 정렬. 리포트 진입(`start`)과 상세 진입이 같은 정의를 쓴다.
    func resetSort() {
        sortField = .date
        isDescending = true
    }

    func setSort(field: ReportSortField) {
        if sortField == field {
            isDescending.toggle()
        } else {
            sortField = field
            isDescending = true
        }
    }

    func reload() async {
        invalidateMonthCache()
        _ = await loadCurrentSelection()
    }

    func observeLedgerChanges(
        _ events: AsyncStream<Void>,
        revision: @escaping () -> Int
    ) async {
        guard !Task.isCancelled else {
            return
        }
        await refreshIfBehind(revision: revision)
        for await _ in events {
            guard !Task.isCancelled else {
                return
            }
            await refreshIfBehind(revision: revision)
        }
    }

    func applyLanguage(_ newLanguage: AppLanguage) {
        guard language != newLanguage else {
            return
        }

        language = newLanguage
        rebuildDisplay()
    }

    /// 통계 탭은 늘 살아 있어 `start` 로 다시 들어오지 않는다 — 보던 달과 탭은 두고 새 통화로만 다시 집계한다.
    /// 요청 통화를 바로 기록하므로 빠르게 여러 번 바꿔도 로드가 끝나는 순서와 무관하게 마지막 통화가 남는다.
    func requestBaseCurrency(_ newBaseCurrency: SelectableCurrency) {
        guard requestedBaseCurrency != newBaseCurrency else {
            return
        }

        requestedBaseCurrency = newBaseCurrency
        invalidateMonthCache()
        launchLoad()
    }

    func transaction(clientEntryID: UUID) -> LocalTransaction? {
        displaySnapshot.transactions.first { $0.clientEntryID == clientEntryID }
    }

    func entryRows(categoryID: Int) -> [ReportEntryRow] {
        MonthReportAggregator.entryRows(
            transactions: displaySnapshot.transactions,
            categoryID: categoryID,
            field: sortField,
            isDescending: isDescending,
            baseAmount: { [self] transaction in
                baseAmount(
                    for: transaction,
                    baseCurrency: displaySnapshot.baseCurrency,
                    baseTTSByDate: displaySnapshot.baseTTSByDate
                )
            },
            memo: { transaction in
                let trimmed = transaction.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    /// 상세 행의 날짜 표시. 문자열 파싱은 홈 정본(`MainViewModel.date(from:calendar:)`)을 그대로 쓴다 —
    /// 규칙을 새로 만들면 같은 내역이 화면마다 다른 날짜로 보인다.
    func entryDateText(_ transactionDate: String) -> String {
        guard let date = MainViewModel.date(from: transactionDate, calendar: calendar) else {
            return transactionDate
        }

        return WoniDateFormat.monthDayWeekday(date, language: language, calendar: calendar)
    }

    func categoryDisplayName(categoryID: Int) -> String {
        page(offset: 0).categoryDisplayName(categoryID: categoryID)
    }

    /// 그 달 내역에서 구한 표시명. 내역이 없으면 nil — 상세 머리가 보관한 이름을 남길지 이것으로 판단한다.
    func resolvedCategoryDisplayName(categoryID: Int) -> String? {
        displaySnapshot.categoryDisplayNames[categoryID]
    }

    func categoryTotal(categoryID: Int) -> Decimal {
        expenseCategoryItems.first { $0.categoryID == categoryID }?.amount
            ?? incomeCategoryItems.first { $0.categoryID == categoryID }?.amount
            ?? 0
    }

    func formatBaseAmount(_ amount: Decimal) -> String {
        page(offset: 0).formatAmount(amount)
    }

    func exchangeInfoText(for transaction: LocalTransaction) -> String? {
        BaseAmountCalculator.exchangeInfo(
            for: transaction,
            baseCurrency: displaySnapshot.baseCurrency,
            baseTTSByDate: displaySnapshot.baseTTSByDate,
            rateProvider: rateProvider
        )
    }
}

private extension MonthReportViewModel {
    func launchLoad() {
        let request = beginLoad()
        Task { await performLoad(request) }
    }

    func loadCurrentSelection() async -> Bool {
        let request = beginLoad()
        return await performLoad(request)
    }

    private func beginLoad() -> LoadRequest {
        loadGeneration += 1
        isLoading = true
        errorMessage = nil
        return LoadRequest(
            generation: loadGeneration,
            month: selectedMonth,
            baseCurrency: requestedBaseCurrency
        )
    }

    private func performLoad(_ request: LoadRequest) async -> Bool {
        do {
            let transactions = try await loadTransactions(request.month.ledgerMonth)
            let baseTTSByDate = await baseRateResolver.ttsByDate(
                for: request.baseCurrency,
                dates: Set(transactions.map(\.transactionDate))
            )
            guard request.generation == loadGeneration && request.month == selectedMonth else {
                return false
            }

            displaySnapshot = makeDisplaySnapshot(
                baseCurrency: request.baseCurrency,
                baseTTSByDate: baseTTSByDate,
                transactions: transactions
            )
            cacheLoadedMonth(
                request.month,
                data: MainMonthData(transactions: transactions, baseTTSByDate: baseTTSByDate)
            )
            if request.generation == loadGeneration {
                isLoading = false
            }
            return true
        } catch {
            guard request.generation == loadGeneration && request.month == selectedMonth else {
                return false
            }

            displaySnapshot = .empty(baseCurrency: request.baseCurrency)
            if request.generation == loadGeneration {
                errorMessage = error.localizedDescription
                isLoading = false
            }
            return false
        }
    }

    func refreshIfBehind(revision: () -> Int) async {
        let targetRevision = revision()
        guard targetRevision > lastAppliedRevision else {
            return
        }

        invalidateMonthCache()
        guard await loadCurrentSelection() else {
            return
        }
        lastAppliedRevision = targetRevision
    }

    func rebuildDisplay() {
        // 자리표시는 다시 집계하지 않는다 — 집계하면 읽기 전인 달이 "읽음"(0건)으로 바뀐다.
        guard !displaySnapshot.isPlaceholder else {
            return
        }

        displaySnapshot = makeDisplaySnapshot(
            baseCurrency: displaySnapshot.baseCurrency,
            baseTTSByDate: displaySnapshot.baseTTSByDate,
            transactions: displaySnapshot.transactions
        )
    }
}

extension MonthReportViewModel {
    func makeDisplaySnapshot(
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal],
        transactions: [LocalTransaction]
    ) -> MonthReportDisplaySnapshot {
        let convert: (LocalTransaction) -> Decimal? = { [self] transaction in
            baseAmount(
                for: transaction,
                baseCurrency: baseCurrency,
                baseTTSByDate: baseTTSByDate
            )
        }
        let expenseItems = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .expense,
            baseAmount: convert
        )
        let incomeItems = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .income,
            baseAmount: convert
        )
        let expense = expenseItems.reduce(Decimal(0)) { $0 + $1.amount }
        let income = incomeItems.reduce(Decimal(0)) { $0 + $1.amount }
        let names = categoryDisplayNames(
            items: expenseItems + incomeItems,
            transactions: transactions
        )

        return MonthReportDisplaySnapshot(
            baseCurrency: baseCurrency,
            baseTTSByDate: baseTTSByDate,
            transactions: transactions,
            expenseCategoryItems: expenseItems,
            incomeCategoryItems: incomeItems,
            categoryDisplayNames: names,
            summary: MainMonthlySummary(
                income: income,
                expense: expense,
                total: income - expense
            ),
            hasUnconvertedTransactions: transactions.contains { convert($0) == nil }
        )
    }
}

private extension MonthReportViewModel {
    func categoryDisplayNames(
        items: [ReportCategoryItem],
        transactions: [LocalTransaction]
    ) -> [Int: String] {
        var names: [Int: String] = [:]
        for item in items {
            let representative = transactions.first {
                $0.categoryID == item.categoryID
                    && $0.categorySnapshot == item.categorySnapshot
            } ?? transactions.first { $0.categoryID == item.categoryID }
            guard let representative else {
                continue
            }
            names[item.categoryID] = CategoryDisplayNameResolver.displayName(
                for: representative,
                categoriesByID: categoriesByID,
                customCategoryStore: customCategoryStore,
                language: language
            )
        }
        return names
    }

    func baseAmount(
        for transaction: LocalTransaction,
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal]
    ) -> Decimal? {
        BaseAmountCalculator.baseAmount(
            for: transaction,
            baseCurrency: baseCurrency,
            baseTTSByDate: baseTTSByDate,
            rateProvider: rateProvider
        )
    }
}

private extension Calendar {
    static var woniSeoul: Calendar {
        guard let timeZone = TimeZone(identifier: "Asia/Seoul") else {
            preconditionFailure("Asia/Seoul time zone is unavailable")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 1
        return calendar
    }
}
