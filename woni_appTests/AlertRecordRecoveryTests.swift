//
//  AlertRecordRecoveryTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 끝나지 않은 로그아웃·데이터 삭제를 마저 하는 길도 예산 알림 발송 기록을 비운다(BACKLOG B42, 2026-10-04 사용자 결정).
/// 비우지 않으면 같은 계정으로 다시 들어왔을 때 정상 경로를 지난 기기만 80%·100% 를 다시 보낸다.
@Suite(.serialized)
@MainActor
struct AlertRecordRecoveryTests {
    @Test("BDF.S7-R1 표식이 남은 부팅 복구는 발송 기록 두 키를 모두 비우고 표식을 지운다")
    func logoutRecoveryClearsRecords() async throws {
        let records = try AlertRecordSuite(keys: ["r1-a|2026-5|80|KRW|100000", "r1-a|2026-5|100|KRW|100000"])
        let marker = InMemoryLogoutCleanupMarker()
        marker.markPending()
        let auth = FakeAuthService()
        try await auth.ensureIdentity()

        try await Self.recover(auth: auth, marker: marker, records: records)

        #expect(records.remainingKeys.isEmpty)
        #expect(!marker.isPending)
    }

    @Test("BDF.S7-R1 sign-out 이 던져도 부팅 복구는 발송 기록을 비우고 표식을 지운다")
    func logoutRecoveryClearsRecordsWhenSignOutFails() async throws {
        let records = try AlertRecordSuite(keys: ["r1-b|2026-6|80|USD|500.00", "r1-b|2026-6|100|USD|500.00"])
        let marker = InMemoryLogoutCleanupMarker()
        marker.markPending()
        let auth = FakeAuthService(signOutFailuresRemaining: 1)
        try await auth.ensureIdentity()

        try await Self.recover(auth: auth, marker: marker, records: records)

        #expect(auth.signOutCount == 1)
        #expect(records.remainingKeys.isEmpty)
        #expect(!marker.isPending)
    }

    @Test("BDF.S7-R1 표식이 없으면 부팅 복구는 발송 기록을 그대로 둔다")
    func logoutRecoveryKeepsRecordsWithoutMarker() async throws {
        let keys = ["r1-c|2026-7|80|JPY|30000", "r1-c|2026-7|100|JPY|30000"]
        let records = try AlertRecordSuite(keys: keys)
        let marker = InMemoryLogoutCleanupMarker()
        let auth = FakeAuthService()
        try await auth.ensureIdentity()

        try await Self.recover(auth: auth, marker: marker, records: records)

        #expect(records.remainingKeys == keys)
        #expect(auth.signOutCount == 0)
    }

    @Test("BDF.S7-R2 부팅 복구는 표식을 지우기 전에 발송 기록을 비운다")
    func logoutRecoveryClearsRecordsBeforeMarker() async throws {
        let records = try AlertRecordSuite(keys: ["r2-a|2026-8|80|KRW|200000", "r2-a|2026-8|100|KRW|200000"])
        let marker = RecordCheckingMarker(records: records)
        let auth = FakeAuthService()
        try await auth.ensureIdentity()

        try await Self.recover(auth: auth, marker: marker, records: records)

        #expect(marker.keysLeftWhenCleared?.isEmpty == true)
        #expect(!marker.isPending)
    }

    @Test("BDF.S7-R2 원장 비우기가 던지면 복구가 던지고 표식이 남는다 — 발송 기록은 이미 비워져 있다")
    func logoutRecoveryKeepsMarkerWhenLedgerClearFails() async throws {
        let records = try AlertRecordSuite(keys: ["r2-b|2026-9|80|EUR|300.00", "r2-b|2026-9|100|EUR|300.00"])
        let marker = RecordCheckingMarker(records: records)
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let database = try AppDatabase.inMemory()

        await #expect(throws: AlertRecordTestError.ledgerClearFailed) {
            try await AppDependencyFactory.recoverIncompleteLogout(
                repository: FailingLogoutRepository(),
                customCategoryCache: CustomCategoryCacheRepository(database: database),
                authProvider: auth,
                cleanupMarker: marker,
                clearBudgetAlertRecords: { records.store.clear() }
            )
        }

