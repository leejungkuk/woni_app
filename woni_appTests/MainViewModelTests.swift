//
//  MainViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 표시 스냅샷 빌더·포매터(MainViewModel+Display.swift)의 계약도 이 스위트가 검증한다.
@Suite(.serialized)
@MainActor
struct MainViewModelTests {
    @Test("월 타이틀은 language에 맞게 한글과 영문 형식을 사용한다")
    func monthTitleUsesLanguageSpecificFormat() throws {
        let korean = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko
        )
        let english = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .en
        )

        #expect(korean.monthTitle == "2026년 1월")
        #expect(english.monthTitle == "JANUARY 2026")
    }

    @Test("달력은 일요일 시작 grid와 윤년 2월을 계산한다")
    func calendarGridUsesSundayStartAndLeapYear() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2024, month: 2, day: 10),
            language: .ko
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
            language: .ko
        )

        await viewModel.load()

        #expect(viewModel.summary.income == decimalLiteral("300.00"))
        #expect(viewModel.summary.expense == decimalLiteral("150.00"))
        #expect(viewModel.summary.total == decimalLiteral("150.00"))
        #expect(viewModel.summary.totalTone == MainAmountTone.income)
        #expect(viewModel.summaryItems.map { $0.kind } == [
            MainSummaryItem.Kind.expense,
            MainSummaryItem.Kind.income,
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
            language: .en
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
            language: .ko
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
            language: .ko
        )

        await viewModel.load()

        let selectedDay = try #require(viewModel.calendarDays.first { $0.dateString == "2026-01-15" })
        #expect(viewModel.summary.expense == Decimal(0))
        #expect(viewModel.summary.total == Decimal(0))
        #expect(viewModel.hasUnconvertedTransactions)
        #expect(viewModel.conversionWarningText == "선택한 기본 통화로 환산할 수 없는 거래는 집계에서 제외했습니다.")
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
            language: .ko,
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
        _ = await januaryLoad.value

        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.selectedDateString == "2026-01-15")
        #expect(viewModel.summary.income == decimalLiteral("200.00"))
        #expect(viewModel.summary.expense == Decimal(0))
        #expect(viewModel.historyRows.isEmpty)
    }

    @Test("스와이프 방향은 이전/다음 달 이동으로 해석된다")
    func swipeMovesMonthByDominantAxis() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko
        )

        await viewModel.handleSwipe(horizontal: -80, vertical: 10)
        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.selectedDateString == "2026-01-15")

        // 1월은 오늘이 속한 달이라 복귀 시 오늘이 다시 선택된다(값은 위와 같지만 경로가 다르다).
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
            language: .ko
        )
        await korean.load()

        let english = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .en
        )
        await english.load()

        let stored = try #require(try await repository.all(month: LedgerMonth(year: 2026, month: 1)).first)
        #expect(stored.memo == nil)
        #expect(korean.historyRows.first?.title == "메모")
        #expect(english.historyRows.first?.title == "Memo")
    }

    @Test("applyLanguage는 표시 row를 즉시 갱신하고 선택 월과 선택일을 유지한다")
    func applyLanguageRefreshesDisplayRowsWithoutResettingSelection() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("100.00"),
            categoryID: 999,
            assetID: 998,
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: nil
        ))
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko
        )

        await viewModel.load()

        let selectedMonth = viewModel.selectedMonth
        let selectedDateString = viewModel.selectedDateString
        #expect(viewModel.monthTitle == "2026년 1월")
        #expect(viewModel.summaryItems.map(\.title) == ["지출", "수입", "합계"])
        #expect(viewModel.historyRows.first?.title == "메모")
        #expect(viewModel.historyRows.first?.categoryAssetText == "미분류 · 미지정")

        viewModel.applyLanguage(.en)

        #expect(viewModel.selectedMonth == selectedMonth)
        #expect(viewModel.selectedDateString == selectedDateString)
        #expect(viewModel.monthTitle == "JANUARY 2026")
        #expect(viewModel.summaryItems.map(\.kind) == [
            MainSummaryItem.Kind.expense,
            MainSummaryItem.Kind.income,
            MainSummaryItem.Kind.total
        ])
        #expect(viewModel.summaryItems.map(\.title) == ["Expense", "Income", "Total"])
        #expect(viewModel.historyRows.first?.title == "Memo")
        #expect(viewModel.historyRows.first?.categoryAssetText == "Uncategorized · Unassigned")
    }
}

