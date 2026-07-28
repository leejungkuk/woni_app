import Foundation
import Observation

struct MainDisplaySnapshot {
    let baseCurrency: SelectableCurrency
    let baseTTSByDate: [String: Decimal]
    let transactions: [LocalTransaction]
    let summary: MainMonthlySummary
    let calendarDays: [MainCalendarDay]
    let historyRows: [MainHistoryRow]
    let hasUnconvertedTransactions: Bool
}

@Observable
@MainActor
final class MainViewModel {
    var selectedMonth: MainMonth
    var selectedDateString: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let transactionRepository: TransactionRepository
    let rateProvider: RateProvider
    private let baseRateResolver: BaseRateResolver
    let currentDate: Date
    let calendar: Calendar
    private(set) var language: AppLanguage
    let categoriesByID: [Int: Category]
    let assetsByID: [Int: Asset]
    private let loadTransactions: (LedgerMonth) async throws -> [LocalTransaction]
    private var displaySnapshot: MainDisplaySnapshot
    private var requestedBaseCurrency: SelectableCurrency
    private var loadGeneration = 0
    private var lastAppliedRevision = 0

    var baseCurrency: SelectableCurrency {
        displaySnapshot.baseCurrency
    }

    var summary: MainMonthlySummary {
        displaySnapshot.summary
    }

    var calendarDays: [MainCalendarDay] {
        displaySnapshot.calendarDays
    }

    var historyRows: [MainHistoryRow] {
        displaySnapshot.historyRows
    }

    var hasUnconvertedTransactions: Bool {
        displaySnapshot.hasUnconvertedTransactions
    }

