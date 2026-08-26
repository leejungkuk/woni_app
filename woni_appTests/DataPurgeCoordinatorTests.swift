//
//  DataPurgeCoordinatorTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct DataPurgeCoordinatorTests {
    @Test("정상 삭제는 마커 영속화 뒤 서버를 지우고 원자 정리 후 push를 재개한다")
    func successfulPurgePreservesCrashSafeOrder() async throws {
        let harness = try await PurgeHarness()

        harness.coordinator.prepare()
        #expect(harness.coordinator.state == .awaitingConfirmation)
        await harness.coordinator.confirm()

        #expect(harness.events.values == [
            .suspend, .mark, .delete, .clearForPurge, .dataCleared, .resume
        ])
        #expect(harness.service.tokens == ["PLACEHOLDER_VALUE"])
        #expect(harness.store.memberID == nil)
        #expect(harness.coordinator.state == .completed)
    }

    @Test("purge는 커스텀 카테고리 메모리를 비우고 지연 refresh를 무효화한다")
    func purgeClearsCustomCategoryMemoryAndInvalidatesRefresh() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 1, type: .expense, name: "기존")
        ])
        let categoryService = PurgeCategoryServiceStub()
        let categoryStore = try CustomCategoryStore(
            service: categoryService,
            cache: cache,
            authProvider: FakeAuthService()
        )
        let harness = try await PurgeHarness(
            onDataCleared: { try? await categoryStore.clear() }
        )
        let refresh = Task { await categoryStore.refresh() }
        await categoryService.waitUntilFetchHeld()

        #expect(!categoryStore.expenseCategories.isEmpty)
        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        #expect(categoryStore.expenseCategories.isEmpty)
        #expect(cache.categories.isEmpty)
        #expect(cache.clearCount == 1)

        categoryService.releaseFetch()
        await refresh.value
        #expect(categoryStore.expenseCategories.isEmpty)
    }

    @Test("onDataCleared 완료 전에는 push 재개와 성공 상태로 진행하지 않는다")
    func finishSuccessAwaitsDataCleared() async throws {
        let dataClearGate = PurgeAsyncGate()
        let harness = try await PurgeHarness(
            onDataCleared: { await dataClearGate.hold() }
        )
        harness.coordinator.prepare()

        let confirm = Task { await harness.coordinator.confirm() }
        await dataClearGate.waitUntilHeld()

        #expect(harness.events.values.last == .dataCleared)
        #expect(!harness.events.values.contains(.resume))
        #expect(harness.coordinator.state == .deleting)

        dataClearGate.release()
        await confirm.value
        #expect(harness.events.values.suffix(2) == [.dataCleared, .resume])
        #expect(harness.coordinator.state == .completed)
    }

    @Test("timeout 뒤 401은 삭제 가능성이 단조 증가해 마커와 suspension을 유지한다")
    func timeoutThenUnauthorizedNeverRollsBack() async throws {
        let harness = try await PurgeHarness(errors: [
            APIError.transport(URLError(.timedOut)),
            APIError.server(code: "UNAUTHORIZED", message: "expired")
        ])

        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        #expect(harness.service.tokens.count == 2)
        #expect(harness.store.memberID == harness.memberID.uuidString)
        #expect(!harness.events.values.contains(.clearMarker))
        #expect(!harness.events.values.contains(.resume))
        #expect(harness.coordinator.state == .completionPending(acknowledged: false))
    }

    @Test("재생성 resume은 마커 존재만으로 possiblyDeleted true에서 시작한다")
    func recreatedResumeStartsPossiblyDeleted() async throws {
        let first = try await PurgeHarness(
            errors: [APIError.transport(URLError(.timedOut))],
            maxAmbiguousRetries: 0
        )
        first.coordinator.prepare()
        await first.coordinator.confirm()
        #expect(first.store.memberID == first.memberID.uuidString)

        let resumed = try await PurgeHarness(
            memberID: first.memberID,
            store: first.store,
            errors: [APIError.server(code: "UNAUTHORIZED", message: "expired")]
        )
        await resumed.coordinator.resumeIfPending()

        #expect(resumed.service.tokens.count == 1)
        #expect(resumed.store.memberID == first.memberID.uuidString)
        #expect(!resumed.events.values.contains(.clearMarker))
        #expect(!resumed.events.values.contains(.resume))
        #expect(resumed.coordinator.state == .completionPending(acknowledged: false))
    }

    @Test("timeout 뒤 429 재시도 소진도 pending 마커를 유지한다")
    func timeoutThenRateLimitExhaustionKeepsPending() async throws {
        let harness = try await PurgeHarness(errors: [
            APIError.transport(URLError(.timedOut)),
            APIError.server(code: "TOO_MANY_REQUESTS", message: "slow"),
            APIError.server(code: "TOO_MANY_REQUESTS", message: "slow"),
            APIError.server(code: "TOO_MANY_REQUESTS", message: "slow")
        ], maxAmbiguousRetries: 3)

        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        #expect(harness.service.tokens.count == 4)
        #expect(harness.store.memberID == harness.memberID.uuidString)
        #expect(!harness.events.values.contains(.resume))
        #expect(harness.coordinator.state == .completionPending(acknowledged: false))
    }

    @Test("INTERNAL_ERROR는 미삭제 확정이 아니라 모호 실패로 분류한다")
    func internalServerErrorIsAmbiguous() async throws {
        let harness = try await PurgeHarness(
            errors: [APIError.server(code: "INTERNAL_ERROR", message: "failed")],
            maxAmbiguousRetries: 0
        )

        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        #expect(harness.store.memberID == harness.memberID.uuidString)
        #expect(!harness.events.values.contains(.clearMarker))
        #expect(harness.coordinator.state == .completionPending(acknowledged: false))
    }

    @Test("200 뒤 로컬 정리 실패는 롤백 없이 마커와 suspension을 유지한다")
    func cleanupFailureAfterSuccessNeverRollsBack() async throws {
        let store = PurgeStoreStub(clearFailuresRemaining: 4)
        let harness = try await PurgeHarness(store: store, maxAmbiguousRetries: 3)

        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        #expect(harness.service.tokens.count == 1)
        #expect(store.clearForPurgeCount == 4)
        #expect(store.memberID == harness.memberID.uuidString)
        #expect(!harness.events.values.contains(.clearMarker))
        #expect(!harness.events.values.contains(.resume))
        #expect(harness.coordinator.state == .completionPending(acknowledged: false))
    }

    @Test("resume 마커 신원이 다르면 DELETE 없이 마커를 포기하고 purge 게이트를 되연다")
    func identityMismatchClearsOnlyMarker() async throws {
        let otherMemberID = UUID()
        let store = PurgeStoreStub(memberID: otherMemberID.uuidString)
        let harness = try await PurgeHarness(store: store)

        await harness.coordinator.resumeIfPending()

        #expect(store.memberID == nil)
        #expect(harness.events.values == [.clearMarker, .resume])
        #expect(harness.service.tokens.isEmpty)
        #expect(harness.coordinator.state == .idle)
    }

    @Test("오프라인 prepare는 확인·서버·저장소 접근 전에 멈춘다")
    func offlinePrepareStopsBeforePurge() async throws {
        let harness = try await PurgeHarness(isOnline: false)

        harness.coordinator.prepare()

        #expect(harness.coordinator.state == .offline)
        #expect(harness.events.values.isEmpty)
        #expect(harness.service.tokens.isEmpty)
        harness.coordinator.dismissOffline()
        #expect(harness.coordinator.state == .idle)
    }

    @Test("pending 안내 acknowledge는 운영 pending을 유지하고 다른 전이를 차단하지 않는다")
    func pendingAcknowledgementDoesNotChangeOperationalState() async throws {
        let harness = try await PurgeHarness(
            errors: [APIError.transport(URLError(.timedOut))],
            maxAmbiguousRetries: 0
        )
        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        #expect(!harness.coordinator.isBlockingOtherEntry)
        harness.coordinator.acknowledgePending()
        #expect(harness.coordinator.state == .completionPending(acknowledged: true))
        #expect(!harness.coordinator.isBlockingOtherEntry)
    }

    @Test("중복 confirm은 같은 purge 전이에 합류해 DELETE를 한 번만 보낸다")
    func duplicateConfirmCoalesces() async throws {
        let gate = PurgeAsyncGate()
        let harness = try await PurgeHarness(gate: gate)
        harness.coordinator.prepare()

        let first = Task { await harness.coordinator.confirm() }
        await gate.waitUntilHeld()
        let second = Task { await harness.coordinator.confirm() }
        await Task.yield()

        #expect(harness.service.tokens.count == 1)
        gate.release()
        await first.value
        await second.value
        #expect(harness.service.tokens.count == 1)
        #expect(harness.coordinator.state == .completed)
    }

    @Test("마커 없는 자동 resume은 사용자가 처리할 완료 상태를 지우지 않는다")
    func resumeWithoutMarkerPreservesCompletion() async throws {
        let harness = try await PurgeHarness()
        harness.coordinator.prepare()
        await harness.coordinator.confirm()
        #expect(harness.coordinator.state == .completed)

        await harness.coordinator.resumeIfPending()

        #expect(harness.coordinator.state == .completed)
    }

    @Test("마커 읽기 일시 실패 뒤 마커 없음이 확인되면 false pending을 해제한다")
    func resumeWithoutMarkerClearsFalsePendingAfterReadFailure() async throws {
        let store = PurgeStoreStub(readFailuresRemaining: 1)
        let harness = try await PurgeHarness(store: store)

        await harness.coordinator.resumeIfPending()
        #expect(harness.coordinator.state == .completionPending(acknowledged: false))

        await harness.coordinator.resumeIfPending()
        #expect(harness.coordinator.state == .idle)
    }

    @Test("마커 없는 resume DB read와 겹친 confirm도 body가 드롭되지 않는다")
    func confirmDuringMarkerReadRunsAfterResumeSettles() async throws {
        let readGate = PurgeAsyncGate()
        let store = PurgeStoreStub(readGate: readGate)
        let harness = try await PurgeHarness(store: store)

        let resume = Task { await harness.coordinator.resumeIfPending() }
        await readGate.waitUntilHeld()
        harness.coordinator.prepare()
        let confirm = Task { await harness.coordinator.confirm() }
        await Task.yield()

        #expect(harness.service.tokens.isEmpty)
        readGate.release()
        await resume.value
        await confirm.value

        #expect(harness.service.tokens.count == 1)
        #expect(harness.coordinator.state == .completed)
    }

    @Test("stale 다른 신원 마커 정리는 동시에 열린 새 확인 상태를 취소하지 않는다")
    func identityMismatchDuringPreparePreservesConfirmation() async throws {
        let readGate = PurgeAsyncGate()
        let store = PurgeStoreStub(memberID: UUID().uuidString, readGate: readGate)
        let harness = try await PurgeHarness(store: store)

        let resume = Task { await harness.coordinator.resumeIfPending() }
        await readGate.waitUntilHeld()
        harness.coordinator.prepare()
        readGate.release()
        await resume.value

        #expect(store.memberID == nil)
        #expect(harness.coordinator.state == .awaitingConfirmation)
    }

    @Test("마커 read 실패도 동시에 열린 새 확인 상태를 덮지 않는다")
    func markerReadFailureDuringPreparePreservesConfirmation() async throws {
        let readGate = PurgeAsyncGate()
        let store = PurgeStoreStub(readGate: readGate, readFailuresRemaining: 1)
        let harness = try await PurgeHarness(store: store)

        let resume = Task { await harness.coordinator.resumeIfPending() }
        await readGate.waitUntilHeld()
        harness.coordinator.prepare()
        readGate.release()
        await resume.value

        #expect(harness.coordinator.state == .awaitingConfirmation)
    }
}

