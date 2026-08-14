import Foundation
import Observation

struct MainDisplaySnapshot {
    let baseCurrency: SelectableCurrency
    let baseTTSByDate: [String: Decimal]
    let transactions: [LocalTransaction]
    let outOfMonthTransactions: [LocalTransaction]
    let summary: MainMonthlySummary
    var calendarDays: [MainCalendarDay]
    let historyRows: [MainHistoryRow]
    let hasUnconvertedTransactions: Bool
}

@Observable
@MainActor
final class MainViewModel {
    /// MainView 페이저의 정착 스프링과 월 변경의 데이터 표시 대기가 같은 길이를 써야 한다 —
    /// 어긋나면 정착 중에 금액이 채워지거나 완료 후 공백이 생긴다.
    nonisolated static let monthTransitionDuration: TimeInterval = 0.35

    var selectedMonth: MainMonth
    var selectedDateString: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var monthChangeDirection: MainMonthChangeDirection = .next
    /// 직전에 화면에서 밀려난 달의 그리드. 페이저 이웃 슬롯과 Reduce Motion 크로스페이드가
    /// 이 보존본을 써야 나가는 달이 금액을 유지한 채 사라진다.
    private(set) var outgoingCalendarDays: (month: MainMonth, days: [MainCalendarDay])?

    private let transactionRepository: TransactionRepository
    let rateProvider: RateProvider
    private let baseRateResolver: BaseRateResolver
    let currentDate: Date
    let calendar: Calendar
    private(set) var language: AppLanguage
    let categoriesByID: [Int: Category]
    let assetsByID: [Int: Asset]
    private let loadTransactions: (LedgerMonth) async throws -> [LocalTransaction]
    private let loadDayTransactions: (String) async throws -> [LocalTransaction]
    private let pauseForMonthTransition: () async -> Void
    private var displaySnapshot: MainDisplaySnapshot
    private var requestedBaseCurrency: SelectableCurrency
    private var loadGeneration = 0
    private var lastAppliedRevision = 0
    /// 진행 중인 월 전환 대기 수. Bool이 아니라 카운터인 이유: 대기 중 추가 스와이프로 전환이
    /// 겹치면, 먼저 깬 전환의 감소가 나중 전환의 대기를 풀어버리면 안 된다.
    private var monthTransitionPauseCount = 0

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

