//
//  MonthReportViewModel.swift
//  woni_app
//

import Foundation
import Observation

private struct MonthReportDisplaySnapshot {
    let baseCurrency: SelectableCurrency
    let baseTTSByDate: [String: Decimal]
    let transactions: [LocalTransaction]
    let expenseCategoryItems: [ReportCategoryItem]
    let incomeCategoryItems: [ReportCategoryItem]
    let categoryDisplayNames: [Int: String]
    let summary: MainMonthlySummary
    let hasUnconvertedTransactions: Bool

    static func empty(baseCurrency: SelectableCurrency) -> MonthReportDisplaySnapshot {
        MonthReportDisplaySnapshot(
            baseCurrency: baseCurrency,
            baseTTSByDate: [:],
            transactions: [],
            expenseCategoryItems: [],
            incomeCategoryItems: [],
            categoryDisplayNames: [:],
            summary: .empty,
            hasUnconvertedTransactions: false
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

    let currentDate: Date
    let calendar: Calendar
    private(set) var language: AppLanguage

    private let customCategoryStore: CustomCategoryStore
    private let rateProvider: RateProvider
    private let baseRateResolver: BaseRateResolver
    private let categoriesByID: [Int: Category]
    private let loadTransactions: (LedgerMonth) async throws -> [LocalTransaction]
    private var requestedBaseCurrency: SelectableCurrency
    private var displaySnapshot: MonthReportDisplaySnapshot
    private var loadGeneration = 0
    private var lastAppliedRevision = 0

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
        switch selectedKind {
        case .expense:
            expenseCategoryItems
        case .income:
            incomeCategoryItems
        case .total:
            []
        }
    }

    var summary: MainMonthlySummary {
        displaySnapshot.summary
    }

    var selectedTotal: Decimal {
        switch selectedKind {
        case .expense:
            summary.expense
        case .income:
            summary.income
        case .total:
            summary.total
        }
    }

    var donutSlices: [ReportDonutSlice] {
        MonthReportAggregator.donutSlices(items: categoryItems, total: selectedTotal)
    }

    var summaryItems: [MainSummaryItem] {
        [
            MainSummaryItem(
                kind: .expense,
                title: WoniStrings.expense(language),
                amountText: formatBaseAmount(summary.expense),
                tone: .expense
            ),
            MainSummaryItem(
                kind: .income,
                title: WoniStrings.income(language),
                amountText: formatBaseAmount(summary.income),
                tone: .income
            ),
            MainSummaryItem(
                kind: .total,
                title: WoniStrings.total(language),
                amountText: formatBaseAmount(summary.total),
                tone: summary.totalTone
            )
        ]
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
        guard hasUnconvertedTransactions else {
            return nil
        }
        return WoniStrings.conversionWarning(language)
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
        loadTransactions: ((LedgerMonth) async throws -> [LocalTransaction])? = nil
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
        selectedMonth = MainMonth(date: currentDate, calendar: calendar)
        requestedBaseCurrency = baseCurrency
        displaySnapshot = .empty(baseCurrency: baseCurrency)

        let categories = catalogProvider.categories(for: .expense)
            + catalogProvider.categories(for: .income)
        categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    func start(
        month: MainMonth,
        language: AppLanguage,
        baseCurrency: SelectableCurrency,
        revision: Int
    ) {
        selectedMonth = month
        selectedKind = .expense
        sortField = .date
        isDescending = true
        self.language = language
        requestedBaseCurrency = baseCurrency
        lastAppliedRevision = revision
        displaySnapshot = .empty(baseCurrency: baseCurrency)
        errorMessage = nil
        launchLoad()
    }

    func setMonth(_ month: MainMonth) {
        guard month != selectedMonth,
              month.date(day: 1, calendar: calendar) != nil
        else {
            return
        }

        selectedMonth = month
        displaySnapshot = .empty(baseCurrency: requestedBaseCurrency)
        errorMessage = nil
        launchLoad()
    }

    func setKind(_ kind: MainSummaryItem.Kind) {
        selectedKind = kind
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

        return WoniDateFormat.monthDay(date, language: language, calendar: calendar)
    }

    func categoryDisplayName(categoryID: Int) -> String {
        displaySnapshot.categoryDisplayNames[categoryID]
            ?? WoniStrings.uncategorized(language)
    }

    func categoryTotal(categoryID: Int) -> Decimal {
        expenseCategoryItems.first { $0.categoryID == categoryID }?.amount
            ?? incomeCategoryItems.first { $0.categoryID == categoryID }?.amount
            ?? 0
    }

    func formatBaseAmount(_ amount: Decimal) -> String {
        CurrencyFormat.string(amount, currencyCode: displaySnapshot.baseCurrency.rawValue)
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

        guard await loadCurrentSelection() else {
            return
        }
        lastAppliedRevision = targetRevision
    }

    func rebuildDisplay() {
        displaySnapshot = makeDisplaySnapshot(
            baseCurrency: displaySnapshot.baseCurrency,
            baseTTSByDate: displaySnapshot.baseTTSByDate,
            transactions: displaySnapshot.transactions
        )
    }

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