        #expect(marker.isPending)
        #expect(marker.keysLeftWhenCleared == nil)
        #expect(records.remainingKeys.isEmpty)
    }

    @Test("BDF.S7-R3 새 purge 는 서버 삭제 뒤 clearForPurge 전에 발송 기록을 한 번 비운다")
    func confirmedPurgeClearsRecordsBeforeLocalClear() async throws {
        let harness = try await RecordPurgeHarness(keys: ["r3-a|2026-5|80|KRW|400000", "r3-a|2026-5|100|KRW|400000"])

        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        #expect(harness.store.recordClearsSeenByClearForPurge == [1])
        #expect(harness.counter.calls == 1)
        #expect(harness.records.remainingKeys.isEmpty)
        #expect(harness.coordinator.state == .completed)
    }

    @Test("BDF.S7-R3 clearForPurge 가 끝까지 실패해 완료 대기로 남아도 발송 기록은 비워져 있다")
    func purgeClearsRecordsEvenWhenLocalClearKeepsFailing() async throws {
        let harness = try await RecordPurgeHarness(
            keys: ["r3-b|2026-6|80|USD|700.00", "r3-b|2026-6|100|USD|700.00"],
            store: RecordPurgeStore(clearFailuresRemaining: 9),
            maxAmbiguousRetries: 1
        )

        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        #expect(harness.store.recordClearsSeenByClearForPurge == [1, 1])
        #expect(harness.counter.calls == 1)
        #expect(harness.records.remainingKeys.isEmpty)
        #expect(harness.coordinator.state == .completionPending(acknowledged: false))
    }

    @Test("BDF.S7-R3 재시작 재개(같은 계정 표식)도 clearForPurge 전에 발송 기록을 비운다")
    func resumedPurgeClearsRecordsBeforeLocalClear() async throws {
        let memberID = UUID()
        let harness = try await RecordPurgeHarness(
            keys: ["r3-c|2026-7|80|JPY|90000", "r3-c|2026-7|100|JPY|90000"],
            memberID: memberID,
            store: RecordPurgeStore(memberID: memberID.uuidString)
        )

        await harness.coordinator.resumeIfPending()

        #expect(harness.store.recordClearsSeenByClearForPurge == [1])
        #expect(harness.counter.calls == 1)
        #expect(harness.records.remainingKeys.isEmpty)
        #expect(harness.coordinator.state == .completed)
    }

    @Test("BDF.S7-R3 서버 삭제가 실패해 purge 를 포기하면 발송 기록을 비우지 않는다")
    func abandonedPurgeKeepsRecords() async throws {
        let keys = ["r3-d|2026-8|80|EUR|800.00", "r3-d|2026-8|100|EUR|800.00"]
        let harness = try await RecordPurgeHarness(
            keys: keys,
            errors: [APIError.server(code: "UNAUTHORIZED", message: "expired")]
        )

        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        #expect(harness.counter.calls == 0)
        #expect(harness.records.remainingKeys == keys)
        #expect(harness.store.memberID == nil)
        #expect(harness.store.recordClearsSeenByClearForPurge.isEmpty)
        #expect(harness.coordinator.state == .failed)
    }

    @Test("BDF.S7-R3 재개 때 표식이 다른 계정이라 포기하면 발송 기록을 비우지 않는다")
    func resumeWithOtherAccountMarkerKeepsRecords() async throws {
        let keys = ["r3-e|2026-9|80|KRW|600000", "r3-e|2026-9|100|KRW|600000"]
        let harness = try await RecordPurgeHarness(
            keys: keys,
            store: RecordPurgeStore(memberID: UUID().uuidString)
        )

        await harness.coordinator.resumeIfPending()

        #expect(harness.counter.calls == 0)
        #expect(harness.records.remainingKeys == keys)
        #expect(harness.store.memberID == nil)
        #expect(harness.store.recordClearsSeenByClearForPurge.isEmpty)
        #expect(harness.service.deleteCount == 0)
    }
}

// MARK: 기록을 비우기 전에 시작한 판정

