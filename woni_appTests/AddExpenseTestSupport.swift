//
//  AddExpenseTestSupport.swift
//  woni_appTests
//
//  AddExpenseViewModelTests 전용 in-memory repository·시드 fixture.
//

import Foundation
import GRDB
import Testing
@testable import woni_app

struct AddExpenseHarness {
    let viewModel: AddExpenseViewModel
    let repository: TransactionRepository
}

@MainActor
func makeAddExpenseHarness(
    seedData: SeedData = addExpenseSeedData(),
    baseCurrency: SelectableCurrency = .krw,
    lastUsedCurrencyStore: LastUsedCurrencyStore? = nil,
    customCategoryStore: CustomCategoryStore? = nil,
    mode: AddExpenseViewModel.Mode = .create
) throws -> AddExpenseHarness {
    try makeAddExpenseHarness(
        seedData: seedData,
        rateProvider: SeedRateProviderAdapter(seedData: seedData),
        baseCurrency: baseCurrency,
        lastUsedCurrencyStore: lastUsedCurrencyStore,
        customCategoryStore: customCategoryStore,
        mode: mode
    )
}

@MainActor
func makeAddExpenseHarness(
    seedData: SeedData = addExpenseSeedData(),
    rateProvider: any RateProviding,
    baseCurrency: SelectableCurrency = .krw,
    lastUsedCurrencyStore: LastUsedCurrencyStore? = nil,
    customCategoryStore: CustomCategoryStore? = nil,
    syncTrigger: (any LocalWriteSyncTriggering)? = nil,
    mode: AddExpenseViewModel.Mode = .create
) throws -> AddExpenseHarness {
    let repository = try TransactionRepository(database: AppDatabase.inMemory())
    let viewModel = try AddExpenseViewModel(
        transactionRepository: repository,
        catalogProvider: CatalogProvider(seedData: seedData),
        customCategoryStore: customCategoryStore ?? makeCustomCategoryStore(),
        addExpenseRateProvider: rateProvider,
        baseCurrency: baseCurrency,
        lastUsedCurrencyStore: lastUsedCurrencyStore,
        syncTrigger: syncTrigger,
        mode: mode
    )

    return AddExpenseHarness(viewModel: viewModel, repository: repository)
}

/// 커스텀 카테고리 store 테스트 대역. in-memory 캐시를 시드해 초기 목록을 만들고,
/// 기본 FakeAuthService가 비로그인 상태라 refresh는 무동작 — 네트워크가 개입하지 않는다.
/// 게이트 판정 테스트는 authProvider를 주입해 세션 상태를 제어한다.
@MainActor
func makeCustomCategoryStore(
    _ categories: [CachedCustomCategory] = [],
    authProvider: (any AuthProviding)? = nil
) throws -> CustomCategoryStore {
    let database = try AppDatabase.inMemory()
    try database.write { db in
        for category in categories {
            try db.execute(
                sql: "INSERT INTO custom_category (id, transaction_type, name) VALUES (?, ?, ?)",
                arguments: [category.id, category.transactionType.rawValue, category.name]
            )
        }
    }
    return try CustomCategoryStore(
        service: CustomCategoryService(),
        cache: CustomCategoryCacheRepository(database: database),
        authProvider: authProvider ?? FakeAuthService()
    )
}

func makeEditableTransaction(
    clientEntryID: UUID = UUID(),
    amount: Decimal = decimalLiteral("123.45"),
    currencyCode: String = "USD",
    categoryID: Int = 11,
    assetID: Int = 21,
    transactionType: LocalTransaction.TransactionType = .expense,
    transactionDate: String = "2026-07-02",
    memo: String? = "original memo",
    createdAt: String? = "2026-07-02T01:02:03Z"
) -> LocalTransaction {
    LocalTransaction(
        id: 7,
        clientEntryID: clientEntryID,
        amount: amount,
        currencyCode: currencyCode,
        categoryID: categoryID,
        assetID: assetID,
        transactionType: transactionType,
        transactionDate: transactionDate,
        memo: memo,
        pending: false,
        appliedRate: decimalLiteral("1400.00"),
        rateBaseDate: "2026-07-02",
        krwAmount: decimalLiteral("172830.00"),
        createdAt: createdAt,
        updatedAt: "2026-07-02T01:02:04Z",
        syncState: .synced
    )
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

actor CurrencyAwareRateProvider: RateProviding {
    struct Request: Equatable {
        let id: Int
        let currency: SelectableCurrency
        let date: Date
    }

    private struct PendingRequest {
        let continuation: CheckedContinuation<RateQuote?, Never>
    }

    private struct CountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    /// 요청이 끝내 도착하지 않는 회귀에서 hang 대신 실패로 끝내기 위한 상한.
    private static let waiterTimeoutNanoseconds: UInt64 = 10_000_000_000

    private let quotes: [SelectableCurrency: RateQuote]
    private let defersResponses: Bool
    private var nextRequestID = 0
    private var recordedRequests: [Request] = []
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var countWaiters: [Int: CountWaiter] = [:]
    private var nextWaiterID = 0

    init(
        quotes: [SelectableCurrency: RateQuote] = [:],
        defersResponses: Bool = false
    ) {
        self.quotes = quotes
        self.defersResponses = defersResponses
    }

    func quote(for currency: SelectableCurrency, on date: Date) async -> RateQuote? {
        let request = Request(
            id: nextRequestID,
            currency: currency,
            date: date
        )
        nextRequestID += 1
        recordedRequests.append(request)
        resumeSatisfiedWaiters()

        guard defersResponses else {
            return quotes[currency]
        }

        return await withCheckedContinuation { continuation in
            pendingRequests[request.id] = PendingRequest(continuation: continuation)
        }
    }

    func requests() -> [Request] {
        recordedRequests
    }

    /// 요청 도착을 continuation으로 기다린다. yield 횟수 폴링은 CI의 병렬 시뮬레이터 부하에서
    /// 대상 Task가 스케줄되기 전에 소진돼 실패하므로 쓰지 않는다.
    func waitForRequestCount(_ expectedCount: Int) async {
        guard recordedRequests.count < expectedCount else {
            return
        }

        let waiterID = nextWaiterID
        nextWaiterID += 1
        let watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.waiterTimeoutNanoseconds)
            await self?.failWaiter(id: waiterID)
        }
        defer { watchdog.cancel() }

        await withCheckedContinuation { continuation in
            countWaiters[waiterID] = CountWaiter(
                expectedCount: expectedCount,
                continuation: continuation
            )
        }
    }

    private func resumeSatisfiedWaiters() {
        for (id, waiter) in countWaiters where recordedRequests.count >= waiter.expectedCount {
            countWaiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    private func failWaiter(id: Int) {
        guard let waiter = countWaiters.removeValue(forKey: id) else {
            return
        }

        // 조용히 대기를 이어가면 이후 resume이 no-op되어 테스트가 hang한다 — 즉시 실패시킨다.
        Issue.record(
            "waitForRequestCount(\(waiter.expectedCount)) 미충족: 현재 \(recordedRequests.count)건"
        )
        waiter.continuation.resume()
    }

    func resume(requestID: Int, with quote: RateQuote?) {
        pendingRequests.removeValue(forKey: requestID)?.continuation.resume(returning: quote)
    }
}