extension DataPurgeCoordinatorTests {
    @Test("미삭제 확정(401·429 소진·미도달 소진)은 마커를 해제하고 push를 되연 뒤 failed로 롤백한다")
    func confirmedUndeletedFailuresRollBack() async throws {
        try await assertRollbackAfterConfirmedFailure(
            errors: [APIError.server(code: "UNAUTHORIZED", message: "expired")],
            maxAmbiguousRetries: 3,
            expectedFires: 1
        )
        try await assertRollbackAfterConfirmedFailure(
            errors: [
                APIError.server(code: "TOO_MANY_REQUESTS", message: "slow"),
                APIError.server(code: "TOO_MANY_REQUESTS", message: "slow")
            ],
            maxAmbiguousRetries: 1,
            expectedFires: 2
        )
        try await assertRollbackAfterConfirmedFailure(
            errors: [APIError.transport(URLError(.notConnectedToInternet))],
            maxAmbiguousRetries: 0,
            expectedFires: 1
        )
    }

    private func assertRollbackAfterConfirmedFailure(
        errors: [Error],
        maxAmbiguousRetries: Int,
        expectedFires: Int
    ) async throws {
        let harness = try await PurgeHarness(
            errors: errors,
            maxAmbiguousRetries: maxAmbiguousRetries
        )
        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        let deletes = Array(
            repeating: PurgeEventRecorder.Event.delete,
            count: expectedFires
        )
        #expect(harness.service.tokens.count == expectedFires)
        #expect(harness.store.memberID == nil)
        #expect(harness.events.values == [.suspend, .mark] + deletes + [.clearMarker, .resume])
        #expect(harness.coordinator.state == .failed)
    }

