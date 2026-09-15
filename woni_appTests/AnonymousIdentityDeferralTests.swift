//
//  AnonymousIdentityDeferralTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct AnonymousIdentityDeferralTests {}

extension AnonymousIdentityDeferralTests {
    @Test("기록 없이 앱을 열면 익명 로그인이 일어나지 않는다")
    func foregroundWithoutRecordsDoesNotIssueIdentity() async throws {
        let harness = try await makeDeferralHarness(isOnline: true)

        await AppDependencies.handleForegroundActivation(
            sync: harness.engine,
            coordinator: harness.coordinator,
            prefetchRates: {},
            signal: ForegroundActivationSignal()
        )

        #expect(harness.auth.anonymousSignInCount == 0)
        #expect(harness.auth.currentUserID == nil)
    }

    @Test("기록 없이 네트워크가 복귀해도 익명 로그인이 일어나지 않는다")
    func onlineTransitionWithoutRecordsDoesNotIssueIdentity() async throws {
        let harness = try await makeDeferralHarness(isOnline: false)
        await Task.yield()

        harness.connectivity.setOnline(true)
        for _ in 0 ..< 100 {
            await Task.yield()
        }

        #expect(harness.auth.anonymousSignInCount == 0)
        #expect(harness.auth.currentUserID == nil)
    }

    @Test("삭제 대기만 남은 상태에서는 익명 로그인이 일어나지 않는다")
    func deleteOnlyQueueDoesNotIssueIdentity() async throws {
        let harness = try await makeDeferralHarness(isOnline: true)
        let deletedID = UUID()
        try await harness.repository.insert(makeDeferralTransaction(clientEntryID: deletedID))
        try await harness.repository.markSynced(clientEntryIDs: [deletedID])
        try await harness.repository.delete(clientEntryID: deletedID)

        await harness.engine.pushPending()

        #expect(harness.auth.anonymousSignInCount == 0)
        #expect(try await harness.repository.pendingDeleteClientEntryIDs() == [deletedID])
    }

    @Test("첫 거래를 저장하면 익명 신원이 한 번 발급된다")
    func firstTransactionIssuesIdentityOnce() async throws {
        let harness = try await makeDeferralHarness(isOnline: true)
        configureSuccessfulPush(harness)
        defer { SyncPushURLProtocol.handler = nil }

        try await harness.engine.performLocalWrite {
            try await harness.repository.insert(makeDeferralTransaction())
        }
        await harness.engine.pushPending()

        #expect(harness.auth.anonymousSignInCount == 1)
        #expect(harness.recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])
    }

    @Test("오프라인에서 쌓은 기록은 네트워크 복귀 시 발급 후 전송된다")
    func offlineRecordsIssueIdentityAndPushOnReconnect() async throws {
        let harness = try await makeDeferralHarness(isOnline: false)
        configureSuccessfulPush(harness)
        defer { SyncPushURLProtocol.handler = nil }
        try await harness.repository.insert(makeDeferralTransaction())
        try await harness.repository.insert(makeDeferralTransaction())
        await Task.yield()

        harness.connectivity.setOnline(true)
        let completed = try await waitForDeferralCondition {
            try await harness.repository.pendingPushEntries().isEmpty
        }

        #expect(completed)
        #expect(harness.auth.anonymousSignInCount == 1)
        #expect(harness.recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])
    }

    @Test("커스텀 카테고리 작업만 있어도 익명 신원이 발급된다")
    func categoryOnlyWorkIssuesIdentity() async throws {
        let category = DeferralCategoryWork()
        category.isPending = true
        let harness = try await makeDeferralHarness(
            isOnline: true,
            hasPendingCategoryWork: { category.isPending },
            onBeforeLedgerPush: { category.isPending = false }
        )

        await harness.engine.pushPending()

        #expect(harness.auth.anonymousSignInCount == 1)
        #expect(harness.auth.currentUserID != nil)
    }
}

extension AnonymousIdentityDeferralTests {
    @Test("이미 신원이 있으면 추가 발급 없이 기존 흐름을 탄다")
    func existingIdentityUsesCurrentPushFlow() async throws {
        let harness = try await makeDeferralHarness(isOnline: true, issueIdentity: true)
        configureSuccessfulPush(harness)
        defer { SyncPushURLProtocol.handler = nil }
        try await harness.repository.insert(makeDeferralTransaction())

        await harness.engine.pushPending()

        #expect(harness.auth.anonymousSignInCount == 1)
        #expect(harness.recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])
    }