extension AlertRecordRecoveryTests {
    @Test("BDF.S7-R4 서버 읽기에서 멈춘 판정은 그 사이 clearRecords() 가 불리면 재개돼도 창을 내지 않고 기록하지 않는다")
    func clearRecordsDropsInFlightEvaluation() async throws {
        let fakes = try HeldFetchFakes(budget: makeAlertBudget(amount: 2_500_000, status: .nearLimit))
        let evaluator = fakes.makeEvaluator()
        let key = try fakes.key(.nearLimit)

        await fakes.evaluateHoldingFetch(evaluator) {
            evaluator.clearRecords()
        }

        #expect(evaluator.pendingAlert == nil)
        #expect(!fakes.records.store.contains(key))
    }

    @Test("BDF.S7-R4 clearRecords() 없이 재개된 판정은 원래대로 창을 내고, 띄우면 기록한다")
    func heldEvaluationRecordsWithoutClear() async throws {
        // 기준 아래로 먼저 확인한 예산이다 — 처음 확인이 이미 넘었으면 창이 없다(BAD step 2).
        let fakes = try HeldFetchFakes(budget: makeAlertBudget(amount: 1_200_000, status: .inProgress))
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate(.ledgerChange)
        fakes.budget = makeAlertBudget(amount: 1_200_000, status: .exceeded)
        let reachedKey = try fakes.key(.reached)
        let nearLimitKey = try fakes.key(.nearLimit)

        await fakes.evaluateHoldingFetch(evaluator) {}

        let alert = try #require(evaluator.pendingAlert)
        #expect(alert.threshold == .reached)
        #expect(evaluator.markShown(alert))
        #expect(fakes.records.store.contains(reachedKey))
        #expect(fakes.records.store.contains(nearLimitKey))
    }

    @Test("BDF.S7-R4 clearRecords() 뒤 새로 시작한 판정은 평소대로 창을 내고, 띄우면 기록한다")
    func evaluationAfterClearRecordsRecords() async throws {
        let fakes = try HeldFetchFakes(budget: makeAlertBudget(amount: 3_000_000, status: .nearLimit))
        let evaluator = fakes.makeEvaluator()
        let key = try fakes.key(.nearLimit)
        await fakes.evaluateHoldingFetch(evaluator) {
            evaluator.clearRecords()
        }
        #expect(evaluator.pendingAlert == nil)
        #expect(!fakes.records.store.contains(key))

        // 기준 아래로 먼저 확인한 예산이다 — 처음 확인이 이미 넘었으면 창이 없다(BAD step 2).
        fakes.budget = makeAlertBudget(amount: 3_000_000, status: .inProgress)
        await evaluator.evaluate(.ledgerChange)
        fakes.budget = makeAlertBudget(amount: 3_000_000, status: .nearLimit)
        await evaluator.evaluate(.ledgerChange)

        let alert = try #require(evaluator.pendingAlert)
        #expect(alert.threshold == .nearLimit)
        #expect(evaluator.markShown(alert))
        #expect(fakes.records.store.contains(key))
    }
}

private extension AlertRecordRecoveryTests {
    static func recover(
        auth: FakeAuthService,
        marker: any LogoutCleanupMarking,
        records: AlertRecordSuite
    ) async throws {
        let database = try AppDatabase.inMemory()
        try await AppDependencyFactory.recoverIncompleteLogout(
            repository: TransactionRepository(database: database),
            customCategoryCache: CustomCategoryCacheRepository(database: database),
            authProvider: auth,
            cleanupMarker: marker,
            clearBudgetAlertRecords: { records.store.clear() }
        )
    }
}

/// 테스트마다 고유 suite 의 실제 발송 기록 저장소. 끝나면 suite 를 지운다.
@MainActor
private final class AlertRecordSuite {
    let store: BudgetAlertRecordStore
    let keys: [String]
    private let suiteName: String