extension MainViewModelTests {
    @Test("현재 월 스냅샷에서 clientEntryID로 거래를 동기 조회한다")
    func transactionLookupFindsEntryInCurrentMonthSnapshot() async throws {
        let clientEntryID = UUID()
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: decimalLiteral("42.00"),
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: "lookup"
        ))
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko
        )

        await viewModel.load()

        #expect(viewModel.transaction(clientEntryID: clientEntryID)?.clientEntryID == clientEntryID)
    }

    @Test("현재 월 스냅샷에 없는 clientEntryID 조회는 nil을 반환한다")
    func transactionLookupReturnsNilForMissingEntry() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko
        )

        await viewModel.load()

        #expect(viewModel.transaction(clientEntryID: UUID()) == nil)
    }

    @Test("히스토리 행 id는 서버 id가 아니라 clientEntryID를 사용한다")
    func historyRowIdentityUsesClientEntryID() async throws {
        let clientEntryID = UUID()
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: decimalLiteral("42.00"),
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: "identity"
        ))
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko
        )

        await viewModel.load()

        #expect(viewModel.historyRows.first?.id == clientEntryID)
    }

    @Test("moveMonth로 오늘이 없는 달로 옮기면 선택일이 유지돼 선택 셀 없이 히스토리가 빈다")
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
            language: .ko
        )

        await viewModel.moveMonth(by: 1)

        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.selectedDateString == "2026-01-15")
        #expect(viewModel.calendarDays.allSatisfy { !$0.isSelected })
        #expect(viewModel.summary.income == decimalLiteral("200.00"))
        #expect(viewModel.historyRows.isEmpty)
    }

    @Test("setMonth는 월만 변경하고 선택일을 유지한 채 load를 수행한다")
    func setMonthKeepsSelectedDateAndLoads() async throws {
        let loader = DeferredMonthLoader()
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
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

    @Test("보고 있는 달을 다시 설정하면 선택일을 유지하고 load를 다시 돌리지 않는다")
    func setMonthWithUnchangedMonthKeepsSelectionAndSkipsLoad() async throws {
        var requestedMonths: [LedgerMonth] = []
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: { month in
                requestedMonths.append(month)
                return []
            }
        )
        await viewModel.load()
        let otherDay = try #require(viewModel.calendarDays.first { $0.dateString == "2026-01-20" })
        viewModel.selectDay(otherDay)

        await viewModel.setMonth(year: 2026, month: 1)

        #expect(viewModel.selectedDateString == "2026-01-20")
        #expect(requestedMonths == [LedgerMonth(year: 2026, month: 1)])
    }

    /// 보는 달과 어긋나지만 확정된 동작이다 — 월 이동은 선택 날짜를 건드리지 않는다(플랜 §0).
    @Test("월을 이동해도 추가 화면 기본 날짜는 직전에 고른 날짜 그대로다")
    func defaultEntryDateKeepsPreviousSelectionAfterMonthMove() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 7, day: 31),
            language: .ko
        )
        let pickedDate = try makeSeoulDate(year: 2026, month: 7, day: 20)
        await viewModel.load()
        let pickedDay = try #require(viewModel.calendarDays.first { $0.dateString == "2026-07-20" })
        viewModel.selectDay(pickedDay)

        await viewModel.moveMonth(by: 1)

        #expect(viewModel.defaultEntryDate == pickedDate)
    }

    @Test("다른 달에서 고른 날짜가 있어도 이번 달로 돌아오면 오늘이 선택된다")
    func returningToCurrentMonthSelectsToday() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("100.00"),
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: "today"
        ))
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko
        )

        await viewModel.setMonth(year: 2026, month: 3)
        #expect(viewModel.selectedDateString == "2026-01-15")
        // 3월에서 직접 날짜를 고른다. 이렇게 해야 복귀 시의 "오늘"이 선택이 남아 있던 것과 구분된다.
        let marchDay = try #require(viewModel.calendarDays.first { $0.dateString == "2026-03-20" })
        viewModel.selectDay(marchDay)

        await viewModel.setMonth(year: 2026, month: 1)

        let today = try #require(viewModel.calendarDays.first { $0.dateString == "2026-01-15" })
        #expect(viewModel.selectedDateString == "2026-01-15")
        #expect(today.isSelected)
        #expect(viewModel.historyRows.map(\.title) == ["today"])
    }

    @Test("isToday는 주입 currentDate 기준이며 선택일과 독립적으로 계산된다")
    func calendarMarksInjectedTodaySeparatelyFromSelectedDay() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko
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
            transactionDate: "2026-07-27",
            memo: "tokyo"
        ))

        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 7, day: 27),
            language: .ko,
            seedData: SeedLoader().load()
        )

        await viewModel.load()

        let firstRow = try #require(viewModel.historyRows.first)
        #expect(viewModel.summary.expense == decimalLiteral("9047.60"))
        #expect(viewModel.summaryItems.first { $0.kind == .expense }?.amountText == "9,047")
        #expect(viewModel.hasUnconvertedTransactions == false)
        #expect(firstRow.amountText == "9,047")
        #expect(firstRow.secondaryAmountText == "JPY 1,000")
        #expect(firstRow.exchangeInfoText == "KRW 1.00 = JPY 0.1105")
    }

    @Test("번들 시드 하한의 USD 거래를 CNY base 월 합계와 달력 및 히스토리에 환산한다")
    func bundledSeedLowerBoundConvertsUSDTransactionsForCNYBase() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("19301.00"),
            currencyCode: "USD",
            transactionType: .expense,
            transactionDate: "2024-07-29",
            memo: "lower-bound-expense",
            appliedRate: nil,
            krwAmount: nil
        ))
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("19207.00"),
            currencyCode: "USD",
            categoryID: 30,
            transactionType: .income,
            transactionDate: "2024-07-30",
            memo: "next-day-income",
            appliedRate: nil,
            krwAmount: nil
        ))

        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2024, month: 7, day: 29),
            language: .ko,
            seedData: SeedLoader().load(),
            baseCurrency: .cny
        )

        await viewModel.load()

        let lowerBoundDay = try #require(
            viewModel.calendarDays.first { $0.dateString == "2024-07-29" }
        )
        let nextDay = try #require(
            viewModel.calendarDays.first { $0.dateString == "2024-07-30" }
        )
        let lowerBoundRow = try #require(
            viewModel.historyRows.first { $0.title == "lower-bound-expense" }
        )

        #expect(viewModel.summary.income == decimalLiteral("139582.00"))
        #expect(viewModel.summary.expense == decimalLiteral("139925.00"))
        #expect(lowerBoundDay.expense == decimalLiteral("139925.00"))
        #expect(nextDay.income == decimalLiteral("139582.00"))
        #expect(viewModel.hasUnconvertedTransactions == false)
        #expect(lowerBoundRow.exchangeInfoText == "CNY 1.00 = USD 0.1379")
    }

    @Test("저장된 krwAmount와 appliedRate는 Main 표시에서 시드보다 우선한다")
    func persistedKrwAmountAndAppliedRateTakePrecedenceInDisplay() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("10.00"),
            currencyCode: "USD",
            transactionType: .expense,
            transactionDate: "2026-07-15",
            memo: "server quote",
            appliedRate: decimalLiteral("1250.00"),
            krwAmount: decimalLiteral("12345.67")
        ))

        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 7, day: 15),
            language: .ko,
            seedData: SeedLoader().load()
        )

        await viewModel.load()

        let firstRow = try #require(viewModel.historyRows.first)
        #expect(viewModel.summary.expense == decimalLiteral("12345.67"))
        #expect(viewModel.hasUnconvertedTransactions == false)
        #expect(firstRow.amountText == "12,345")
        #expect(firstRow.secondaryAmountText == "USD 10.00")
        #expect(firstRow.exchangeInfoText == "KRW 1.00 = USD 0.0008")
    }

    @Test("JPY base는 확정 KRW 금액을 거래일 JPY 환율로 나누고 KRW 거래도 대칭 표시한다")
    func jpyBaseConvertsPersistedUSDAndKRWSymmetrically() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("10.00"),
            currencyCode: "USD",
            transactionType: .expense,
            transactionDate: "2026-07-27",
            memo: "usd",
            appliedRate: decimalLiteral("1480.96"),
            krwAmount: decimalLiteral("14809.60")
        ))
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("13900"),
            transactionType: .expense,
            transactionDate: "2026-07-27",
            memo: "krw"
        ))
        let seedData = try SeedLoader().load()
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 7, day: 27),
            language: .ko,
            seedData: seedData,
            baseCurrency: .jpy
        )

        await viewModel.load()

        let jpyKrwPerUnit = try #require(BaseRateMath.krwPerUnit(
            tts: decimalLiteral("904.76"),
            unit: SelectableCurrency.jpy.exchangeUnit
        ))
        let expectedUSD = BaseRateMath.baseDisplayValue(
            krwValue: decimalLiteral("14809.60"),
            baseKrwPerUnit: jpyKrwPerUnit
        )
        let expectedKRW = BaseRateMath.baseDisplayValue(
            krwValue: decimalLiteral("13900"),
            baseKrwPerUnit: jpyKrwPerUnit
        )
        let usdRow = try #require(viewModel.historyRows.first { $0.title == "usd" })
        let krwRow = try #require(viewModel.historyRows.first { $0.title == "krw" })

        #expect(viewModel.baseCurrency == .jpy)
        #expect(viewModel.summary.expense == expectedUSD + expectedKRW)
        #expect(viewModel.summaryItems.first { $0.kind == .expense }?.amountText == "3,173")
        #expect(usdRow.amountText == "1,636")
        #expect(usdRow.secondaryAmountText == "USD 10.00")
        #expect(usdRow.exchangeInfoText == "JPY 1.00 = USD 0.006109")
        #expect(krwRow.amountText == "1,536")
        #expect(krwRow.secondaryAmountText == "KRW 13,900")
        #expect(krwRow.exchangeInfoText == "JPY 1.00 = KRW 9.0476")
        #expect(!viewModel.hasUnconvertedTransactions)
    }

    @Test("base 환율이 없으면 KRW 거래도 미환산으로 표시하고 집계에서 제외한다")
    func missingBaseRateKeepsKRWOriginalAmount() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("13900"),
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: "krw"
        ))
        let seedData = SeedData(
            exchangeRates: [],
            expenseCategories: addExpenseExpenseCategories(),
            incomeCategories: addExpenseIncomeCategories(),
            assets: addExpenseAssets()
        )
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            seedData: seedData,
            baseCurrency: .jpy
        )

        await viewModel.load()

        let row = try #require(viewModel.historyRows.first)
        #expect(viewModel.summary.expense == 0)
        #expect(viewModel.hasUnconvertedTransactions)
        #expect(row.amountText == "KRW 13,900")
        #expect(row.secondaryAmountText == nil)
        #expect(row.exchangeInfoText == nil)
    }

    @Test("환율 정보가 없는 동일 base 거래는 원금액으로 합계와 내역에 포함한다")
    func sameBaseTransactionWithoutRateUsesOriginalAmount() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("10.25"),
            currencyCode: "USD",
            transactionType: .expense,
            transactionDate: "2026-01-15",
            memo: "cash",
            appliedRate: nil,
            krwAmount: nil
        ))
        let seedData = SeedData(
            exchangeRates: [],
            expenseCategories: addExpenseExpenseCategories(),
            incomeCategories: addExpenseIncomeCategories(),
            assets: addExpenseAssets()
        )
        let viewModel = try Self.makeViewModel(
            repository: repository,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            seedData: seedData,
            baseCurrency: .usd
        )

        await viewModel.load()

        let row = try #require(viewModel.historyRows.first)
        #expect(viewModel.summary.expense == decimalLiteral("10.25"))
        #expect(viewModel.summaryItems.first { $0.kind == .expense }?.amountText == "10.25")
        #expect(!viewModel.hasUnconvertedTransactions)
        #expect(row.amountText == "10.25")
        #expect(row.secondaryAmountText == nil)
        #expect(row.exchangeInfoText == nil)
    }

    @Test("연속 base 변경은 마지막 resolver 결과만 원자적으로 적용한다")
    func consecutiveBaseChangesCommitOnlyLatestSnapshot() async throws {
        let date = "2026-01-15"
        let cache = DeferredExchangeRateCache()
        let seedData = SeedData(
            exchangeRates: [],
            expenseCategories: addExpenseExpenseCategories(),
            incomeCategories: addExpenseIncomeCategories(),
            assets: addExpenseAssets()
        )
        let transaction = Self.makeTransaction(
            amount: decimalLiteral("1000"),
            transactionType: .expense,
            transactionDate: date,
            memo: "race"
        )
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            seedData: seedData,
            baseRateResolver: BaseRateResolver(
                cache: cache,
                seedRateProvider: RateProvider(seedData: seedData)
            ),
            loadTransactions: { _ in [transaction] }
        )
        await viewModel.load()
        #expect(viewModel.summary.expense == decimalLiteral("1000"))

        let jpyChange = Task { await viewModel.applyBaseCurrency(.jpy) }
        await cache.waitForRequest(currencyCode: "JPY", date: date)
        #expect(viewModel.baseCurrency == .krw)
        #expect(viewModel.summary.expense == decimalLiteral("1000"))
        #expect(!viewModel.hasUnconvertedTransactions)

        let usdChange = Task { await viewModel.applyBaseCurrency(.usd) }
        await cache.waitForRequest(currencyCode: "USD", date: date)
        await cache.resume(currencyCode: "USD", date: date, tts: decimalLiteral("100"))
        _ = await usdChange.value

        #expect(viewModel.baseCurrency == .usd)
        #expect(viewModel.summary.expense == decimalLiteral("10"))
        #expect(viewModel.summaryItems.first { $0.kind == .expense }?.amountText == "10.00")
        #expect(!viewModel.hasUnconvertedTransactions)

        await cache.resume(currencyCode: "JPY", date: date, tts: nil)
        _ = await jpyChange.value

        #expect(viewModel.baseCurrency == .usd)
        #expect(viewModel.summary.expense == decimalLiteral("10"))
        #expect(!viewModel.hasUnconvertedTransactions)
        #expect(!viewModel.isLoading)
    }

    @Test("base 전환 중 월 이동은 최신 월의 완성 스냅샷만 적용한다")
    func monthMoveDuringBaseChangeCommitsLatestMonthSnapshot() async throws {
        let januaryDate = "2026-01-15"
        let februaryDate = "2026-02-01"
        let cache = DeferredExchangeRateCache()
        let seedData = SeedData(
            exchangeRates: [],
            expenseCategories: addExpenseExpenseCategories(),
            incomeCategories: addExpenseIncomeCategories(),
            assets: addExpenseAssets()
        )
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            seedData: seedData,
            baseRateResolver: BaseRateResolver(
                cache: cache,
                seedRateProvider: RateProvider(seedData: seedData)
            ),
            loadTransactions: { month in
                if month.month == 1 {
                    return [Self.makeTransaction(
                        amount: decimalLiteral("1000"),
                        transactionType: .expense,
                        transactionDate: januaryDate,
                        memo: "january"
                    )]
                }
                return [Self.makeTransaction(
                    amount: decimalLiteral("2000"),
                    transactionType: .expense,
                    transactionDate: februaryDate,
                    memo: "february"
                )]
            }
        )
        await viewModel.load()

        let baseChange = Task { await viewModel.applyBaseCurrency(.jpy) }
        await cache.waitForRequest(currencyCode: "JPY", date: januaryDate)
        let monthMove = Task { await viewModel.moveMonth(by: 1) }
        await cache.waitForRequest(currencyCode: "JPY", date: februaryDate)

        await cache.resume(currencyCode: "JPY", date: februaryDate, tts: decimalLiteral("1000"))
        await monthMove.value
        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.baseCurrency == .jpy)
        #expect(viewModel.summary.expense == decimalLiteral("200"))
        #expect(!viewModel.hasUnconvertedTransactions)

        await cache.resume(currencyCode: "JPY", date: januaryDate, tts: nil)
        _ = await baseChange.value
        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.baseCurrency == .jpy)
        #expect(viewModel.summary.expense == decimalLiteral("200"))
        #expect(!viewModel.hasUnconvertedTransactions)
        #expect(!viewModel.isLoading)
    }

    @Test("월 load 뒤 base 변경이 역순 완료돼도 최신 월과 base로 끝나고 loading을 해제한다")
    func baseChangeSupersedesInFlightMonthLoadAndFinishesLoading() async throws {
        let loader = DeferredMonthLoader()
        let cache = DeferredExchangeRateCache()
        let seedData = SeedData(
            exchangeRates: [],
            expenseCategories: addExpenseExpenseCategories(),
            incomeCategories: addExpenseIncomeCategories(),
            assets: addExpenseAssets()
        )
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            seedData: seedData,
            baseRateResolver: BaseRateResolver(
                cache: cache,
                seedRateProvider: RateProvider(seedData: seedData)
            ),
            loadTransactions: loader.load
        )

        let monthLoad = Task { await viewModel.setMonth(year: 2026, month: 2) }
        await loader.waitForRequestCount(1)
        let baseChange = Task { await viewModel.applyBaseCurrency(.usd) }
        await loader.waitForRequestCount(2)

        loader.resumeLast(
            month: LedgerMonth(year: 2026, month: 2),
            returning: [Self.makeTransaction(
                amount: decimalLiteral("50.25"),
                currencyCode: "USD",
                transactionType: .expense,
                transactionDate: "2026-02-01",
                memo: "latest"
            )]
        )
        await cache.waitForRequest(currencyCode: "USD", date: "2026-02-01")
        await cache.resume(currencyCode: "USD", date: "2026-02-01", tts: nil)
        _ = await baseChange.value

        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.baseCurrency == .usd)
        #expect(viewModel.summary.expense == decimalLiteral("50.25"))
        #expect(!viewModel.hasUnconvertedTransactions)
        #expect(!viewModel.isLoading)

        loader.resume(
            month: LedgerMonth(year: 2026, month: 2),
            returning: [Self.makeTransaction(
                amount: decimalLiteral("999"),
                transactionType: .expense,
                transactionDate: "2026-02-01",
                memo: "stale"
            )]
        )
        await monthLoad.value

        #expect(viewModel.selectedMonth == MainMonth(year: 2026, month: 2))
        #expect(viewModel.baseCurrency == .usd)
        #expect(viewModel.summary.expense == decimalLiteral("50.25"))
        #expect(!viewModel.hasUnconvertedTransactions)
        #expect(!viewModel.isLoading)
    }

    @Test("resolver 진행 중 foreground 신호는 reload로 최신 환율 상태에 수렴한다")
    func foregroundSignalDuringResolutionReloadsToLatestSnapshot() async throws {
        let loader = DeferredMonthLoader()
        let cache = DeferredExchangeRateCache()
        let signal = ForegroundActivationSignal()
        let reloadCoordinator = ForegroundMainReloadCoordinator()
        let seedData = Self.emptySeedData()
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            seedData: seedData,
            baseCurrency: .jpy,
            baseRateResolver: BaseRateResolver(
                cache: cache,
                seedRateProvider: RateProvider(seedData: seedData)
            ),
            loadTransactions: loader.load
        )

        let initialLoad = Task { await viewModel.load() }
        await loader.waitForRequestCount(1)
        loader.resumeLast(
            month: LedgerMonth(year: 2026, month: 1),
            returning: [Self.makeForegroundTransaction(
                amount: "1000", date: "2026-01-15", memo: "stale"
            )]
        )
        await cache.waitForRequest(currencyCode: "JPY", date: "2026-01-15")

        signal.bump()
        let foregroundReload = Task {
            await reloadCoordinator.handle(
                revision: signal.revision,
                baseCurrency: .jpy,
                reload: { _ = await viewModel.reload() }
            )
        }
        await loader.waitForRequestCount(1)
        loader.resumeLast(
            month: LedgerMonth(year: 2026, month: 1),
            returning: [Self.makeForegroundTransaction(
                amount: "2000", date: "2026-01-16", memo: "latest"
            )]
        )
        await cache.waitForRequest(currencyCode: "JPY", date: "2026-01-16")
        await cache.resume(
            currencyCode: "JPY",
            date: "2026-01-16",
            tts: decimalLiteral("1000")
        )
        await foregroundReload.value

        #expect(viewModel.summary.expense == decimalLiteral("200"))

        await cache.resume(currencyCode: "JPY", date: "2026-01-15", tts: nil)
        _ = await initialLoad.value

        #expect(viewModel.summary.expense == decimalLiteral("200"))
        #expect(!viewModel.isLoading)
    }

    @Test("첫 스냅샷이 없는 최초 로드 중에는 isInitialLoading이 참이다")
    func firstLoadReportsInitialLoading() async throws {
        let loader = DeferredMonthLoader()
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: loader.load
        )

        let firstLoad = Task { await viewModel.load() }
        await loader.waitForRequestCount(1)

        #expect(viewModel.isLoading)
        #expect(viewModel.isInitialLoading)

        loader.resume(month: LedgerMonth(year: 2026, month: 1), returning: [])
        await firstLoad.value

        #expect(!viewModel.isInitialLoading)
    }

    @Test("거래가 0건이어도 스냅샷이 있으면 reload 중 isInitialLoading이 거짓이라 달력이 유지된다")
    func reloadWithCommittedSnapshotIsNotInitialLoading() async throws {
        let loader = DeferredMonthLoader()
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: loader.load
        )

        let firstLoad = Task { await viewModel.load() }
        await loader.waitForRequestCount(1)
        loader.resume(month: LedgerMonth(year: 2026, month: 1), returning: [])
        await firstLoad.value
        #expect(!viewModel.calendarDays.isEmpty)

        let reload = Task { await viewModel.reload() }
        await loader.waitForRequestCount(1)

        #expect(viewModel.isLoading)
        #expect(!viewModel.isInitialLoading)
        #expect(!viewModel.calendarDays.isEmpty)

        loader.resume(month: LedgerMonth(year: 2026, month: 1), returning: [])
        await reload.value
    }

    @Test("로드 실패도 스냅샷을 커밋하므로 재시도 중 isInitialLoading은 거짓이다")
    func retryAfterFailedLoadIsNotInitialLoading() async throws {
        let loader = DeferredMonthLoader()
        var isFirstLoad = true
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: { month in
                guard !isFirstLoad else {
                    isFirstLoad = false
                    throw MainViewModelTestError.loadFailure
                }
                return try await loader.load(month: month)
            }
        )

        await viewModel.load()
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.calendarDays.isEmpty)

        let retry = Task { await viewModel.reload() }
        await loader.waitForRequestCount(1)

        #expect(viewModel.isLoading)
        #expect(!viewModel.isInitialLoading)

        loader.resume(month: LedgerMonth(year: 2026, month: 1), returning: [])
        await retry.value

        #expect(viewModel.errorMessage == nil)
    }
}

