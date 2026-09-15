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

    @Test("신원이 없을 때의 탈퇴는 서버 호출 없이 완료된다")
    func withdrawalWithoutIdentityCompletesWithoutServerRequest() async {
        let auth = FakeAuthService()
        let repository = DeferralWithdrawalRepository()
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let service = DeferralWithdrawalService()
        let session = makeTestSessionCoordinator(
            authProvider: auth,
            repository: repository,
            connectivity: connectivity
        )
        let coordinator = WithdrawalCoordinator(
            session: session,
            authProvider: auth,
            connectivity: connectivity,
            withdrawalService: service
        )

        coordinator.prepareWithdrawal()
        await coordinator.confirmWithdrawal()

        #expect(service.codes.isEmpty)
        #expect(repository.forceArguments == [true])
        #expect(coordinator.state == .completed(appleUnlinkPending: false))
        #expect(auth.anonymousSignInCount == 0)
    }

    @Test("신원이 없으면 오프라인에서도 탈퇴가 진행된다")
    func withdrawalWithoutIdentityProceedsOffline() async {
        let auth = FakeAuthService()
        let repository = DeferralWithdrawalRepository()
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let service = DeferralWithdrawalService()
        let session = makeTestSessionCoordinator(
            authProvider: auth,
            repository: repository,
            connectivity: connectivity
        )
        let coordinator = WithdrawalCoordinator(
            session: session,
            authProvider: auth,
            connectivity: connectivity,
            withdrawalService: service
        )

        coordinator.prepareWithdrawal()
        #expect(coordinator.state == .awaitingConfirmation(isAppleLinked: false))
        await coordinator.confirmWithdrawal()

        #expect(service.codes.isEmpty)
        #expect(repository.forceArguments == [true])
        #expect(coordinator.state == .completed(appleUnlinkPending: false))
    }

    @Test("신원 없이 시작한 탈퇴도 확인 전에 신원이 생기면 서버 탈퇴를 요청한다")
    func withdrawalStartedWithoutIdentityUsesIdentityIssuedBeforeConfirmation() async throws {
        let harness = try makeIssuanceLoginHarness(sessionValue: "PLACEHOLDER_SESSION_VALUE")
        SyncPushURLProtocol.handler = { request in
            try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }
        try await harness.repository.insert(makeDeferralTransaction())

        var pushFinished = false
        let push = Task { @MainActor in
            await harness.engine.pushPending()
            pushFinished = true
        }
        let issuanceIsHeld = await waitForDeferralCondition { harness.identityGate.isHeld }
        #expect(issuanceIsHeld)

        harness.withdrawalCoordinator.prepareWithdrawal()
        #expect(
            harness.withdrawalCoordinator.state
                == .awaitingConfirmation(isAppleLinked: false)
        )
        var withdrawalStarted = false
        var withdrawalFinished = false
        let withdrawal = Task { @MainActor in
            withdrawalStarted = true
            await harness.withdrawalCoordinator.confirmWithdrawal()
            withdrawalFinished = true
        }
        let didStartWithdrawal = await waitForDeferralCondition { withdrawalStarted }
        #expect(didStartWithdrawal)

        harness.identityGate.release()
        let didComplete = await waitForDeferralCondition { pushFinished && withdrawalFinished }

        #expect(didComplete)
        if pushFinished { await push.value }
        if withdrawalFinished { await withdrawal.value }
        #expect(harness.withdrawalService.codes == [nil])
        #expect(
            harness.withdrawalCoordinator.state
                == .completed(appleUnlinkPending: false)
        )
    }

    @Test("회원으로 시작한 탈퇴가 확인 전에 세션을 잃으면 실패로 끝난다")
    func withdrawalStartedAsMemberFailsWhenSessionDisappearsBeforeConfirmation() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let repository = DeferralWithdrawalRepository()
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let service = DeferralWithdrawalService()
        let session = makeTestSessionCoordinator(
            authProvider: auth,
            repository: repository,
            connectivity: connectivity
        )
        let coordinator = WithdrawalCoordinator(
            session: session,
            authProvider: auth,
            connectivity: connectivity,
            withdrawalService: service
        )

        coordinator.prepareWithdrawal()
        #expect(coordinator.state == .awaitingConfirmation(isAppleLinked: false))
        try await auth.signOut()
        await coordinator.confirmWithdrawal()

        #expect(service.codes.isEmpty)
        #expect(repository.forceArguments.isEmpty)
        #expect(coordinator.state == .failed)
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

    @Test("발급 도중 시작된 로그인도 그 익명 계정을 정리 대상으로 잡는다")
    func loginDuringIdentityIssuanceCapturesAnonymousAccount() async throws {
        let anonymousSessionValue = "PLACEHOLDER_ANONYMOUS_SESSION_VALUE"
        let harness = try makeIssuanceLoginHarness(sessionValue: anonymousSessionValue)
        SyncPushURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/ledgers/restore" {
                return try response(
                    for: request,
                    data: successEnvelope(
                        dataJSON: restorePageJSON(entries: [], nextCursor: nil, hasNext: false)
                    )
                )
            }
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }
        try await harness.repository.insert(makeDeferralTransaction())

        var pushFinished = false
        let push = Task { @MainActor in
            await harness.engine.pushPending()
            pushFinished = true
        }
        let issuanceIsHeld = await waitForDeferralCondition { harness.identityGate.isHeld }
        #expect(issuanceIsHeld)

        var loginStarted = false
        var loginFinished = false
        let login = Task { @MainActor in
            loginStarted = true
            await harness.loginViewModel.signIn(.google)
            loginFinished = true
        }
        let didStartLogin = await waitForDeferralCondition { loginStarted }
        #expect(didStartLogin)
        for _ in 0 ..< 100 {
            await Task.yield()
        }
        #expect(harness.loginViewModel.flowState == .idle)

        harness.identityGate.release()
        let didComplete = await waitForDeferralCondition { pushFinished && loginFinished }

        #expect(didComplete)
        if pushFinished { await push.value }
        if loginFinished { await login.value }
        #expect(harness.loginViewModel.flowState == .completed)
        #expect(harness.deleter.deletedAccessTokens == [anonymousSessionValue])
    }
}

