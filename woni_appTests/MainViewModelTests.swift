//
//  MainViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

// swiftlint:disable file_length

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
            language: .ko
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

    func resumeLast(month: LedgerMonth, returning transactions: [LocalTransaction]) {
        guard let index = requests.lastIndex(where: { $0.month == month }) else {
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
        // 조용히 반환하면 이후 resumeLast가 no-op되어 테스트가 hang한다 — 즉시 실패시킨다.
        Issue.record("waitForRequestCount(\(count)) 미충족: 현재 \(requests.count)건")
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