private enum MainViewModelTestError: Error {
    case loadFailure
}

private extension MainViewModelTests {
    static func emptySeedData() -> SeedData {
        SeedData(
            exchangeRates: [],
            expenseCategories: addExpenseExpenseCategories(),
            incomeCategories: addExpenseIncomeCategories(),
            assets: addExpenseAssets()
        )
    }

    static func makeForegroundTransaction(
        amount: String,
        date: String,
        memo: String
    ) -> LocalTransaction {
        makeTransaction(
            amount: decimalLiteral(amount),
            transactionType: .expense,
            transactionDate: date,
            memo: memo,
            krwAmount: decimalLiteral(amount)
        )
    }

    static func makeViewModel(
        repository: TransactionRepository? = nil,
        currentDate: Date,
        language: AppLanguage,
        seedData: SeedData = addExpenseSeedData(),
        baseCurrency: SelectableCurrency = .krw
    ) throws -> MainViewModel {
        let repository = try repository ?? TransactionRepository(database: AppDatabase.inMemory())
        return makeViewModel(
            repository: repository,
            currentDate: currentDate,
            language: language,
            seedData: seedData,
            baseCurrency: baseCurrency
        )
    }

    static func makeViewModel(
        repository: TransactionRepository,
        currentDate: Date,
        language: AppLanguage,
        seedData: SeedData = addExpenseSeedData(),
        baseCurrency: SelectableCurrency = .krw,
        baseRateResolver: BaseRateResolver? = nil,
        loadTransactions: ((LedgerMonth) async throws -> [LocalTransaction])? = nil
    ) -> MainViewModel {
        let rateProvider = RateProvider(seedData: seedData)
        return MainViewModel(
            transactionRepository: repository,
            catalogProvider: CatalogProvider(seedData: seedData),
            rateProvider: rateProvider,
            baseRateResolver: baseRateResolver ?? BaseRateResolver(
                cache: FakeExchangeRateCache(),
                seedRateProvider: rateProvider
            ),
            baseCurrency: baseCurrency,
            currentDate: currentDate,
            language: language,
            loadTransactions: loadTransactions
        )
    }