    @Test("신원이 있으면 삭제 대기만 있어도 삭제가 전송된다")
    func existingIdentityPushesDeleteOnlyQueue() async throws {
        let harness = try await makeDeferralHarness(isOnline: true, issueIdentity: true)
        let deletedID = UUID()
        try await harness.repository.insert(makeDeferralTransaction(clientEntryID: deletedID))
        try await harness.repository.markSynced(clientEntryIDs: [deletedID])
        try await harness.repository.delete(clientEntryID: deletedID)
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successVoidResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.pushPending()

        #expect(harness.recorder.snapshot().map(\.path) == [
            "/api/v1/ledgers/sync/\(deletedID.uuidString)"
        ])
        #expect(try await harness.repository.pendingDeleteClientEntryIDs().isEmpty)
    }

    @Test("발급이 실패하면 push를 중단하고 대기열을 보존한다")
    func identityFailureStopsPushAndPreservesQueue() async throws {
        let harness = try await makeDeferralHarness(
            isOnline: true,
            ensureIdentityFailuresRemaining: 1
        )
        configureSuccessfulPush(harness)
        defer { SyncPushURLProtocol.handler = nil }
        try await harness.repository.insert(makeDeferralTransaction())

        await harness.engine.pushPending()

        #expect(harness.auth.currentUserID == nil)
        #expect(harness.auth.anonymousSignInCount == 0)
        #expect(harness.recorder.snapshot().isEmpty)
        #expect(try await harness.repository.pendingPushEntries().count == 1)
        #expect(harness.coordinator.logoutState == .idle)
    }

    @Test("다음 push 트리거에서 발급을 재시도한다")
    func nextPushRetriesIdentityIssuance() async throws {
        let harness = try await makeDeferralHarness(
            isOnline: true,
            ensureIdentityFailuresRemaining: 1
        )
        configureSuccessfulPush(harness)
        defer { SyncPushURLProtocol.handler = nil }
        try await harness.repository.insert(makeDeferralTransaction())

        await harness.engine.pushPending()
        await harness.engine.pushPending()

        #expect(harness.auth.anonymousSignInCount == 1)
        #expect(harness.recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
    }

    @Test("로그아웃 직후에는 익명 신원을 만들지 않는다")
    func logoutDoesNotImmediatelyIssueIdentity() async throws {
        let harness = try await makeDeferralHarness(isOnline: true, signInMember: true)

        await harness.coordinator.requestLogout()

        #expect(harness.coordinator.logoutState == .completed)
        #expect(harness.auth.currentUserID == nil)
        #expect(harness.auth.anonymousSignInCount == 0)
    }

    @Test("로그아웃 후 새 기록을 남기면 그때 익명 신원이 발급된다")
    func recordAfterLogoutIssuesIdentity() async throws {
        let harness = try await makeDeferralHarness(isOnline: true, signInMember: true)
        configureSuccessfulPush(harness)
        defer { SyncPushURLProtocol.handler = nil }
        await harness.coordinator.requestLogout()

        try await harness.engine.performLocalWrite {
            try await harness.repository.insert(makeDeferralTransaction())
        }
        await harness.engine.pushPending()

        #expect(harness.auth.anonymousSignInCount == 1)
        #expect(harness.recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])
    }
}

extension AnonymousIdentityDeferralTests {
    @Test("계정 전환이 시작되면 push는 신원을 발급하지 않는다")
    func accountSwitchPreventsIdentityIssuance() async throws {
        let harness = try await makeDeferralHarness(isOnline: true)
        try await harness.repository.insert(makeDeferralTransaction())
        let gate = DeferralGate()
        var transitionFinished = false
        let transition = Task { @MainActor in
            await harness.coordinator.runAccountSwitchTransition { await gate.hold() }
            transitionFinished = true
        }
        await gate.waitUntilHeld()
        #expect(!harness.engine.isPushSuspended)
        var pushFinished = false
        let push = Task { @MainActor in
            await harness.engine.pushPending()
            pushFinished = true
        }

        let pushCompletedBeforeRelease = await waitForDeferralCondition { pushFinished }
        #expect(pushCompletedBeforeRelease)
        gate.release()
        let transitionCompleted = await waitForDeferralCondition { transitionFinished }
        #expect(transitionCompleted)
        if pushFinished { await push.value }
        if transitionFinished { await transition.value }
        #expect(harness.auth.anonymousSignInCount == 0)
    }

