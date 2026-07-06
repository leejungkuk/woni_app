//
//  MainViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct MainViewModelTests {
    @Test("월 타이틀은 locale에 맞게 한글과 영문 형식을 사용한다")
    func monthTitleUsesLocaleSpecificFormat() throws {
        let korean = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ko_KR")
        )
        let english = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "en_US")
        )
        let japanese = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ja_JP")
        )

        #expect(korean.monthTitle == "2026년 1월")
        #expect(english.monthTitle == "JANUARY 2026")
        #expect(japanese.monthTitle == "JANUARY 2026")
    }

    @Test("달력은 일요일 시작 grid와 윤년 2월을 계산한다")
    func calendarGridUsesSundayStartAndLeapYear() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2024, month: 2, day: 10),
            locale: Locale(identifier: "ko_KR")
        )

        await viewModel.load()

        #expect(viewModel.calendarDays.count == 35)
        #expect(viewModel.calendarDays.prefix(4).allSatisfy { $0.day == nil })
        #expect(viewModel.calendarDays[4].day == 1)
        #expect(viewModel.calendarDays.compactMap { $0.day }.last == 29)
        #expect(viewModel.calendarDays.first { $0.dateString == "2024-02-10" }?.isToday == true)
    }

    @Test("월 합계와 일별 marker는 Decimal로 수입과 지출을 집계하고 total tone을 계산한다")
    func loadAggregatesMonthlySummaryAndDailyMarkers() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("100.00"),
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: "coffee"
        ))
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("300.00"),
            categoryID: 30,
            transactionType: .income,
            transactionDate: "2026-01-15",
            memo: nil
        ))
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("50.00"),
            transactionType: .expense,
            transactionDate: "2026-01-16",
            memo: "taxi"
        ))

        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ko_KR")
        )

        await viewModel.load()

        #expect(viewModel.summary.income == decimalLiteral("300.00"))
        #expect(viewModel.summary.expense == decimalLiteral("150.00"))
        #expect(viewModel.summary.total == decimalLiteral("150.00"))
        #expect(viewModel.summary.totalTone == MainAmountTone.income)
        #expect(viewModel.summaryItems.map { $0.kind } == [
            MainSummaryItem.Kind.income,
            MainSummaryItem.Kind.expense,
            MainSummaryItem.Kind.total
        ])

        let selectedDay = try #require(viewModel.calendarDays.first { $0.dateString == "2026-01-15" })
        #expect(selectedDay.income == decimalLiteral("300.00"))
        #expect(selectedDay.expense == decimalLiteral("100.00"))
        #expect(viewModel.historyRows.map { $0.title } == ["메모", "coffee"])
    }

    @Test("total이 음수면 expense tone을 사용한다")
    func negativeTotalUsesExpenseTone() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("500.00"),
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: "hotel"
        ))
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("100.00"),
            categoryID: 30,
            transactionType: .income,
            transactionDate: "2026-01-15",
            memo: "refund"
        ))
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "en_US")
        )

        await viewModel.load()

        #expect(viewModel.summary.total == decimalLiteral("-400.00"))
        #expect(viewModel.summary.totalTone == MainAmountTone.expense)
        #expect(viewModel.summaryItems.last?.tone == .expense)
    }

    @Test("total이 0이면 income tone을 사용한다")
    func zeroTotalUsesIncomeTone() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("100.00"),
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: "expense"
        ))
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("100.00"),
            categoryID: 30,
            transactionType: .income,
            transactionDate: "2026-01-15",
            memo: "income"
        ))
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ko_KR")
        )

        await viewModel.load()

        #expect(viewModel.summary.total == Decimal(0))
        #expect(viewModel.summary.totalTone == MainAmountTone.income)
        #expect(viewModel.summaryItems.last?.tone == .income)
    }

    @Test("환율 없는 외화 거래는 합계에서 제외 사실을 경고로 드러낸다")
    func foreignTransactionWithoutRateSetsConversionWarning() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("10.00"),
            currencyCode: "USD",
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: "hotel"
        ))
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ko_KR")
        )

        await viewModel.load()

        let selectedDay = try #require(viewModel.calendarDays.first { $0.dateString == "2026-01-15" })
        #expect(viewModel.summary.expense == Decimal(0))
        #expect(viewModel.summary.total == Decimal(0))
        #expect(viewModel.hasUnconvertedTransactions)
        #expect(viewModel.conversionWarningText == "환율이 없는 외화 거래는 합계에서 제외됐습니다.")
        #expect(selectedDay.expense == nil)
        #expect(viewModel.historyRows.first?.amountText == "USD 10.00")
        #expect(viewModel.historyRows.first?.secondaryAmountText == nil)
    }

    @Test("이전 월 load가 늦게 끝나도 현재 월 화면을 덮지 않는다")
    func staleMonthLoadResultIsDiscarded() async throws {
        let loader = DeferredMonthLoader()
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ko_KR"),
            loadTransactions: loader.load
        )

        let januaryLoad = Task {
            await viewModel.load()
        }
        await loader.waitForRequestCount(1)
        #expect(loader.requestedMonths == [LedgerMonth(year: 2026, month: 1)])

        let februaryLoad = Task {
            await viewModel.handleSwipe(horizontal: -80, vertical: 0)
        }
        await loader.waitForRequestCount(2)
        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(loader.requestedMonths == [
            LedgerMonth(year: 2026, month: 1),
            LedgerMonth(year: 2026, month: 2)
        ])

        loader.resume(
            month: LedgerMonth(year: 2026, month: 2),
            returning: [
                Self.makeTransaction(
                    amount: decimalLiteral("200.00"),
                    categoryID: 30,
                    transactionType: .income,
                    transactionDate: "2026-02-01",
                    memo: "salary"
                )
            ]
        )
        await februaryLoad.value

        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.selectedDateString == "2026-01-15")
        #expect(viewModel.summary.income == decimalLiteral("200.00"))
        #expect(viewModel.summary.expense == Decimal(0))
        #expect(viewModel.historyRows.isEmpty)

        loader.resume(
            month: LedgerMonth(year: 2026, month: 1),
            returning: [
                Self.makeTransaction(
                    amount: decimalLiteral("999.00"),
                    transactionType: .expense,
                    transactionDate: "2026-01-15",
                    memo: "stale"
                )
            ]
        )
        await januaryLoad.value

        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.summary.income == decimalLiteral("200.00"))
        #expect(viewModel.summary.expense == Decimal(0))
        #expect(viewModel.historyRows.isEmpty)
    }

    @Test("스와이프 방향은 이전/다음 달 이동으로 해석된다")
    func swipeMovesMonthByDominantAxis() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ko_KR")
        )

        await viewModel.handleSwipe(horizontal: -80, vertical: 10)
        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.selectedDateString == "2026-01-15")

        await viewModel.handleSwipe(horizontal: 0, vertical: 100)
        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 1))
        #expect(viewModel.selectedDateString == "2026-01-15")

        await viewModel.handleSwipe(horizontal: 20, vertical: 20)
        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 1))
        #expect(viewModel.selectedDateString == "2026-01-15")
    }

    @Test("빈 메모는 저장값을 바꾸지 않고 표시 fallback만 사용한다")
    func emptyMemoUsesDisplayFallbackOnly() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("100.00"),
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: nil
        ))

        let korean = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ko_KR")
        )
        await korean.load()

        let english = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "en_US")
        )
        await english.load()

        let stored = try #require(try await repository.all(month: LedgerMonth(year: 2026, month: 1)).first)
        #expect(stored.memo == nil)
        #expect(korean.historyRows.first?.title == "메모")
        #expect(english.historyRows.first?.title == "Memo")
    }
}

