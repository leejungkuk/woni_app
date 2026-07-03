import Foundation
import Observation

@Observable
@MainActor
final class MainViewModel {
    var selectedMonth: MainMonth
    var selectedDateString: String?
    private(set) var summary: MainMonthlySummary = .empty
    private(set) var calendarDays: [MainCalendarDay] = []
    private(set) var historyRows: [MainHistoryRow] = []
    private(set) var hasUnconvertedTransactions = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let transactionRepository: TransactionRepository
    private let rateProvider: RateProvider
    private let calendar: Calendar
    private let locale: Locale
    private let categoriesByID: [Int: Category]
    private let assetsByID: [Int: Asset]
    private let loadTransactions: (LedgerMonth) async throws -> [LocalTransaction]
    private var transactions: [LocalTransaction] = []
    private var loadGeneration = 0

    var monthTitle: String {
        if MainLocaleText.isKorean(locale: locale) {
            return "\(selectedMonth.year)년 \(selectedMonth.month)월"
        }

        guard let date = selectedMonth.date(day: 1, calendar: calendar) else {
            return "\(selectedMonth.year)"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    var summaryItems: [MainSummaryItem] {
        [
            MainSummaryItem(
                kind: .income,
                title: MainLocaleText.isKorean(locale: locale) ? "수입" : "Income",
                amountText: formatMoney(summary.income),
                tone: .income
            ),
            MainSummaryItem(
                kind: .expense,
                title: MainLocaleText.isKorean(locale: locale) ? "지출" : "Expense",
                amountText: formatMoney(summary.expense),
                tone: .expense
            ),
            MainSummaryItem(
                kind: .total,
                title: MainLocaleText.isKorean(locale: locale) ? "합계" : "Total",
                amountText: formatMoney(summary.total),
                tone: summary.totalTone
            )
        ]
    }

    var conversionWarningText: String? {
        guard hasUnconvertedTransactions else {
            return nil
        }

        return MainLocaleText.isKorean(locale: locale)
            ? "환율이 없는 외화 거래는 합계에서 제외됐습니다."
            : "Foreign entries without rates are excluded from totals."
    }

    init(
        transactionRepository: TransactionRepository,
        catalogProvider: CatalogProvider,
        rateProvider: RateProvider,
        currentDate: Date = Date(),
        calendar: Calendar = .woniSeoul,
        locale: Locale = .current,
        loadTransactions: ((LedgerMonth) async throws -> [LocalTransaction])? = nil
    ) {
        self.transactionRepository = transactionRepository
        self.rateProvider = rateProvider
        self.calendar = calendar
        self.locale = locale
        self.loadTransactions = loadTransactions ?? { month in
            try await transactionRepository.all(month: month)
        }
        selectedMonth = MainMonth(date: currentDate, calendar: calendar)
        selectedDateString = Self.dateString(from: currentDate, calendar: calendar)

        let categories = catalogProvider.categories(for: .expense) + catalogProvider.categories(for: .income)
        categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        assetsByID = Dictionary(uniqueKeysWithValues: catalogProvider.assets.map { ($0.id, $0) })
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedMonth = selectedMonth
        isLoading = true
        errorMessage = nil

        do {
            let loadedTransactions = try await loadTransactions(requestedMonth.ledgerMonth)
            guard shouldApplyLoad(generation: generation, requestedMonth: requestedMonth) else {
                finishLoadIfCurrent(generation: generation)
                return
            }

            transactions = loadedTransactions
            rebuildDisplay()
        } catch {
            guard shouldApplyLoad(generation: generation, requestedMonth: requestedMonth) else {
                finishLoadIfCurrent(generation: generation)
                return
            }

            transactions = []
            summary = .empty
            calendarDays = makeCalendarDays(dailySummaries: [:])
            historyRows = []
            hasUnconvertedTransactions = false
            errorMessage = error.localizedDescription
        }
        finishLoadIfCurrent(generation: generation)
    }

    func reload() async {
        await load()
    }

    func selectDay(_ day: MainCalendarDay) {
        guard let dateString = day.dateString else {
            return
        }

        selectedDateString = dateString
        rebuildDisplay()
    }

    func moveMonth(by value: Int) async {
        selectedMonth = selectedMonth.addingMonths(value, calendar: calendar)
        selectedDateString = selectedMonth.date(day: 1, calendar: calendar).map {
            Self.dateString(from: $0, calendar: calendar)
        }
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

    func formatMoney(_ amount: Decimal) -> String {
        moneyFormatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }
}

private extension MainViewModel {
    var moneyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }

    func rebuildDisplay() {
        let summariesByDate = dailySummaries(from: transactions)
        summary = monthlySummary(from: summariesByDate.values)
        calendarDays = makeCalendarDays(dailySummaries: summariesByDate)
        historyRows = makeHistoryRows()
    }

    func monthlySummary(from dailySummaries: Dictionary<String, MainDailySummary>.Values) -> MainMonthlySummary {
        let income = dailySummaries.reduce(Decimal(0)) { $0 + $1.income }
        let expense = dailySummaries.reduce(Decimal(0)) { $0 + $1.expense }
        return MainMonthlySummary(income: income, expense: expense, total: income - expense)
    }

    func dailySummaries(from transactions: [LocalTransaction]) -> [String: MainDailySummary] {
        hasUnconvertedTransactions = false
        return transactions.reduce(into: [:]) { result, transaction in
            guard let amount = baseAmount(for: transaction) else {
                hasUnconvertedTransactions = true
                return
            }

            var dailySummary = result[transaction.transactionDate] ?? MainDailySummary()
            switch transaction.transactionType {
            case .expense:
                dailySummary.expense += amount
            case .income:
                dailySummary.income += amount
            }
            result[transaction.transactionDate] = dailySummary
        }
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
                income: nil,
                expense: nil
            )
        }

        for day in dayRange {
            let dateString = Self.dateString(year: selectedMonth.year, month: selectedMonth.month, day: day)
            let dailySummary = dailySummaries[dateString]
            days.append(MainCalendarDay(
                id: dateString,
                day: day,
                dateString: dateString,
                isSelected: dateString == selectedDateString,
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
                income: nil,
                expense: nil
            ))
        }

        return days
    }