    var monthTitle: String {
        WoniDateFormat.monthTitle(
            year: selectedMonth.year,
            month: selectedMonth.month,
            language: language,
            calendar: calendar
        )
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

    var defaultEntryDate: Date {
        selectedDateString.flatMap { Self.date(from: $0, calendar: calendar) } ?? currentDate
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
        rateProvider: RateProvider,
        baseRateResolver: BaseRateResolver,
        baseCurrency: SelectableCurrency,
        currentDate: Date = Date(),
        calendar: Calendar = .woniSeoul,
        language: AppLanguage = AppLanguage.resolved(from: .current),
        loadTransactions: ((LedgerMonth) async throws -> [LocalTransaction])? = nil
    ) {
        self.transactionRepository = transactionRepository
        self.rateProvider = rateProvider
        self.baseRateResolver = baseRateResolver
        self.currentDate = currentDate
        self.calendar = calendar
        self.language = language
        self.loadTransactions = loadTransactions ?? { month in
            try await transactionRepository.all(month: month)
        }
        selectedMonth = MainMonth(date: currentDate, calendar: calendar)
        selectedDateString = Self.dateString(from: currentDate, calendar: calendar)
        requestedBaseCurrency = baseCurrency
        displaySnapshot = MainDisplaySnapshot(
            baseCurrency: baseCurrency,
            baseTTSByDate: [:],
            transactions: [],
            summary: .empty,
            calendarDays: [],
            historyRows: [],
            hasUnconvertedTransactions: false
        )

        let categories = catalogProvider.categories(for: .expense) + catalogProvider.categories(for: .income)
        categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        assetsByID = Dictionary(uniqueKeysWithValues: catalogProvider.assets.map { ($0.id, $0) })
    }

    /// 반환값: **이 호출이 실제로 현재 월 데이터를 적용한 경우에만** `true`. 더 새 load에 의해
    /// superseded되었거나(자기 결과 미적용) 로드가 실패해 오류 상태로 남은 경우 `false`.
    /// `refreshIfBehind`는 자기 reload가 실제로 적용됐을 때만 revision을 기록한다 — superseding load가
    /// 실패해도 변경을 삼키지 않는다(다음 신호가 재시도). superseded를 `true`로 보면 겹친 load에서
    /// 미적용 revision을 소비해버릴 수 있어 `false`로 둔다(superseding 성공 시 최악은 양성 중복 reload).
    @discardableResult
    func load() async -> Bool {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedMonth = selectedMonth
        let requestedBase = requestedBaseCurrency
        isLoading = true
        errorMessage = nil

        var didApply = false
        do {
            let loadedTransactions = try await loadTransactions(requestedMonth.ledgerMonth)
            guard shouldApplyLoad(
                generation: generation,
                requestedMonth: requestedMonth,
                requestedBase: requestedBase
            ) else {
                finishLoadIfCurrent(generation: generation)
                return false
            }

            let transactionDates = Set(loadedTransactions.map(\.transactionDate))
            let resolvedBaseRates = await baseRateResolver.ttsByDate(
                for: requestedBase,
                dates: transactionDates
            )
            guard shouldApplyLoad(
                generation: generation,
                requestedMonth: requestedMonth,
                requestedBase: requestedBase
            ) else {
                finishLoadIfCurrent(generation: generation)
                return false
            }

            displaySnapshot = makeDisplaySnapshot(
                baseCurrency: requestedBase,
                baseTTSByDate: resolvedBaseRates,
                transactions: loadedTransactions
            )
            didApply = true
        } catch {
            guard shouldApplyLoad(
                generation: generation,
                requestedMonth: requestedMonth,
                requestedBase: requestedBase
            ) else {
                finishLoadIfCurrent(generation: generation)
                return false
            }

            displaySnapshot = makeDisplaySnapshot(
                baseCurrency: requestedBase,
                baseTTSByDate: [:],
                transactions: []
            )
            errorMessage = error.localizedDescription
        }
        finishLoadIfCurrent(generation: generation)
        return didApply
    }

    @discardableResult
    func reload() async -> Bool {
        await load()
    }

    @discardableResult
    func applyBaseCurrency(_ newBaseCurrency: SelectableCurrency) async -> Bool {
        guard requestedBaseCurrency != newBaseCurrency else {
            return false
        }

        requestedBaseCurrency = newBaseCurrency
        return await reload()
    }

    func transaction(clientEntryID: UUID) -> LocalTransaction? {
        displaySnapshot.transactions.first { $0.clientEntryID == clientEntryID }
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

    func selectDay(_ day: MainCalendarDay) {
        guard let dateString = day.dateString else {
            return
        }

        selectedDateString = dateString
        rebuildDisplay()
    }

    func moveMonth(by value: Int) async {
        let nextMonth = selectedMonth.addingMonths(value, calendar: calendar)
        await setMonth(year: nextMonth.year, month: nextMonth.month)
    }

    func setMonth(year: Int, month: Int) async {
        guard (1 ... 12).contains(month) else {
            return
        }

        let nextMonth = MainMonth(year: year, month: month)
        guard nextMonth.date(day: 1, calendar: calendar) != nil else {
            return
        }

        selectedMonth = nextMonth
        await load()
    }

    func handleSwipe(horizontal: Double, vertical: Double) async {
        let threshold = 40.0
        guard max(abs(horizontal), abs(vertical)) >= threshold else {
            return
        }

        if abs(horizontal) >= abs(vertical) {
            await moveMonth(by: horizontal < 0 ? 1 : -1)
        } else {
            await moveMonth(by: vertical < 0 ? 1 : -1)
        }
    }

    func formatBaseAmount(_ amount: Decimal) -> String {
        CurrencyFormat.string(amount, currencyCode: displaySnapshot.baseCurrency.rawValue)
    }
}

private extension MainViewModel {
    func refreshIfBehind(revision: () -> Int) async {
        let targetRevision = revision()
        guard targetRevision > lastAppliedRevision else {
            return
        }

        // reload가 실제로 데이터를 적용했을 때만 revision을 기록한다. 실패(오류 흡수)나 더 새 load에
        // 의한 supersede로 자기 결과가 미적용이면 남겨, 같은 revision이 다음 이벤트로 오면 재시도한다.
        guard await reload() else {
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

    func shouldApplyLoad(
        generation: Int,
        requestedMonth: MainMonth,
        requestedBase: SelectableCurrency
    ) -> Bool {
        generation == loadGeneration
            && selectedMonth == requestedMonth
            && requestedBaseCurrency == requestedBase
    }

    func finishLoadIfCurrent(generation: Int) {
        if generation == loadGeneration {
            isLoading = false
        }
    }
}

private extension Calendar {
    nonisolated static var woniSeoul: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }
}