    init(keys: [String]) throws {
        let suiteName = "woni_appTests.AlertRecordRecoveryTests.\(UUID().uuidString)"
        self.suiteName = suiteName
        self.keys = keys
        store = try BudgetAlertRecordStore(userDefaults: #require(UserDefaults(suiteName: suiteName)))
        store.insert(keys)
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// 넣은 키 가운데 아직 남은 것(넣은 순서).
    var remainingKeys: [String] {
        keys.filter(store.contains)
    }
}

/// 지워지는 순간 발송 기록에 남은 키를 적어 두는 로그아웃 표식. 처음부터 남아 있다.
@MainActor
private final class RecordCheckingMarker: LogoutCleanupMarking {
    private(set) var isPending = true
    /// `clear()` 가 불린 순간 남아 있던 키. 불리지 않았으면 nil.
    private(set) var keysLeftWhenCleared: [String]?
    private let records: AlertRecordSuite

    init(records: AlertRecordSuite) {
        self.records = records
    }

    func markPending() {
        isPending = true
    }

    func clear() {
        keysLeftWhenCleared = records.remainingKeys
        isPending = false
    }
}

private struct FailingLogoutRepository: LogoutDataProviding {
    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        false
    }

    func clearForLogout(force _: Bool) async throws {
        throw AlertRecordTestError.ledgerClearFailed
    }
}

@MainActor
private final class RecordClearCounter {
    var calls = 0
}

@MainActor
private struct RecordPurgeHarness {
    let records: AlertRecordSuite
    let counter: RecordClearCounter
    let store: RecordPurgeStore
    let service: RecordPurgeService
    let coordinator: DataPurgeCoordinator

    init(
        keys: [String],
        memberID: UUID = UUID(),
        store: RecordPurgeStore? = nil,
        errors: [Error] = [],
        maxAmbiguousRetries: Int = 3
    ) async throws {
        let records = try AlertRecordSuite(keys: keys)
        let counter = RecordClearCounter()
        let store = store ?? RecordPurgeStore()
        store.counter = counter
        let service = RecordPurgeService(errors: errors)
        let auth = FakeAuthService(makeSignedInUserID: { memberID })
        try await auth.signIn(.google)
        let connectivity = FakeConnectivityMonitor(isOnline: true)

        self.records = records
        self.counter = counter
        self.store = store
        self.service = service
        coordinator = DataPurgeCoordinator(
            session: makeTestSessionCoordinator(authProvider: auth, connectivity: connectivity),
            purgeSync: RecordPurgeSync(),
            purgeStore: store,
            ledgerService: service,
            authProvider: auth,
            connectivity: connectivity,
            clearBudgetAlertRecords: {
                counter.calls += 1
                records.store.clear()
            },
            onDataCleared: {},
            retrySleep: { _ in },
            maxAmbiguousRetries: maxAmbiguousRetries
        )
    }
}

/// `clearForPurge` 가 불릴 때마다 그때까지의 발송 기록 비우기 횟수를 적는다.
@MainActor
private final class RecordPurgeStore: PurgeStateStoring {
    var counter: RecordClearCounter?
    private(set) var memberID: String?
    private(set) var recordClearsSeenByClearForPurge: [Int] = []
    private var clearFailuresRemaining: Int

    init(memberID: String? = nil, clearFailuresRemaining: Int = 0) {
        self.memberID = memberID
        self.clearFailuresRemaining = clearFailuresRemaining
    }

    func markPurgePending(memberID: String) async throws {
        self.memberID = memberID
    }

    func purgePendingMemberID() async throws -> String? {
        memberID
    }

    func clearPurgeMarker() async throws {
        memberID = nil
    }

    func clearForPurge() async throws {
        recordClearsSeenByClearForPurge.append(counter?.calls ?? -1)
        if clearFailuresRemaining > 0 {
            clearFailuresRemaining -= 1
            throw AlertRecordTestError.localClearFailed
        }
        memberID = nil
    }
}

@MainActor
private final class RecordPurgeService: LedgerPurging {
    private var errors: [Error]
    private(set) var deleteCount = 0

    init(errors: [Error]) {
        self.errors = errors
    }

    func deleteAll(accessToken _: String) async throws {
        deleteCount += 1
        guard !errors.isEmpty else {
            return
        }
        throw errors.removeFirst()
    }
}

@MainActor
private final class RecordPurgeSync: PurgeSyncing {
    func suspendPushForPurge() async {}