extension MainViewModelTests {
    @Test("moveMonth는 선택일을 유지하고 새 달 거래는 선택일이 다르면 히스토리에 표시하지 않는다")
    func moveMonthKeepsSelectedDate() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("200.00"),
            categoryID: 30,
            transactionType: .income,
            transactionDate: "2026-02-01",
            memo: "salary"
        ))
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ko_KR")
        )

        await viewModel.moveMonth(by: 1)

        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.selectedDateString == "2026-01-15")
        #expect(viewModel.summary.income == decimalLiteral("200.00"))
        #expect(viewModel.historyRows.isEmpty)
    }

    @Test("setMonth는 월만 변경하고 선택일을 유지한 채 load를 수행한다")
    func setMonthKeepsSelectedDateAndLoads() async throws {
        let loader = DeferredMonthLoader()
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ko_KR"),
            loadTransactions: loader.load
        )

        let setMonthTask = Task {
            await viewModel.setMonth(year: 2026, month: 3)
        }
        await loader.waitForRequestCount(1)

        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 3))
        #expect(viewModel.selectedDateString == "2026-01-15")
        #expect(loader.requestedMonths == [LedgerMonth(year: 2026, month: 3)])

        loader.resume(
            month: LedgerMonth(year: 2026, month: 3),
            returning: [
                Self.makeTransaction(
                    amount: decimalLiteral("75.00"),
                    transactionType: .expense,
                    transactionDate: "2026-03-03",
                    memo: "lunch"
                )
            ]
        )
        await setMonthTask.value

        #expect(viewModel.summary.expense == decimalLiteral("75.00"))
        #expect(viewModel.historyRows.isEmpty)
    }

    @Test("isToday는 주입 currentDate 기준이며 선택일과 독립적으로 계산된다")
    func calendarMarksInjectedTodaySeparatelyFromSelectedDay() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            locale: Locale(identifier: "ko_KR")
        )

        await viewModel.load()

        let initialToday = try #require(viewModel.calendarDays.first { $0.dateString == "2026-01-15" })
        #expect(initialToday.isToday)
        #expect(initialToday.isSelected)

        let nextDay = try #require(viewModel.calendarDays.first { $0.dateString == "2026-01-16" })
        viewModel.selectDay(nextDay)

        let today = try #require(viewModel.calendarDays.first { $0.dateString == "2026-01-15" })
        let selectedDay = try #require(viewModel.calendarDays.first { $0.dateString == "2026-01-16" })
        #expect(today.isToday)
        #expect(today.isSelected == false)
        #expect(selectedDay.isToday == false)
        #expect(selectedDay.isSelected)
    }

    @Test("환율 있는 JPY 거래는 100엔 단위로 환산해 월 합계와 히스토리에 표시한다")
    func jpyTransactionUsesHundredUnitConversionInSummaryAndHistory() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("1000.00"),
            currencyCode: "JPY",
            transactionType: .expense,
            transactionDate: "2026-07-15",
            memo: "tokyo"
        ))

        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 7, day: 15),
            locale: Locale(identifier: "ko_KR"),
            seedData: SeedLoader().load()
        )

        await viewModel.load()

        let firstRow = try #require(viewModel.historyRows.first)
        #expect(viewModel.summary.expense == decimalLiteral("9658.80"))
        #expect(viewModel.summaryItems.first { $0.kind == .expense }?.amountText == "9,659")
        #expect(viewModel.hasUnconvertedTransactions == false)
        #expect(firstRow.amountText == "9,659")
        #expect(firstRow.secondaryAmountText == "JPY 1,000.00")
        #expect(firstRow.exchangeInfoText == "KRW 1.00 = JPY 0.1035")
    }
}