    func makeHistoryRows() -> [MainHistoryRow] {
        guard let selectedDateString else {
            return []
        }

        return transactions
            .filter { $0.transactionDate == selectedDateString }
            .map { transaction in
                let tone = amountTone(for: transaction)
                let baseAmount = baseAmount(for: transaction)
                let categoryName = categoryDisplayName(id: transaction.categoryID)
                let assetName = assetDisplayName(id: transaction.assetID)
                let title = memoTitle(for: transaction)
                let isForeignCurrency = transaction.currencyCode != SelectableCurrency.krw.rawValue
                let secondaryAmount = baseAmount != nil && isForeignCurrency
                    ? "\(transaction.currencyCode) \(formatMoney(transaction.amount))"
                    : nil

                return MainHistoryRow(
                    id: transaction.id.map(String.init) ?? transaction.clientEntryID.uuidString,
                    title: title,
                    categoryAssetText: "\(categoryName) · \(assetName)",
                    exchangeInfoText: exchangeInfo(for: transaction),
                    amountText: historyAmountText(for: transaction, baseAmount: baseAmount),
                    secondaryAmountText: secondaryAmount,
                    tone: tone
                )
            }
    }

    func shouldApplyLoad(generation: Int, requestedMonth: MainMonth) -> Bool {
        generation == loadGeneration && selectedMonth == requestedMonth
    }

    func finishLoadIfCurrent(generation: Int) {
        if generation == loadGeneration {
            isLoading = false
        }
    }

    func historyAmountText(for transaction: LocalTransaction, baseAmount: Decimal?) -> String {
        if let baseAmount {
            return formatMoney(baseAmount)
        }

        if transaction.currencyCode != SelectableCurrency.krw.rawValue {
            return "\(transaction.currencyCode) \(formatMoney(transaction.amount))"
        }

        return formatMoney(transaction.amount)
    }

    func baseAmount(for transaction: LocalTransaction) -> Decimal? {
        if let krwAmount = transaction.krwAmount {
            return krwAmount
        }

        guard transaction.currencyCode != SelectableCurrency.krw.rawValue else {
            return transaction.amount
        }

        guard let currency = SelectableCurrency(rawValue: transaction.currencyCode),
              let rate = rateProvider.rate(for: currency, on: transaction.transactionDate)
        else {
            return nil
        }

        return NSDecimalNumber(decimal: transaction.amount)
            .dividing(by: NSDecimalNumber(decimal: currency.exchangeUnit))
            .multiplying(by: NSDecimalNumber(decimal: rate))
            .decimalValue
            .roundedToTwoFractionDigits
    }

    func exchangeInfo(for transaction: LocalTransaction) -> String? {
        guard transaction.currencyCode != SelectableCurrency.krw.rawValue,
              let currency = SelectableCurrency(rawValue: transaction.currencyCode),
              let rate = rateProvider.rate(for: currency, on: transaction.transactionDate),
              rate > 0
        else {
            return nil
        }

        let foreignPerKRW = NSDecimalNumber(decimal: currency.exchangeUnit)
            .dividing(by: NSDecimalNumber(decimal: rate))
            .decimalValue
        return "KRW 1.00 = \(transaction.currencyCode) \(formatRate(foreignPerKRW))"
    }

    func formatRate(_ rate: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSDecimalNumber(decimal: rate)) ?? "\(rate)"
    }

    func memoTitle(for transaction: LocalTransaction) -> String {
        let trimmed = transaction.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        return MainLocaleText.isKorean(locale: locale) ? "메모" : "Memo"
    }

    func categoryDisplayName(id: Int) -> String {
        guard let category = categoriesByID[id] else {
            return MainLocaleText.isKorean(locale: locale) ? "미분류" : "Uncategorized"
        }

        return MainLocaleText.isKorean(locale: locale) ? category.displayNameKo : category.displayNameEn
    }

    func assetDisplayName(id: Int) -> String {
        guard let asset = assetsByID[id] else {
            return MainLocaleText.isKorean(locale: locale) ? "미지정" : "Unassigned"
        }

        return MainLocaleText.isKorean(locale: locale) ? asset.displayNameKo : asset.displayNameEn
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
}

private extension Decimal {
    var nilIfZero: Decimal? {
        self == 0 ? nil : self
    }
}

private extension Calendar {
    static var woniSeoul: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }
}