    @Test("confirm은 확인 시점 신원을 캡처해 큐 대기 중 신원이 바뀌면 DELETE 없이 포기한다")
    func confirmAbortsWhenIdentityChangesBeforeBodyRuns() async throws {
        let readGate = PurgeAsyncGate()
        let store = PurgeStoreStub(readGate: readGate)
        let harness = try await PurgeHarness(store: store)

        let resume = Task { await harness.coordinator.resumeIfPending() }
        await readGate.waitUntilHeld()
        harness.coordinator.prepare()
        let confirm = Task { await harness.coordinator.confirm() }
        await Task.yield()
        try await harness.auth.signOut()
        try await harness.auth.ensureIdentity()
        readGate.release()
        await resume.value
        await confirm.value

        #expect(harness.service.tokens.isEmpty)
        #expect(harness.store.memberID == nil)
        #expect(harness.events.values.isEmpty)
        #expect(harness.coordinator.state == .failed)
    }

    @Test("재시도 사이 신원이 바뀌면 다음 발사를 멈추고 pending을 유지한다")
    func identityChangeBetweenRetriesKeepsPending() async throws {
        let hook = PurgeRetryHook()
        let harness = try await PurgeHarness(
            errors: [APIError.transport(URLError(.timedOut))],
            retryHook: hook
        )
        hook.onRetry = { [auth = harness.auth] in
            try? await auth.signOut()
        }

        harness.coordinator.prepare()
        await harness.coordinator.confirm()

        #expect(harness.service.tokens.count == 1)
        #expect(harness.store.memberID == harness.memberID.uuidString)
        #expect(!harness.events.values.contains(.resume))
        #expect(harness.coordinator.state == .completionPending(acknowledged: false))
    }
}