    static func makeTransaction(
        clientEntryID: UUID = UUID(),
        amount: Decimal,
        currencyCode: String = "KRW",
        categoryID: Int = 10,
        assetID: Int = 20,
        transactionType: LocalTransaction.TransactionType,
        transactionDate: String,
        memo: String?,
        appliedRate: Decimal? = nil,
        krwAmount: Decimal? = nil
    ) -> LocalTransaction {
        LocalTransaction(
            clientEntryID: clientEntryID,
            amount: amount,
            currencyCode: currencyCode,
            categoryID: categoryID,
            assetID: assetID,
            transactionType: transactionType,
            transactionDate: transactionDate,
            memo: memo,
            appliedRate: appliedRate,
            krwAmount: krwAmount
        )
    }
}

@MainActor
private final class DeferredMonthLoader {
    private struct Request {
        let month: LedgerMonth
        let continuation: CheckedContinuation<[LocalTransaction], Error>
    }

    private struct CountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    /// 요청이 끝내 도착하지 않는 회귀에서 hang 대신 실패로 끝내기 위한 상한.
    private static let waiterTimeoutNanoseconds: UInt64 = 10_000_000_000

    private var requests: [Request] = []
    private var countWaiters: [Int: CountWaiter] = [:]
    private var nextWaiterID = 0