    @Test("push가 진행 중일 때 시작된 로그인은 교착 없이 완료된다")
    func accountSwitchDuringPushCompletesWithoutDeadlock() async throws {
        let categoryGate = DeferralGate()
        let harness = try await makeDeferralHarness(
            isOnline: true,
            hasPendingCategoryWork: {
                await categoryGate.hold()
                return true
            }
        )
        try await harness.repository.insert(makeDeferralTransaction())
        var pushFinished = false
        let push = Task { @MainActor in
            await harness.engine.pushPending()
            pushFinished = true
        }
        await categoryGate.waitUntilHeld()
        var switchFinished = false
        let accountSwitch = Task { @MainActor in
            await harness.coordinator.runAccountSwitchTransition {
                try? await harness.engine.beginAccountSwitch()
                _ = harness.engine.resumeAccountSwitch(expectedMemberID: nil)
            }
            switchFinished = true
        }
        await waitUntil { harness.coordinator.isTransitioning }

        categoryGate.release()
        let bothCompleted = await waitForDeferralCondition { pushFinished && switchFinished }

        #expect(bothCompleted)
        if pushFinished { await push.value }
        if switchFinished { await accountSwitch.value }
        #expect(harness.auth.anonymousSignInCount == 0)
    }

    @Test("로그아웃이 push를 기다리는 동안에는 신원을 발급하지 않는다")
    func logoutWaitingForPushDoesNotIssueIdentity() async throws {
        let harness = try await makeDeferralHarness(isOnline: true)
        try await harness.repository.insert(makeDeferralTransaction())
        var logoutFinished = false
        let logout = Task { @MainActor in
            await harness.coordinator.requestLogout()
            logoutFinished = true
        }

        let completed = await waitForDeferralCondition { logoutFinished }

        #expect(completed)
        if logoutFinished { await logout.value }
        #expect(harness.auth.anonymousSignInCount == 0)
        #expect(harness.coordinator.logoutState == .awaitingUnsyncedConfirmation)
    }

    @Test("회원 세션 무효화 처리 중에는 익명 신원을 만들지 않는다")
    func memberInvalidationPreventsIdentityIssuance() async throws {
        let harness = try await makeDeferralHarness(isOnline: true, signInMember: true)
        configureSuccessfulPush(harness)
        defer { SyncPushURLProtocol.handler = nil }
        try await harness.repository.insert(makeDeferralTransaction())
        try await harness.auth.signOut()
        let priorGate = DeferralGate()
        let prior = Task { @MainActor in
            await harness.coordinator.runAccountSwitchTransition { await priorGate.hold() }
        }
        await priorGate.waitUntilHeld()
        var invalidationFinished = false
        let invalidation = Task { @MainActor in
            await harness.coordinator.handleRemoteSessionInvalidation(.member)
            invalidationFinished = true
        }
        await Task.yield()
        var pushFinished = false
        let push = Task { @MainActor in
            await harness.engine.pushPending()
            pushFinished = true
        }

        let pushCompletedBeforeRelease = await waitForDeferralCondition { pushFinished }
        #expect(pushCompletedBeforeRelease)
        priorGate.release()
        let invalidationCompleted = await waitForDeferralCondition { invalidationFinished }
        #expect(invalidationCompleted)
        if pushFinished { await push.value }
        await prior.value
        if invalidationFinished { await invalidation.value }
        #expect(harness.auth.anonymousSignInCount == 0)
        #expect(harness.recorder.snapshot().isEmpty)
    }