@MainActor
private struct PurgeHarness {
    let memberID: UUID
    let events: PurgeEventRecorder
    let store: PurgeStoreStub
    let service: PurgeServiceStub
    let auth: FakeAuthService
    let coordinator: DataPurgeCoordinator

    init(
        memberID: UUID = UUID(),
        isOnline: Bool = true,
        store: PurgeStoreStub? = nil,
        errors: [Error] = [],
        gate: PurgeAsyncGate? = nil,
        retryHook: PurgeRetryHook? = nil,
        onDataCleared: (@MainActor () async -> Void)? = nil,
        maxAmbiguousRetries: Int = 3
    ) async throws {
        let events = PurgeEventRecorder()
        let store = store ?? PurgeStoreStub()
        store.events = events
        let service = PurgeServiceStub(errors: errors, events: events, gate: gate)
        let auth = FakeAuthService(makeSignedInUserID: { memberID })
        try await auth.signIn(.google)
        let connectivity = FakeConnectivityMonitor(isOnline: isOnline)
        let sync = PurgeSyncStub(events: events)
        let session = makeTestSessionCoordinator(
            authProvider: auth,
            connectivity: connectivity,
            logoutSync: sync
        )

        self.memberID = memberID
        self.events = events
        self.store = store
        self.service = service
        self.auth = auth
        coordinator = DataPurgeCoordinator(
            session: session,
            purgeSync: sync,
            purgeStore: store,
            ledgerService: service,
            authProvider: auth,
            connectivity: connectivity,
            onDataCleared: {
                events.record(.dataCleared)
                await onDataCleared?()
            },
            retrySleep: { _ in await retryHook?.onRetry?() },
            maxAmbiguousRetries: maxAmbiguousRetries
        )
    }
}

@MainActor
private final class PurgeAsyncGate {
    private var heldContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isHeld = false

