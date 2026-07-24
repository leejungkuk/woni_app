//
//  MainViewModelLedgerObserverTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct MainViewModelLedgerObserverTests {
    @Test("ledger 변경 신호 1회는 저장소를 한 번 재조회해 서버 확정 KRW 합계를 반영한다")
    func ledgerChangeReloadsConfirmedAmountOnce() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        let transaction = Self.makeTransaction(
            amount: decimalLiteral("10.00"),
            currencyCode: "USD",
            transactionType: .expense,
            transactionDate: "2026-07-15",
            memo: "server quote",
            appliedRate: decimalLiteral("1400.00"),
            krwAmount: decimalLiteral("14000.00")
        )
        try await repository.insert(transaction)
        let loader = MainReloadCountingLoader(repository: repository)
        let currentDate = try makeSeoulDate(year: 2026, month: 7, day: 15)
        let viewModel = Self.makeViewModel(
            repository: repository,
            currentDate: currentDate,
            loadTransactions: loader.load
        )
        await viewModel.load()
        #expect(viewModel.summary.expense == decimalLiteral("14000.00"))

        let source = LedgerChangeTestSource()
        let observer = Task {
            await viewModel.observeLedgerChanges(source.events, revision: { source.revision })
        }
        await Task.yield()

        let didApplyConfirmation = try await repository.confirmPush(
            clientEntryID: transaction.clientEntryID,
            pushed: TransactionRepository.PushedPayload(
                amount: transaction.amount,
                currencyCode: transaction.currencyCode,
                categoryID: transaction.categoryID,
                assetID: transaction.assetID,
                transactionDate: transaction.transactionDate,
                memo: transaction.memo
            ),
            krwAmount: decimalLiteral("12345.67"),
            appliedRate: decimalLiteral("1234.567"),
            rateBaseDate: "2026-07-21"
        )
        #expect(didApplyConfirmation)
        source.publishChange()
        source.finish()
        await observer.value

        #expect(loader.loadCount == 2)
        #expect(viewModel.summary.expense == decimalLiteral("12345.67"))
        #expect(viewModel.historyRows.first?.amountText == "12,346")
    }

    @Test("구독 이전에 증가한 ledger revision은 observer 시작 시 즉시 reload한다")
    func revisionBeforeSubscriptionReloadsImmediately() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("2500.00"),
            transactionType: .expense,
            transactionDate: "2026-07-15",
            memo: "startup restore"
        ))
        let loader = MainReloadCountingLoader(repository: repository)
        let currentDate = try makeSeoulDate(year: 2026, month: 7, day: 15)
        let viewModel = Self.makeViewModel(
            repository: repository,
            currentDate: currentDate,
            loadTransactions: loader.load
        )
        let finishedEvents = AsyncStream<Void> { continuation in
            continuation.finish()
        }

        await viewModel.observeLedgerChanges(finishedEvents, revision: { 1 })

        #expect(loader.loadCount == 1)
        #expect(viewModel.summary.expense == decimalLiteral("2500.00"))
    }

    @Test("신호가 없고 ledger revision이 그대로면 observer는 reload하지 않는다")
    func unchangedRevisionDoesNotReload() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        let loader = MainReloadCountingLoader(repository: repository)
        let currentDate = try makeSeoulDate(year: 2026, month: 7, day: 15)
        let viewModel = Self.makeViewModel(
            repository: repository,
            currentDate: currentDate,
            loadTransactions: loader.load
        )
        let finishedEvents = AsyncStream<Void> { continuation in
            continuation.finish()
        }

        await viewModel.observeLedgerChanges(finishedEvents, revision: { 0 })

        #expect(loader.loadCount == 0)
    }

    @Test("버퍼된 같은 revision은 구독 시작 비교와 겹쳐도 한 번만 reload한다")
    func bufferedSameRevisionReloadsOnce() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("1000.00"),
            transactionType: .expense,
            transactionDate: "2026-07-21",
            memo: "buffered startup change"
        ))
        let loader = MainReloadCountingLoader(repository: repository)
        let currentDate = try makeSeoulDate(year: 2026, month: 7, day: 21)
        let viewModel = Self.makeViewModel(
            repository: repository,
            currentDate: currentDate,
            loadTransactions: loader.load
        )
        let stream = AsyncStream.makeStream(of: Void.self)
        stream.continuation.yield(())
        stream.continuation.finish()

        await viewModel.observeLedgerChanges(stream.stream, revision: { 1 })

        #expect(loader.loadCount == 1)
        #expect(viewModel.summary.expense == decimalLiteral("1000.00"))
    }

    @Test("reload가 실패하면 revision을 적용 처리하지 않아 이어지는 신호가 같은 변경을 재시도한다")
    func failedReloadDoesNotSwallowRevisionAndRetries() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("3000.00"),
            transactionType: .expense,
            transactionDate: "2026-07-15",
            memo: "retry after failure"
        ))
        // 첫 관찰자 reload(구독 시작 비교)는 실패시키고, 이어지는 신호의 reload는 성공시킨다.
        let loader = MainReloadCountingLoader(repository: repository, failAttempts: 1)
        let currentDate = try makeSeoulDate(year: 2026, month: 7, day: 15)
        let viewModel = Self.makeViewModel(
            repository: repository,
            currentDate: currentDate,
            loadTransactions: loader.load
        )

        // revision=1을 먼저 세우고 이벤트를 버퍼링해 둔다. 구독 시작 비교가 reload#1(실패)을,
        // 버퍼된 이벤트가 reload#2(재시도·성공)를 유발한다. revision을 삼켰다면 재시도가 없다.
        let source = LedgerChangeTestSource()
        source.publishChange()
        source.finish()

        await viewModel.observeLedgerChanges(source.events, revision: { source.revision })

        #expect(loader.loadCount == 2)
        #expect(viewModel.summary.expense == decimalLiteral("3000.00"))
    }

    @Test("observer reload가 실패하는 더 새 load에 superseded되어도 revision을 삼키지 않고 재적용한다")
    func supersededByFailingLoadDoesNotSwallowRevision() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(
            amount: decimalLiteral("4000.00"),
            transactionType: .expense,
            transactionDate: "2026-07-15",
            memo: "superseded"
        ))
        // call#2(테스트가 직접 트리거하는 superseding load)만 실패. call#1(observer reload)·call#3(재시도)는 성공.
        let loader = GatedReloadLoader(repository: repository, failCalls: [2])
        let currentDate = try makeSeoulDate(year: 2026, month: 7, day: 15)
        let viewModel = Self.makeViewModel(
            repository: repository,
            currentDate: currentDate,
            loadTransactions: loader.load
        )

        let source = LedgerChangeTestSource()
        source.publishChange()
        source.finish()
        let observer = Task {
            await viewModel.observeLedgerChanges(source.events, revision: { source.revision })
        }

        // observer의 구독 시작 reload(call#1)가 gate에서 suspend될 때까지 기다린 뒤, suspend된 동안
        // 더 새 load(call#2·실패)를 시작해 call#1을 supersede시킨다. call#1은 superseded로 false 반환(미기록),
        // 버퍼된 이벤트가 call#3로 재시도되어 성공한다. revision을 삼켰다면 재시도가 없어 합계가 비어야 한다.
        await loader.awaitFirstLoadSuspended()
        await viewModel.load()
        loader.releaseFirstLoadNow()
        await observer.value

        #expect(loader.callCount == 3)
        #expect(viewModel.summary.expense == decimalLiteral("4000.00"))
    }
}