@MainActor
private struct IssuanceLoginHarness {
    let engine: SyncEngine
    let repository: TransactionRepository
    let identityGate: DeferralGate
    let loginViewModel: LoginViewModel
    let deleter: FakeAnonymousAccountDeleter
    let withdrawalCoordinator: WithdrawalCoordinator
    let withdrawalService: DeferralWithdrawalService
}

@MainActor
private func makeIssuanceLoginHarness(sessionValue: String) throws -> IssuanceLoginHarness {
    let anonymousUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let memberUserID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    let underlyingAuth = FakeAuthService(
        makeUserID: { anonymousUserID },
        makeSignedInUserID: { memberUserID },
        initialValue: sessionValue,
        refreshedValue: sessionValue
    )
    let identityGate = DeferralGate()
    let auth = GatedDeferralAuth(underlying: underlyingAuth, identityGate: identityGate)
    let connectivity = FakeConnectivityMonitor(isOnline: true)
    let repository = try TransactionRepository(database: AppDatabase.inMemory())
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyncPushURLProtocol.self]
    let engine = SyncEngine(
        repository: repository,
        ledgerService: LedgerService(client: APIClient(
            session: URLSession(configuration: configuration),
            authProvider: auth
        )),
        authProvider: auth,
        connectivity: connectivity
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
    let deleter = FakeAnonymousAccountDeleter()
    let loginViewModel = LoginViewModel(
        authProvider: auth,
        sync: engine,
        coordinator: coordinator,
        connectivity: connectivity,
        anonymousAccountDeleter: deleter
    )
    let withdrawalService = DeferralWithdrawalService()
    let withdrawalCoordinator = WithdrawalCoordinator(
        session: coordinator,
        authProvider: auth,
        connectivity: connectivity,
        withdrawalService: withdrawalService
    )
    return IssuanceLoginHarness(
        engine: engine,
        repository: repository,
        identityGate: identityGate,
        loginViewModel: loginViewModel,
        deleter: deleter,
        withdrawalCoordinator: withdrawalCoordinator,
        withdrawalService: withdrawalService
    )
}

@MainActor
private final class DeferralWithdrawalRepository: LogoutDataProviding {
    private(set) var forceArguments: [Bool] = []

    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        false
    }

    func clearForLogout(force: Bool) async throws {
        forceArguments.append(force)
    }
}

@MainActor
private final class DeferralWithdrawalService: WithdrawalRequesting {
    private(set) var codes: [String?] = []

    func withdraw(appleAuthorizationCode: String?) async throws {
        codes.append(appleAuthorizationCode)
    }
}

@MainActor
private final class GatedDeferralAuth: AuthProviding {
    private let underlying: FakeAuthService
    private let identityGate: DeferralGate

    init(underlying: FakeAuthService, identityGate: DeferralGate) {
        self.underlying = underlying
        self.identityGate = identityGate
    }

    func ensureIdentity() async throws {
        await identityGate.hold()
        try await underlying.ensureIdentity()
    }

    func currentAccessToken() -> String? {
        underlying.currentAccessToken()
    }

    func refreshedAccessToken() async throws -> String? {
        try await underlying.refreshedAccessToken()
    }

    func revokeOtherSessions() async throws {
        try await underlying.revokeOtherSessions()
    }

    func probeSessionValidity() async -> Bool {
        await underlying.probeSessionValidity()
    }

    func requestAppleAuthorizationCode() async throws -> String? {
        try await underlying.requestAppleAuthorizationCode()
    }

    func signIn(_ provider: OAuthProvider) async throws {
        try await underlying.signIn(provider)
    }

    func signOut() async throws {
        try await underlying.signOut()
    }

    var sessionInvalidated: AsyncStream<SessionInvalidation> {
        underlying.sessionInvalidated
    }

    var identityDidChange: AsyncStream<Void> {
        underlying.identityDidChange
    }

    var currentUserID: UUID? {
        underlying.currentUserID
    }

    var currentUserEmail: String? {
        underlying.currentUserEmail
    }

    var isAnonymous: Bool {
        underlying.isAnonymous
    }

    var hasAppleIdentity: Bool {
        underlying.hasAppleIdentity
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