    var requestedMonths: [LedgerMonth] {
        requests.map { $0.month }
    }

    func load(month: LedgerMonth) async throws -> [LocalTransaction] {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(Request(month: month, continuation: continuation))
            resumeSatisfiedWaiters()
        }
    }

    func resume(month: LedgerMonth, returning transactions: [LocalTransaction]) {
        guard let index = requests.firstIndex(where: { $0.month == month }) else {
            return
        }

        let request = requests.remove(at: index)
        request.continuation.resume(returning: transactions)
    }

    func resumeLast(month: LedgerMonth, returning transactions: [LocalTransaction]) {
        guard let index = requests.lastIndex(where: { $0.month == month }) else {
            return
        }

        let request = requests.remove(at: index)
        request.continuation.resume(returning: transactions)
    }

    func resume(month: LedgerMonth, throwing error: Error) {
        guard let index = requests.firstIndex(where: { $0.month == month }) else {
            return
        }

        let request = requests.remove(at: index)
        request.continuation.resume(throwing: error)
    }

    /// 요청 도착을 continuation으로 기다린다. yield 횟수 폴링은 CI의 병렬 시뮬레이터 부하에서
    /// 대상 Task가 스케줄되기 전에 소진돼 실패하므로 쓰지 않는다.
    func waitForRequestCount(_ count: Int) async {
        guard requests.count < count else {
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
            countWaiters[waiterID] = CountWaiter(
                expectedCount: count,
                continuation: continuation
            )
        }
    }

    private func resumeSatisfiedWaiters() {
        for (id, waiter) in countWaiters where requests.count >= waiter.expectedCount {
            countWaiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    private func failWaiter(id: Int) {
        guard let waiter = countWaiters.removeValue(forKey: id) else {
            return
        }

        // 조용히 반환하면 이후 resumeLast가 no-op되어 테스트가 hang한다 — 즉시 실패시킨다.
        Issue.record("waitForRequestCount(\(waiter.expectedCount)) 미충족: 현재 \(requests.count)건")
        waiter.continuation.resume()
    }
}

private actor DeferredExchangeRateCache: ExchangeRateCaching {
    private typealias RateContinuation = CheckedContinuation<CachedExchangeRate?, Error>

    private struct Request {
        let lookup: ExchangeRateCacheLookup
        let continuation: RateContinuation
    }

    private var requests: [Request] = []
    private var requestWaiters: [ExchangeRateCacheLookup: [CheckedContinuation<Void, Never>]] = [:]

    func upsert(_: [CachedExchangeRate]) async throws {}

    func latestRate(
        for currencyCode: String,
        onOrBefore localDate: String
    ) async throws -> CachedExchangeRate? {
        try await withCheckedThrowingContinuation { (continuation: RateContinuation) in
            let lookup = ExchangeRateCacheLookup(
                currencyCode: currencyCode,
                localDate: localDate
            )
            requests.append(Request(lookup: lookup, continuation: continuation))
            requestWaiters.removeValue(forKey: lookup)?.forEach { $0.resume() }
        }
    }

    func waitForRequest(currencyCode: String, date: String) async {
        let lookup = ExchangeRateCacheLookup(currencyCode: currencyCode, localDate: date)
        guard !requests.contains(where: { $0.lookup == lookup }) else {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            requestWaiters[lookup, default: []].append(continuation)
        }
    }

    func resume(currencyCode: String, date: String, tts: Decimal?) {
        let lookup = ExchangeRateCacheLookup(currencyCode: currencyCode, localDate: date)
        guard let index = requests.firstIndex(where: { $0.lookup == lookup }) else {
            return
        }
        let request = requests.remove(at: index)
        let rate = tts.map {
            CachedExchangeRate(currencyCode: currencyCode, baseDate: date, tts: $0)
        }
        request.continuation.resume(returning: rate)
    }
}

extension MainViewModelTests {
    @Test("다음 달로 이동하면 월 변경 방향은 next다")
    func movingToNextMonthRecordsNextDirection() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 3, day: 15),
            language: .ko
        )

        await viewModel.setMonth(year: 2026, month: 4)

        #expect(viewModel.monthChangeDirection == .next)
    }

    @Test("이전 달로 이동하면 월 변경 방향은 previous다")
    func movingToPreviousMonthRecordsPreviousDirection() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 3, day: 15),
            language: .ko
        )

        await viewModel.setMonth(year: 2026, month: 2)

        #expect(viewModel.monthChangeDirection == .previous)
    }

    @Test("월 픽커의 먼 미래와 과거 점프도 연월 순서로 방향을 정한다")
    func pickerJumpsRecordDirectionByYearAndMonth() async throws {
        let futureViewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 3, day: 15),
            language: .ko
        )
        let pastViewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 3, day: 15),
            language: .ko
        )

        await futureViewModel.setMonth(year: 2026, month: 12)
        await pastViewModel.setMonth(year: 2025, month: 11)

        #expect(futureViewModel.monthChangeDirection == .next)
        #expect(pastViewModel.monthChangeDirection == .previous)
    }

    @Test("12월과 1월 경계에서도 연도를 포함해 방향을 정한다")
    func yearBoundaryRecordsChronologicalDirection() async throws {
        let nextViewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 12, day: 15),
            language: .ko
        )
        let previousViewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2027, month: 1, day: 15),
            language: .ko
        )

        await nextViewModel.setMonth(year: 2027, month: 1)
        await previousViewModel.setMonth(year: 2026, month: 12)

        #expect(nextViewModel.monthChangeDirection == .next)
        #expect(previousViewModel.monthChangeDirection == .previous)
    }

    @Test("같은 달을 다시 고르면 방향과 달력 스냅샷을 유지한다")
    func reselectingMonthKeepsDirectionAndCalendarDays() async throws {
        let viewModel = try Self.makeViewModel(
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko
        )
        // 직전 이동을 next로 만들어 둔다. previous로 두면 같은 달 비교도 previous라
        // 방향 계산을 early return 앞으로 옮기는 회귀를 이 단언이 구분하지 못한다.
        await viewModel.setMonth(year: 2026, month: 2)
        let calendarDays = viewModel.calendarDays

        await viewModel.setMonth(year: 2026, month: 2)

        #expect(viewModel.monthChangeDirection == .next)
        #expect(viewModel.calendarDays == calendarDays)
    }

    @Test("월 로드 완료 전 새 달의 빈 달력 골격을 즉시 표시한다")
    func monthChangeImmediatelyPublishesEmptyCalendarSkeleton() async throws {
        let loader = DeferredMonthLoader()
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: loader.load
        )

        let monthChange = Task { await viewModel.setMonth(year: 2026, month: 4) }
        await loader.waitForRequestCount(1)

        #expect(viewModel.calendarDays.count == 35)
        #expect(viewModel.calendarDays.prefix(3).allSatisfy { $0.day == nil })
        #expect(viewModel.calendarDays[3].dateString == "2026-04-01")
        #expect(viewModel.calendarDays.compactMap(\.day).count == 30)
        #expect(viewModel.calendarDays.compactMap(\.day).last == 30)
        #expect(viewModel.calendarDays.allSatisfy { $0.income == nil && $0.expense == nil })

        loader.resume(month: LedgerMonth(year: 2026, month: 4), returning: [])
        await monthChange.value
    }

    @Test("연속 월 이동 요청이 역순 완료돼도 마지막 월과 이동 방향만 적용한다")
    func consecutiveMonthChangesCommitOnlyLatestSnapshotAndDirection() async throws {
        let loader = DeferredMonthLoader()
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: loader.load
        )

        let januaryLoad = Task { await viewModel.load() }
        await loader.waitForRequestCount(1)
        let marchLoad = Task { await viewModel.setMonth(year: 2026, month: 3) }
        await loader.waitForRequestCount(2)
        // 최초 로드가 아직 진행 중이어도 골격이 먼저 커밋되므로 인디케이터 조건이 풀린다.
        #expect(!viewModel.isInitialLoading)
        let februaryLoad = Task { await viewModel.setMonth(year: 2026, month: 2) }
        await loader.waitForRequestCount(3)

        loader.resume(
            month: LedgerMonth(year: 2026, month: 2),
            returning: [Self.makeTransaction(
                amount: decimalLiteral("200"),
                transactionType: .expense,
                transactionDate: "2026-02-01",
                memo: "latest"
            )]
        )
        await februaryLoad.value
        loader.resume(
            month: LedgerMonth(year: 2026, month: 3),
            returning: [Self.makeTransaction(
                amount: decimalLiteral("300"),
                transactionType: .expense,
                transactionDate: "2026-03-01",
                memo: "stale-march"
            )]
        )
        await marchLoad.value
        loader.resume(
            month: LedgerMonth(year: 2026, month: 1),
            returning: [Self.makeTransaction(
                amount: decimalLiteral("100"),
                transactionType: .expense,
                transactionDate: "2026-01-15",
                memo: "stale-january"
            )]
        )
        _ = await januaryLoad.value

        #expect(viewModel.monthChangeDirection == .previous)
        #expect(viewModel.summary.expense == decimalLiteral("200"))
        #expect(viewModel.calendarDays.first { $0.dateString == "2026-02-01" }?.expense == decimalLiteral("200"))
        #expect(viewModel.calendarDays.allSatisfy { $0.dateString?.hasPrefix("2026-03") != true })
    }

    @Test("월 로드가 실패해도 새 달 골격과 방향을 유지하고 오류를 표시한다")
    func failedMonthLoadKeepsSkeletonAndDirection() async throws {
        let loader = DeferredMonthLoader()
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: loader.load
        )

        let monthChange = Task { await viewModel.setMonth(year: 2026, month: 2) }
        await loader.waitForRequestCount(1)
        let skeleton = viewModel.calendarDays
        loader.resume(
            month: LedgerMonth(year: 2026, month: 2),
            throwing: MainViewModelTestError.loadFailure
        )
        await monthChange.value

        #expect(viewModel.monthChangeDirection == .next)
        #expect(viewModel.calendarDays == skeleton)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("이번 달 복귀 로드 전에는 이전 달 내역과 요약을 유지한다")
    func returningToCurrentMonthKeepsHistoryUntilLoadCompletes() async throws {
        let loader = DeferredMonthLoader()
        let viewModel = try Self.makeViewModel(
            repository: TransactionRepository(database: AppDatabase.inMemory()),
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: loader.load
        )

        let marchTransaction = Self.makeTransaction(
            amount: decimalLiteral("88"),
            transactionType: .expense,
            transactionDate: "2026-03-20",
            memo: "march-history"
        )
        let marchLoad = Task { await viewModel.setMonth(year: 2026, month: 3) }
        await loader.waitForRequestCount(1)
        loader.resume(month: LedgerMonth(year: 2026, month: 3), returning: [marchTransaction])
        await marchLoad.value
        let marchDay = try #require(viewModel.calendarDays.first { $0.dateString == "2026-03-20" })
        viewModel.selectDay(marchDay)
        let previousRows = viewModel.historyRows
        let previousSummary = viewModel.summary

        let januaryLoad = Task { await viewModel.setMonth(year: 2026, month: 1) }
        await loader.waitForRequestCount(1)

        #expect(viewModel.monthChangeDirection == .previous)
        #expect(viewModel.calendarDays.contains { $0.dateString == "2026-01-01" })
        #expect(viewModel.calendarDays.allSatisfy { $0.income == nil && $0.expense == nil })
        // 골격은 selectedDateString 갱신 뒤에 만들어져야 오늘 셀에 선택 표식이 찍힌다.
        // 두 줄의 순서가 뒤집히면 이번 달 복귀 골격에 선택 셀이 하나도 남지 않는다.
        // isToday는 currentDate로만 정해져 순서와 무관하며, 골격이 옳은 달·기준일로 만들어졌음을 고정한다.
        let todayCell = try #require(viewModel.calendarDays.first { $0.dateString == "2026-01-15" })
        #expect(todayCell.isSelected)
        #expect(todayCell.isToday)
        #expect(viewModel.historyRows == previousRows)
        #expect(viewModel.summary == previousSummary)
        // calendarDays 외 스냅샷 필드도 그대로여야 로드 중 내역을 눌러 수정 화면에 진입할 수 있다.
        #expect(viewModel.transaction(clientEntryID: marchTransaction.clientEntryID) != nil)
        #expect(viewModel.errorMessage == nil)

        loader.resume(month: LedgerMonth(year: 2026, month: 1), returning: [])
        await januaryLoad.value
    }
}
