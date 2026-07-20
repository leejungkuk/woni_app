//
//  AddExpenseTestSupport.swift
//  woni_appTests
//
//  AddExpenseViewModelTests 전용 in-memory repository·시드 fixture.
//

import Foundation
import Testing
@testable import woni_app

struct AddExpenseHarness {
    let viewModel: AddExpenseViewModel
    let repository: TransactionRepository
}

@MainActor
func makeAddExpenseHarness(seedData: SeedData = addExpenseSeedData()) throws -> AddExpenseHarness {
    try makeAddExpenseHarness(
        seedData: seedData,
        rateProvider: SeedRateProviderAdapter(seedData: seedData)
    )
}

@MainActor
func makeAddExpenseHarness(
    seedData: SeedData = addExpenseSeedData(),
    rateProvider: any RateProviding
) throws -> AddExpenseHarness {
    let repository = try TransactionRepository(database: AppDatabase.inMemory())
    let viewModel = AddExpenseViewModel(
        transactionRepository: repository,
        catalogProvider: CatalogProvider(seedData: seedData),
        addExpenseRateProvider: rateProvider
    )

    return AddExpenseHarness(viewModel: viewModel, repository: repository)
}

func addExpenseSeedData() -> SeedData {
    SeedData(
        exchangeRates: addExpenseExchangeRates(),
        expenseCategories: addExpenseExpenseCategories(),
        incomeCategories: addExpenseIncomeCategories(),
        assets: addExpenseAssets()
    )
}

func addExpenseExchangeRates() -> [SeedExchangeRate] {
    [
        SeedExchangeRate(
            currencyCode: .usd,
            currencyName: "미국 달러",
            tts: decimalLiteral("1400.00"),
            baseDate: "2026-07-02",
            stale: false
        ),
        SeedExchangeRate(
            currencyCode: .jpy,
            currencyName: "일본 엔",
            tts: decimalLiteral("950.00"),
            baseDate: "2026-07-02",
            stale: false
        ),
        SeedExchangeRate(
            currencyCode: .eur,
            currencyName: "유로",
            tts: decimalLiteral("1600.00"),
            baseDate: "2026-07-02",
            stale: false
        ),
        SeedExchangeRate(
            currencyCode: .gbp,
            currencyName: "영국 파운드",
            tts: decimalLiteral("1800.00"),
            baseDate: "2026-07-02",
            stale: false
        )
    ]
}

func addExpenseExpenseCategories() -> [woni_app.Category] {
    [
        Category(
            id: 11,
            code: "TRAVEL",
            displayNameKo: "여행",
            displayNameEn: "Travel",
            icon: "airplane",
            sortOrder: 2
        ),
        Category(
            id: 10,
            code: "FOOD",
            displayNameKo: "식비",
            displayNameEn: "Food",
            icon: "fork.knife",
            sortOrder: 1
        )
    ]
}

func addExpenseIncomeCategories() -> [woni_app.Category] {
    [
        Category(
            id: 31,
            code: "SIDE_INCOME",
            displayNameKo: "부수입",
            displayNameEn: "Side Income",
            icon: "laptopcomputer",
            sortOrder: 2
        ),
        Category(
            id: 30,
            code: "SALARY",
            displayNameKo: "급여",
            displayNameEn: "Salary",
            icon: "banknote",
            sortOrder: 1
        )
    ]
}

func addExpenseAssets() -> [Asset] {
    [
        Asset(
            id: 21,
            code: "CARD",
            displayNameKo: "카드",
            displayNameEn: "Card",
            sortOrder: 2
        ),
        Asset(
            id: 20,
            code: "CASH",
            displayNameKo: "현금",
            displayNameEn: "Cash",
            sortOrder: 1
        )
    ]
}

func transactions(
    in repository: TransactionRepository,
    year: Int,
    month: Int
) async throws -> [LocalTransaction] {
    try await repository.page(
        month: LedgerMonth(year: year, month: month),
        after: TransactionPageCursor?.none,
        size: 20
    )
}

func decimal(_ text: String) throws -> Decimal {
    let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    return try #require(value)
}

func decimalLiteral(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
}

func makeSeoulDate(year: Int, month: Int, day: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))

    let components = DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day
    )
    return try #require(calendar.date(from: components))
}

func makeRelativeSeoulDate(daysFromToday: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))

    let startOfToday = calendar.startOfDay(for: Date())
    return try #require(calendar.date(byAdding: .day, value: daysFromToday, to: startOfToday))
}

struct StubRateProvider: RateProviding {
    private let quote: RateQuote?

    init(quote: RateQuote?) {
        self.quote = quote
    }

    func quote(for _: SelectableCurrency, on _: Date) async -> RateQuote? {
        quote
    }
}
