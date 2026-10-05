//
//  MonthReportTestFixture.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 통계 VM 테스트(`MonthReportViewModelTests` · `MonthReportPagingTests`)가 함께 쓰는 도우미.
/// 스위트가 이 프로토콜을 따르면 `makeViewModel`·`makeTransaction` 을 제 것처럼 부른다.
@MainActor
protocol MonthReportTestFixture {}

extension MonthReportTestFixture {
    /// 옆 달 미리 읽기는 기본으로 끈다 — 로더 호출 수·요청 순서를 단언하는 테스트가 배경 읽기에 흔들리면 안 된다.
    func makeViewModel(
        seedData: SeedData = addExpenseSeedData(),
        baseCurrency: SelectableCurrency = .krw,
        loadTransactions: ((LedgerMonth) async throws -> [LocalTransaction])? = nil,
        prefetchesNeighborMonths: Bool = false
    ) throws -> MonthReportViewModel {
        let rateProvider = RateProvider(seedData: seedData)
        return try MonthReportViewModel(
            transactionRepository: TransactionRepository(database: AppDatabase.inMemory()),
            catalogProvider: CatalogProvider(seedData: seedData),
            customCategoryStore: makeCustomCategoryStore(),
            rateProvider: rateProvider,
            baseRateResolver: BaseRateResolver(
                cache: FakeExchangeRateCache(),
                seedRateProvider: rateProvider
            ),
            baseCurrency: baseCurrency,
            currentDate: makeSeoulDate(year: 2026, month: 1, day: 15),
            language: .ko,
            loadTransactions: loadTransactions,
            prefetchesNeighborMonths: prefetchesNeighborMonths
        )
    }

    func makeTransaction(
        clientEntryID: UUID = UUID(),
        amount: Decimal,
        currencyCode: String = "KRW",
        categoryID: Int = 10,
        transactionType: LocalTransaction.TransactionType = .expense,
        transactionDate: String = "2026-01-15",
        memo: String? = nil,
        krwAmount: Decimal? = nil
    ) -> LocalTransaction {
        LocalTransaction(
            clientEntryID: clientEntryID,
            amount: amount,
            currencyCode: currencyCode,
            categoryID: categoryID,
            assetID: 20,
            transactionType: transactionType,
            transactionDate: transactionDate,
            memo: memo,
            krwAmount: krwAmount
        )
    }
}

enum MonthReportViewModelTestError: LocalizedError {
    case loadFailure

    var errorDescription: String? {
        "load failure"
    }
}

/// 바로 답하는 로더. 달마다 다른 거래·오류를 줄 수 있고(없는 달은 `transactions`·`error`), 요청한 달을 순서대로 남긴다.
@MainActor
final class MutableMonthReportLoader {
    var transactions: [LocalTransaction] = []
    var error: Error?
    var transactionsByMonth: [MainMonth: [LocalTransaction]] = [:]
    var errorsByMonth: [MainMonth: Error] = [:]
    private(set) var loadCount = 0
    private(set) var requestedMonths: [MainMonth] = []

    func load(month ledgerMonth: LedgerMonth) async throws -> [LocalTransaction] {
        let month = MainMonth(year: ledgerMonth.year, month: ledgerMonth.month)
        loadCount += 1
        requestedMonths.append(month)
        if let error = errorsByMonth[month] ?? error {
            throw error
        }
        return transactionsByMonth[month] ?? transactions
    }
}

@MainActor
final class DeferredMonthReportLoader {
    private struct Request {
        let month: LedgerMonth
        let continuation: CheckedContinuation<[LocalTransaction], Error>
    }

    private var requests: [Request] = []
    private var requestCount = 0
    private struct CountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private static var waiterTimeoutNanoseconds: UInt64 {
        10_000_000_000
    }

    private var waiters: [Int: CountWaiter] = [:]
    private var nextWaiterID = 0

    func load(month: LedgerMonth) async throws -> [LocalTransaction] {
        try await withCheckedThrowingContinuation { continuation in
            requestCount += 1
            requests.append(Request(month: month, continuation: continuation))
            resumeSatisfiedWaiters()
        }
    }

    func waitForRequestCount(_ count: Int) async {
        guard requestCount < count else {
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
            waiters[waiterID] = CountWaiter(
                expectedCount: count,
                continuation: continuation
            )
        }
    }

    func resumeFirst(month: LedgerMonth, returning transactions: [LocalTransaction]) {
        guard let index = requests.firstIndex(where: { $0.month == month }) else {
            Issue.record("대기 중인 \(month.year)-\(month.month) 요청이 없습니다.")
            return
        }
        requests.remove(at: index).continuation.resume(returning: transactions)
    }

    func resumeFirst(month: LedgerMonth, throwing error: Error) {
        guard let index = requests.firstIndex(where: { $0.month == month }) else {
            Issue.record("대기 중인 \(month.year)-\(month.month) 요청이 없습니다.")
            return
        }
        requests.remove(at: index).continuation.resume(throwing: error)
    }

    func resumeLast(month: LedgerMonth, returning transactions: [LocalTransaction]) {
        guard let index = requests.lastIndex(where: { $0.month == month }) else {
            Issue.record("대기 중인 \(month.year)-\(month.month) 요청이 없습니다.")
            return
        }
        requests.remove(at: index).continuation.resume(returning: transactions)
    }

    private func resumeSatisfiedWaiters() {
        for (id, waiter) in waiters where requestCount >= waiter.expectedCount {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    private func failWaiter(id: Int) {
        guard let waiter = waiters.removeValue(forKey: id) else {
            return
        }
        Issue.record("waitForRequestCount(\(waiter.expectedCount)) 미충족: 현재 \(requestCount)건")
        waiter.continuation.resume()
    }
}