    @Test("탈퇴 전이가 시작된 뒤에는 신원을 발급하지 않는다")
    func withdrawalPreventsIdentityIssuance() async throws {
        let harness = try await makeDeferralHarness(isOnline: true)
        try await harness.repository.insert(makeDeferralTransaction())
        let gate = DeferralGate()
        var withdrawalFinished = false
        let withdrawal = Task { @MainActor in
            await harness.coordinator.runWithdrawal { await gate.hold() }
            withdrawalFinished = true
        }
        await gate.waitUntilHeld()
        #expect(!harness.engine.isPushSuspended)
        var pushFinished = false
        let push = Task { @MainActor in
            await harness.engine.pushPending()
            pushFinished = true
        }

        let pushCompletedBeforeRelease = await waitForDeferralCondition { pushFinished }
        #expect(pushCompletedBeforeRelease)
        gate.release()
        let withdrawalCompleted = await waitForDeferralCondition { withdrawalFinished }
        #expect(withdrawalCompleted)
        if pushFinished { await push.value }
        if withdrawalFinished { await withdrawal.value }
        #expect(harness.auth.anonymousSignInCount == 0)
    }
}

@MainActor
private struct DeferralHarness {
    let engine: SyncEngine
    let repository: TransactionRepository
    let auth: FakeAuthService
    let connectivity: FakeConnectivityMonitor
    let recorder: SyncPushRequestRecorder
    let coordinator: SessionTransitionCoordinator
}

@MainActor
private func makeDeferralHarness(
    isOnline: Bool,
    issueIdentity: Bool = false,
    signInMember: Bool = false,
    ensureIdentityFailuresRemaining: Int = 0,
    hasPendingCategoryWork: @escaping @MainActor () async -> Bool = { false },
    onBeforeLedgerPush: @escaping @MainActor () async -> Void = {}
) async throws -> DeferralHarness {
    let repository = try TransactionRepository(database: AppDatabase.inMemory())
    let auth = FakeAuthService(
        ensureIdentityFailuresRemaining: ensureIdentityFailuresRemaining
    )
    if issueIdentity {
        try await auth.ensureIdentity()
    } else if signInMember {
        try await auth.signIn(.google)
    }
    let connectivity = FakeConnectivityMonitor(isOnline: isOnline)
    let recorder = SyncPushRequestRecorder()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyncPushURLProtocol.self]
    let engine = SyncEngine(
        repository: repository,
        ledgerService: LedgerService(client: APIClient(
            session: URLSession(configuration: configuration),
            authProvider: auth
        )),
        authProvider: auth,
        connectivity: connectivity,
        hasPendingCategoryWork: hasPendingCategoryWork,
        onBeforeLedgerPush: onBeforeLedgerPush
    )
    let coordinator = SessionTransitionCoordinator(
        repository: repository,
        authProvider: auth,
        connectivity: connectivity,
        sync: engine,
        anonymousSync: engine,
        cleanupMarker: InMemoryLogoutCleanupMarker(),
        onLogoutCleanup: {}
    )
    engine.configureSessionEntry { [weak coordinator] in
        await coordinator?.ensureAnonymousIdentityIfNeeded()
    }
    return DeferralHarness(
        engine: engine,
        repository: repository,
        auth: auth,
        connectivity: connectivity,
        recorder: recorder,
        coordinator: coordinator
    )
}

@MainActor
private final class DeferralCategoryWork {
    var isPending = false
}

@MainActor
private final class DeferralGate {
    private(set) var isHeld = false
    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func hold() async {
        isHeld = true
        guard !isReleased else { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilHeld() async {
        await waitUntil { self.isHeld }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private func waitForDeferralCondition(
    _ condition: @escaping @MainActor () async throws -> Bool
) async rethrows -> Bool {
    for _ in 0 ..< 10000 {
        if try await condition() { return true }
        await Task.yield()
    }
    return false
}

@MainActor
private func configureSuccessfulPush(_ harness: DeferralHarness) {
    SyncPushURLProtocol.handler = { request in
        harness.recorder.record(request)
        return try successResponse(for: request)
    }
}

private func makeDeferralTransaction(clientEntryID: UUID = UUID()) -> LocalTransaction {
    LocalTransaction(
        clientEntryID: clientEntryID,
        amount: Decimal(100),
        currencyCode: "USD",
        categoryID: 10,
        assetID: 20,
        transactionType: .expense,
        transactionDate: "2026-09-15",
        pending: true
    )
}