private extension MainViewModelTests {
    static func makeViewModel(
        repository: TransactionRepository? = nil,
        currentDate: Date,
        locale: Locale,
        seedData: SeedData = addExpenseSeedData()
    ) throws -> MainViewModel {
        let repository = try repository ?? TransactionRepository(database: AppDatabase.inMemory())
        return makeViewModel(
            repository: repository,
            currentDate: currentDate,
            locale: locale,
            seedData: seedData
        )
    }

    static func makeViewModel(
        repository: TransactionRepository,
        currentDate: Date,
        locale: Locale,
        seedData: SeedData = addExpenseSeedData(),
        loadTransactions: ((LedgerMonth) async throws -> [LocalTransaction])? = nil
    ) -> MainViewModel {
        MainViewModel(
            transactionRepository: repository,
            catalogProvider: CatalogProvider(seedData: seedData),
            rateProvider: RateProvider(seedData: seedData),
            currentDate: currentDate,
            locale: locale,
            loadTransactions: loadTransactions
        )
    }

    static func makeTransaction(
        amount: Decimal,
        currencyCode: String = "KRW",
        categoryID: Int = 10,
        assetID: Int = 20,
        transactionType: LocalTransaction.TransactionType,
        transactionDate: String,
        memo: String?
    ) -> LocalTransaction {
        LocalTransaction(
            clientEntryID: UUID(),
            amount: amount,
            currencyCode: currencyCode,
            categoryID: categoryID,
            assetID: assetID,
            transactionType: transactionType,
            transactionDate: transactionDate,
            memo: memo
        )
    }
}

@MainActor
private final class DeferredMonthLoader {
    private struct Request {
        let month: LedgerMonth
        let continuation: CheckedContinuation<[LocalTransaction], Error>
    }

    private var requests: [Request] = []

    var requestedMonths: [LedgerMonth] {
        requests.map { $0.month }
    }

    func load(month: LedgerMonth) async throws -> [LocalTransaction] {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(Request(month: month, continuation: continuation))
        }
    }

    func resume(month: LedgerMonth, returning transactions: [LocalTransaction]) {
        guard let index = requests.firstIndex(where: { $0.month == month }) else {
            return
        }

        let request = requests.remove(at: index)
        request.continuation.resume(returning: transactions)
    }

    func waitForRequestCount(_ count: Int) async {
        for _ in 0 ..< 20 {
            if requests.count >= count {
                return
            }
            await Task.yield()
        }
    }
}