    func hold() async {
        isHeld = true
        heldContinuation?.resume()
        heldContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilHeld() async {
        guard !isHeld else { return }
        await withCheckedContinuation { heldContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class PurgeCategoryServiceStub: CustomCategoryServicing {
    private var heldContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isHeld = false

    func fetchCustomCategories(transactionType: String) async throws -> [CategoryDTO] {
        guard transactionType == CatalogTransactionType.expense.rawValue else { return [] }
        isHeld = true
        heldContinuation?.resume()
        heldContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
        return [categoryDTO(id: 2, name: "지연 응답")]
    }

    func createCustomCategory(name _: String, transactionType _: String) async throws -> CategoryDTO {
        throw PurgeTestError.unexpectedCategoryMutation
    }

    func updateCustomCategory(id _: Int, name _: String) async throws -> CategoryDTO {
        throw PurgeTestError.unexpectedCategoryMutation
    }

    func reorderCustomCategories(orderedIDs _: [Int], transactionType _: String) async throws -> [CategoryDTO] {
        throw PurgeTestError.unexpectedCategoryMutation
    }

    func deleteCustomCategory(id _: Int) async throws {
        throw PurgeTestError.unexpectedCategoryMutation
    }

    func waitUntilFetchHeld() async {
        guard !isHeld else { return }
        await withCheckedContinuation { heldContinuation = $0 }
    }

    func releaseFetch() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

/// retrySleep 훅. 재시도 대기 시점에 신원 변경 같은 외부 사건을 주입한다.
@MainActor
private final class PurgeRetryHook {
    var onRetry: (@MainActor () async -> Void)?
}

@MainActor
private final class PurgeEventRecorder {
    enum Event: Equatable {
        case suspend
        case mark
        case delete
        case clearMarker
        case clearForPurge
        case dataCleared
        case resume
        case push
        case logoutSuspend
        case logoutResume
    }

    private(set) var values: [Event] = []

    func record(_ event: Event) {
        values.append(event)
    }
}

@MainActor
private final class PurgeStoreStub: PurgeStateStoring {
    var events: PurgeEventRecorder?
    private(set) var memberID: String?
    private(set) var clearForPurgeCount = 0
    private let readGate: PurgeAsyncGate?
    private var readFailuresRemaining: Int
    private var clearFailuresRemaining: Int

    init(
        memberID: String? = nil,
        readGate: PurgeAsyncGate? = nil,
        readFailuresRemaining: Int = 0,
        clearFailuresRemaining: Int = 0
    ) {
        self.memberID = memberID
        self.readGate = readGate
        self.readFailuresRemaining = readFailuresRemaining
        self.clearFailuresRemaining = clearFailuresRemaining
    }

    func markPurgePending(memberID: String) async throws {
        events?.record(.mark)
        self.memberID = memberID
    }

    func purgePendingMemberID() async throws -> String? {
        await readGate?.hold()
        if readFailuresRemaining > 0 {
            readFailuresRemaining -= 1
            throw PurgeTestError.readFailed
        }
        return memberID
    }

    func clearPurgeMarker() async throws {
        events?.record(.clearMarker)
        memberID = nil
    }

    func clearForPurge() async throws {
        events?.record(.clearForPurge)
        clearForPurgeCount += 1
        if clearFailuresRemaining > 0 {
            clearFailuresRemaining -= 1
            throw PurgeTestError.clearFailed
        }
        memberID = nil
    }
}

@MainActor
private final class PurgeServiceStub: LedgerPurging {
    private var errors: [Error]
    private let events: PurgeEventRecorder
    private let gate: PurgeAsyncGate?
    private(set) var tokens: [String] = []

    init(errors: [Error], events: PurgeEventRecorder, gate: PurgeAsyncGate?) {
        self.errors = errors
        self.events = events
        self.gate = gate
    }

    func deleteAll(accessToken: String) async throws {
        events.record(.delete)
        tokens.append(accessToken)
        await gate?.hold()
        guard !errors.isEmpty else {
            return
        }
        throw errors.removeFirst()
    }
}

@MainActor
private final class PurgeSyncStub: LogoutSyncing, PurgeSyncing {
    private let events: PurgeEventRecorder

    init(events: PurgeEventRecorder) {
        self.events = events
    }

    func pushPending() async {
        events.record(.push)
    }

    func suspendPushForLogout() async {
        events.record(.logoutSuspend)
    }

    func resumePushAfterLogout() {
        events.record(.logoutResume)
    }

    func suspendPushForPurge() async {
        events.record(.suspend)
    }

    func resumePushAfterPurge() async {
        events.record(.resume)
    }
}

private enum PurgeTestError: Error {
    case readFailed
    case clearFailed
    case unexpectedCategoryMutation
}
