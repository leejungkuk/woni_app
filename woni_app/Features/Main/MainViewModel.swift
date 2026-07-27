import Foundation
import Observation

// swiftlint:disable file_length

private struct MainDisplaySnapshot {
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
    private let rateProvider: RateProvider
    private let baseRateResolver: BaseRateResolver
    private let currentDate: Date
    private let calendar: Calendar
    private var language: AppLanguage
    private let categoriesByID: [Int: Category]
    private let assetsByID: [Int: Asset]
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

    func makeDisplaySnapshot(
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal],
        transactions: [LocalTransaction]
    ) -> MainDisplaySnapshot {
        let dailyResult = dailySummaries(
            from: transactions,
            baseCurrency: baseCurrency,
            baseTTSByDate: baseTTSByDate
        )
        return MainDisplaySnapshot(
            baseCurrency: baseCurrency,
            baseTTSByDate: baseTTSByDate,
            transactions: transactions,
            summary: monthlySummary(from: dailyResult.summaries.values),
            calendarDays: makeCalendarDays(dailySummaries: dailyResult.summaries),
            historyRows: makeHistoryRows(
                transactions: transactions,
                baseCurrency: baseCurrency,
                baseTTSByDate: baseTTSByDate
            ),
            hasUnconvertedTransactions: dailyResult.hasUnconvertedTransactions
        )
    }

    func monthlySummary(from dailySummaries: Dictionary<String, MainDailySummary>.Values) -> MainMonthlySummary {
        let income = dailySummaries.reduce(Decimal(0)) { $0 + $1.income }
        let expense = dailySummaries.reduce(Decimal(0)) { $0 + $1.expense }
        return MainMonthlySummary(income: income, expense: expense, total: income - expense)
    }

    func dailySummaries(
        from transactions: [LocalTransaction],
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal]
    ) -> (summaries: [String: MainDailySummary], hasUnconvertedTransactions: Bool) {
        var summaries: [String: MainDailySummary] = [:]
        var hasUnconvertedTransactions = false
        for transaction in transactions {
            guard let amount = baseAmount(
                for: transaction,
                baseCurrency: baseCurrency,
                baseTTSByDate: baseTTSByDate
            ) else {
                hasUnconvertedTransactions = true
                continue
            }

            var dailySummary = summaries[transaction.transactionDate] ?? MainDailySummary()
            switch transaction.transactionType {
            case .expense:
                dailySummary.expense += amount
            case .income:
                dailySummary.income += amount
            }
            summaries[transaction.transactionDate] = dailySummary
        }
        return (summaries, hasUnconvertedTransactions)
    }

    func makeCalendarDays(dailySummaries: [String: MainDailySummary]) -> [MainCalendarDay] {
        guard let firstDay = selectedMonth.date(day: 1, calendar: calendar),
              let dayRange = calendar.range(of: .day, in: .month, for: firstDay)
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlankCount = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [MainCalendarDay] = (0 ..< leadingBlankCount).map { index in
            MainCalendarDay(
                id: "blank-leading-\(index)",
                day: nil,
                dateString: nil,
                isSelected: false,
                isToday: false,
                income: nil,
                expense: nil
            )
        }

        let todayDateString = Self.dateString(from: currentDate, calendar: calendar)
        for day in dayRange {
            let dateString = Self.dateString(year: selectedMonth.year, month: selectedMonth.month, day: day)
            let dailySummary = dailySummaries[dateString]
            days.append(MainCalendarDay(
                id: dateString,
                day: day,
                dateString: dateString,
                isSelected: dateString == selectedDateString,
                isToday: dateString == todayDateString,
                income: dailySummary?.income.nilIfZero,
                expense: dailySummary?.expense.nilIfZero
            ))
        }

        while !days.count.isMultiple(of: 7) {
            days.append(MainCalendarDay(
                id: "blank-trailing-\(days.count)",
                day: nil,
                dateString: nil,
                isSelected: false,
                isToday: false,
                income: nil,
                expense: nil
            ))
        }

        return days
    }

    func makeHistoryRows(
        transactions: [LocalTransaction],
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal]
    ) -> [MainHistoryRow] {
        guard let selectedDateString else {
            return []
        }

        return transactions
            .filter { $0.transactionDate == selectedDateString }
            .map { transaction in
                let tone = amountTone(for: transaction)
                let baseAmount = baseAmount(
                    for: transaction,
                    baseCurrency: baseCurrency,
                    baseTTSByDate: baseTTSByDate
                )
                let categoryName = categoryDisplayName(id: transaction.categoryID)
                let assetName = assetDisplayName(id: transaction.assetID)
                let title = memoTitle(for: transaction)
                let isForeignCurrency = transaction.currencyCode != baseCurrency.rawValue
                let secondaryAmount = baseAmount != nil && isForeignCurrency
                    ? originalAmountText(for: transaction)
                    : nil

                return MainHistoryRow(
                    id: transaction.clientEntryID,
                    title: title,
                    categoryAssetText: "\(categoryName) · \(assetName)",
                    exchangeInfoText: exchangeInfo(
                        for: transaction,
                        baseCurrency: baseCurrency,
                        baseTTSByDate: baseTTSByDate
                    ),
                    amountText: historyAmountText(
                        for: transaction,
                        baseAmount: baseAmount,
                        baseCurrency: baseCurrency
                    ),
                    secondaryAmountText: secondaryAmount,
                    tone: tone
                )
            }
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

    func historyAmountText(
        for transaction: LocalTransaction,
        baseAmount: Decimal?,
        baseCurrency: SelectableCurrency
    ) -> String {
        if let baseAmount {
            return CurrencyFormat.string(baseAmount, currencyCode: baseCurrency.rawValue)
        }

        if transaction.currencyCode != baseCurrency.rawValue {
            return originalAmountText(for: transaction)
        }

        return CurrencyFormat.string(transaction.amount, currencyCode: baseCurrency.rawValue)
    }

    func originalAmountText(for transaction: LocalTransaction) -> String {
        let amountText = formatOriginalAmount(
            transaction.amount,
            currencyCode: transaction.currencyCode
        )
        return "\(transaction.currencyCode) \(amountText)"
    }

    func formatOriginalAmount(_ amount: Decimal, currencyCode: String) -> String {
        CurrencyFormat.string(amount, currencyCode: currencyCode)
    }

    func baseAmount(
        for transaction: LocalTransaction,
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal]
    ) -> Decimal? {
        if transaction.currencyCode == baseCurrency.rawValue {
            return transaction.amount
        }

        if let krwAmount = transaction.krwAmount {
            return displayValue(
                krwValue: krwAmount,
                baseCurrency: baseCurrency,
                transactionDate: transaction.transactionDate,
                baseTTSByDate: baseTTSByDate
            )
        }

        guard let currency = SelectableCurrency(rawValue: transaction.currencyCode),
              let rate = rateProvider.rate(for: currency, on: transaction.transactionDate),
              let transactionKrwPerUnit = BaseRateMath.krwPerUnit(
                  tts: rate,
                  unit: currency.exchangeUnit
              )
        else {
            return nil
        }

        let roundedKRWValue = NSDecimalNumber(decimal: transaction.amount)
            .multiplying(by: NSDecimalNumber(decimal: transactionKrwPerUnit))
            .decimalValue
            .roundedToTwoFractionDigits
        return displayValue(
            krwValue: roundedKRWValue,
            baseCurrency: baseCurrency,
            transactionDate: transaction.transactionDate,
            baseTTSByDate: baseTTSByDate
        )
    }

    func displayValue(
        krwValue: Decimal,
        baseCurrency: SelectableCurrency,
        transactionDate: String,
        baseTTSByDate: [String: Decimal]
    ) -> Decimal? {
        guard baseCurrency != .krw else {
            return krwValue
        }
        guard let baseKrwPerUnit = baseKrwPerUnit(
            baseCurrency: baseCurrency,
            transactionDate: transactionDate,
            baseTTSByDate: baseTTSByDate
        ) else {
            return nil
        }
        return BaseRateMath.baseDisplayValue(
            krwValue: krwValue,
            baseKrwPerUnit: baseKrwPerUnit
        )
    }

    func exchangeInfo(
        for transaction: LocalTransaction,
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal]
    ) -> String? {
        guard transaction.currencyCode != baseCurrency.rawValue,
              let currency = SelectableCurrency(rawValue: transaction.currencyCode),
              let baseKrwPerUnit = baseKrwPerUnit(
                  baseCurrency: baseCurrency,
                  transactionDate: transaction.transactionDate,
                  baseTTSByDate: baseTTSByDate
              )
        else {
            return nil
        }

        let counterKrwPerUnit: Decimal?
        if currency == .krw {
            counterKrwPerUnit = Decimal(1)
        } else {
            let rate = transaction.appliedRate
                ?? rateProvider.rate(for: currency, on: transaction.transactionDate)
            counterKrwPerUnit = rate.flatMap {
                BaseRateMath.krwPerUnit(tts: $0, unit: currency.exchangeUnit)
            }
        }
        guard let counterKrwPerUnit else {
            return nil
        }

        let counterRate = BaseRateMath.counterRate(
            baseKrwPerUnit: baseKrwPerUnit,
            counterKrwPerUnit: counterKrwPerUnit
        )
        return "\(baseCurrency.rawValue) 1.00 = \(transaction.currencyCode) "
            + CurrencyFormat.rateString(counterRate)
    }

    func baseKrwPerUnit(
        baseCurrency: SelectableCurrency,
        transactionDate: String,
        baseTTSByDate: [String: Decimal]
    ) -> Decimal? {
        if baseCurrency == .krw {
            return Decimal(1)
        }
        guard let tts = baseTTSByDate[transactionDate] else {
            return nil
        }
        return BaseRateMath.krwPerUnit(tts: tts, unit: baseCurrency.exchangeUnit)
    }

    func memoTitle(for transaction: LocalTransaction) -> String {
        let trimmed = transaction.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        return WoniStrings.memoFallback(language)
    }

    func categoryDisplayName(id: Int) -> String {
        guard let category = categoriesByID[id] else {
            return WoniStrings.uncategorized(language)
        }

        return language == .ko ? category.displayNameKo : category.displayNameEn
    }

    func assetDisplayName(id: Int) -> String {
        guard let asset = assetsByID[id] else {
            return WoniStrings.unassigned(language)
        }

        return language == .ko ? asset.displayNameKo : asset.displayNameEn
    }

    func amountTone(for transaction: LocalTransaction) -> MainAmountTone {
        switch transaction.transactionType {
        case .expense:
            .expense
        case .income:
            .income
        }
    }

    static func dateString(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return dateString(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    static func dateString(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(from dateString: String, calendar: Calendar) -> Date? {
        let parts = dateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }

        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))
    }
}

private extension Decimal {
    var nilIfZero: Decimal? {
        self == 0 ? nil : self
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