    /// 첫 스냅샷이 커밋되기 전에만 참이다. 갱신 로드에서는 거짓이라 이미 그려진 달력이 인디케이터로
    /// 교체되지 않는다. 실패 로드도 스냅샷을 커밋하므로(`load()`의 catch) 재시도 중에도 거짓이다.
    /// 최초 로드 중 월을 바꾸면 `setMonth`가 골격을 먼저 커밋하므로 그 시점부터 거짓이다 —
    /// 인디케이터가 금액 없는 달력으로 교체된다.
    var isInitialLoading: Bool {
        isLoading && calendarDays.isEmpty
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
        loadTransactions: ((LedgerMonth) async throws -> [LocalTransaction])? = nil,
        loadDayTransactions: ((String) async throws -> [LocalTransaction])? = nil,
        pauseForMonthTransition: (() async -> Void)? = nil
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
        self.loadDayTransactions = loadDayTransactions ?? { date in
            try await transactionRepository.all(on: date)
        }
        self.pauseForMonthTransition = pauseForMonthTransition ?? {
            try? await Task.sleep(for: .seconds(MainViewModel.monthTransitionDuration))
        }
        selectedMonth = MainMonth(date: currentDate, calendar: calendar)
        selectedDateString = Self.dateString(from: currentDate, calendar: calendar)
        requestedBaseCurrency = baseCurrency
        displaySnapshot = MainDisplaySnapshot(
            baseCurrency: baseCurrency,
            baseTTSByDate: [:],
            transactions: [],
            outOfMonthTransactions: [],
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

            let outOfMonthTransactions = try await selectedDayTransactionsOutside(requestedMonth)
            let transactionDates = Set(
                (loadedTransactions + outOfMonthTransactions).map(\.transactionDate)
            )
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
                transactions: loadedTransactions,
                outOfMonthTransactions: outOfMonthTransactions
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
                transactions: [],
                outOfMonthTransactions: []
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
            ?? displaySnapshot.outOfMonthTransactions.first { $0.clientEntryID == clientEntryID }
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

        // 같은 달을 다시 고르는 것은 월 변경이 아니다. 사용자가 고른 날짜와 이미 그려진 화면을 그대로 둔다.
        guard nextMonth != selectedMonth else {
            return
        }

        applyMonthChange(to: nextMonth)
        monthTransitionPauseCount += 1
        await pauseThenLoad()
    }

    /// 제스처 커밋 전용 **동기** 진입점. 월 스왑과 View의 오프셋 리베이스가 같은 프레임에
    /// 일어나야 이음새에서 픽셀이 튀지 않는다. 대기 카운터도 여기서 올린다 — Task 안에서 올리면
    /// Task가 시작되기 전에 끼어든 reload가 정착 중에 금액을 채운다.
    func commitGestureMonthChange(by value: Int) {
        applyMonthChange(to: selectedMonth.addingMonths(value, calendar: calendar))
        monthTransitionPauseCount += 1
        Task { await pauseThenLoad() }
    }

    func formatBaseAmount(_ amount: Decimal) -> String {
        CurrencyFormat.string(amount, currencyCode: displaySnapshot.baseCurrency.rawValue)
    }
}

private extension MainViewModel {
    func applyMonthChange(to nextMonth: MainMonth) {
        monthChangeDirection = (nextMonth.year, nextMonth.month)
            > (selectedMonth.year, selectedMonth.month) ? .next : .previous
        outgoingCalendarDays = (selectedMonth, displaySnapshot.calendarDays)
        selectedMonth = nextMonth
        // 월 이동은 선택 날짜를 건드리지 않는다. 오늘이 속한 달로 돌아올 때도 마찬가지다 —
        // 고른 날짜와 그 내역을 계속 보면서 달만 훑는 것이 이 화면의 규칙이다(2026-08-13 확정).
        displaySnapshot.calendarDays = makeCalendarDays(dailySummaries: [:])
    }

    /// 대기 카운터 증가는 호출자의 동기 구간에 있다 — 여기서 올리면 첫 `await` 이전에
    /// 끼어든 load가 전환 중 스냅샷을 적용해버린다.
    func pauseThenLoad() async {
        // 전환이 끝나기 전에 금액이 채워지면 전환 중 데이터가 미리 뜬다 —
        // 전환 길이만큼 기다린 뒤 로드해 완료 후에 데이터가 나타나게 한다.
        await pauseForMonthTransition()
        monthTransitionPauseCount -= 1
        await load()
    }

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
            transactions: displaySnapshot.transactions,
            outOfMonthTransactions: displaySnapshot.outOfMonthTransactions
        )
    }

    func selectedDayTransactionsOutside(_ month: MainMonth) async throws -> [LocalTransaction] {
        guard let selectedDateString,
              let date = Self.date(from: selectedDateString, calendar: calendar),
              MainMonth(date: date, calendar: calendar) != month
        else {
            return []
        }

        return try await loadDayTransactions(selectedDateString)
    }

    func shouldApplyLoad(
        generation: Int,
        requestedMonth: MainMonth,
        requestedBase: SelectableCurrency
    ) -> Bool {
        generation == loadGeneration
            && selectedMonth == requestedMonth
            && requestedBaseCurrency == requestedBase
            // 전환 대기 중엔 어떤 load도(외부 reload·먼저 깬 겹친 전환 포함) 스냅샷을 적용하지
            // 않는다 — 슬라이드 종료 전 데이터 표시를 모든 경로에서 막는다. 버려진 결과는 대기
            // 종료 후 setMonth의 load가 다시 읽고, refreshIfBehind는 미적용 revision을 다음
            // 이벤트에 재시도한다.
            && monthTransitionPauseCount == 0
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