private extension MainViewModelLedgerObserverTests {
    static func makeViewModel(
        repository: TransactionRepository,
        currentDate: Date,
        loadTransactions: @escaping (LedgerMonth) async throws -> [LocalTransaction]
    ) -> MainViewModel {
        let seedData = addExpenseSeedData()
        return MainViewModel(
            transactionRepository: repository,
            catalogProvider: CatalogProvider(seedData: seedData),
            rateProvider: RateProvider(seedData: seedData),
            currentDate: currentDate,
            language: .ko,
            loadTransactions: loadTransactions
        )
    }

    static func makeTransaction(
        amount: Decimal,
        currencyCode: String = "KRW",
        transactionType: LocalTransaction.TransactionType,
        transactionDate: String,
        memo: String? = nil,
        appliedRate: Decimal? = nil,
        krwAmount: Decimal? = nil
    ) -> LocalTransaction {
        LocalTransaction(
            clientEntryID: UUID(),
            amount: amount,
            currencyCode: currencyCode,
            categoryID: 10,
            assetID: 20,
            transactionType: transactionType,
            transactionDate: transactionDate,
            memo: memo,
            appliedRate: appliedRate,
            rateBaseDate: nil,
            krwAmount: krwAmount
        )
    }
}

private enum MainLedgerObserverTestError: Error {
    case loadFailure
}

@MainActor
private final class MainReloadCountingLoader {
    private let repository: TransactionRepository
    private let failAttempts: Int
    private(set) var loadCount = 0

    init(repository: TransactionRepository, failAttempts: Int = 0) {
        self.repository = repository
        self.failAttempts = failAttempts
    }

    func load(month: LedgerMonth) async throws -> [LocalTransaction] {
        loadCount += 1
        if loadCount <= failAttempts {
            throw MainLedgerObserverTestError.loadFailure
        }
        return try await repository.all(month: month)
    }
}

/// 첫 load 호출을 제어 가능한 지점에서 suspend시켜, 두 번째(superseding) load를 결정적으로 먼저
/// 완료시킬 수 있게 하는 로더. `failCalls`에 지정한 호출 번호는 throw한다.
@MainActor
private final class GatedReloadLoader {
    private let repository: TransactionRepository
    private let failCalls: Set<Int>
    private(set) var callCount = 0
    private var releaseFirstLoad: CheckedContinuation<Void, Never>?
    private var firstLoadSuspended: CheckedContinuation<Void, Never>?

    init(repository: TransactionRepository, failCalls: Set<Int> = []) {
        self.repository = repository
        self.failCalls = failCalls
    }

    func load(month: LedgerMonth) async throws -> [LocalTransaction] {
        callCount += 1
        let currentCall = callCount
        if currentCall == 1 {
            await withCheckedContinuation { continuation in
                releaseFirstLoad = continuation
                firstLoadSuspended?.resume()
                firstLoadSuspended = nil
            }
        }
        if failCalls.contains(currentCall) {
            throw MainLedgerObserverTestError.loadFailure
        }
        return try await repository.all(month: month)
    }

    func awaitFirstLoadSuspended() async {
        guard releaseFirstLoad == nil else {
            return
        }
        await withCheckedContinuation { firstLoadSuspended = $0 }
    }

    func releaseFirstLoadNow() {
        releaseFirstLoad?.resume()
        releaseFirstLoad = nil
    }
}

@MainActor
private final class LedgerChangeTestSource {
    let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private(set) var revision = 0

    init() {
        let stream = AsyncStream.makeStream(of: Void.self)
        events = stream.stream
        continuation = stream.continuation
    }

    func publishChange() {
        revision += 1
        continuation.yield(())
    }

    func finish() {
        continuation.finish()
    }
}