    func resumePushAfterPurge() async {}
}

private enum AlertRecordTestError: Error {
    case ledgerClearFailed
    case localClearFailed
}

/// 실제 `BudgetAlertEvaluator` 의 입력 — 서버 읽기(`fetch`)를 붙잡을 수 있다. 계정 하나이고,
/// 서버 시각과 읽는 달은 응답의 이번 달이다. 기록은 실제 `BudgetAlertRecordStore`(테스트마다 새 suite)다.
@MainActor
private final class HeldFetchFakes {
    let records: AlertRecordSuite
    let userID = UUID()
    /// 다음 서버 읽기가 줄 응답.
    var budget: MonthlyBudget
    private var holdsNextFetch = false
    private var heldFetch: CheckedContinuation<Void, Never>?

    init(budget: MonthlyBudget) throws {
        self.budget = budget
        records = try AlertRecordSuite(keys: [])
    }

    func makeEvaluator() -> BudgetAlertEvaluator {
        BudgetAlertEvaluator(
            currentUserID: { self.userID },
            probeServerMonth: { ServerMonth(year: self.budget.currentYear, month: self.budget.currentMonth) },
            fetch: { _, _ in
                await self.waitIfHeld()
                return self.budget
            },
            records: records.store
        )
    }

    func key(_ threshold: BudgetAlertThreshold) throws -> String {
        try #require(BudgetAlertDecision.recordKey(userID: userID, budget: budget, threshold: threshold))
    }

    /// 서버 읽기에서 판정을 붙잡고, 닿으면 `change` 를 한 뒤 풀어 판정이 끝날 때까지 기다린다.
    func evaluateHoldingFetch(_ evaluator: BudgetAlertEvaluator, during change: () -> Void) async {
        holdsNextFetch = true
        let task = Task { await evaluator.evaluate(.ledgerChange) }
        var tries = 0
        while heldFetch == nil, tries < 1000 {
            await Task.yield()
            tries += 1
        }
        #expect(heldFetch != nil, "판정이 서버 읽기에 닿지 않았다")
        change()
        heldFetch?.resume()
        heldFetch = nil
        await task.value
    }

    private func waitIfHeld() async {
        guard holdsNextFetch else {
            return
        }
        holdsNextFetch = false
        await withCheckedContinuation { heldFetch = $0 }
    }
}

/// 응답의 이번 달(2026-10) 예산 — `BudgetTabViewModel.isWellFormed` 를 지난다. 임박은 80% 창을, 초과는 100% 창을 내고,
/// 진행 중(50%)은 기준 아래다. 결제수단 세 묶음과 그 외 카테고리 줄은 몫 없이 사용액만 있다.
@MainActor
private func makeAlertBudget(amount: Decimal, status: BudgetStatus) -> MonthlyBudget {
    let isOver = status == .exceeded
    let (spent, percent): (Decimal, Int?) = switch status {
    case .exceeded: (amount + 100_000, nil)
    case .nearLimit: (amount * 4 / 5, 80)
    default: (amount / 2, 50)
    }
    let spentOnly = BudgetLine(
        budgetAmount: nil,
        actualAmount: 30000,
        status: nil,
        percent: nil,
        remainingAmount: nil,
        overAmount: nil
    )
    return MonthlyBudget(
        year: 2026,
        month: 10,
        currentYear: 2026,
        currentMonth: 10,
        remainingDaysIncludingToday: 7,
        hasAnyBudget: true,
        status: status,
        currency: .krw,
        total: BudgetLine(
            budgetAmount: amount,
            actualAmount: spent,
            status: status,
            percent: percent,
            remainingAmount: isOver ? nil : amount - spent,
            overAmount: isOver ? spent - amount : nil
        ),
        paymentGroups: [PaymentGroup.creditCard, .cashAndDebit, .accountAndOther].map {
            BudgetPaymentGroupLine(paymentGroup: $0, line: spentOnly)
        },
        categories: [],
        otherCategories: spentOnly,
        missingRateCount: 0,
        dailyAllowance: nil,
        deletedCategoriesWithSpending: []
    )
}
