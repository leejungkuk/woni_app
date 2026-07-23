//
//  SessionTransitionCoordinatorRemoteLogoutTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct SessionTransitionCoordinatorRemoteLogoutTests {
    @Test("원격 무효화 신호는 로컬을 정리하고 새 익명 신원과 안내를 만든다")
    func remoteInvalidationCleansUpAndCreatesAnonymousIdentityWithNotice() async throws {
        let repository = RemoteLogoutRepository()
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let sync = RemoteLogoutSync()
        let marker = InMemoryLogoutCleanupMarker()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: sync,
            cleanupMarker: marker
        )

        auth.simulateRemoteInvalidation()
        await waitUntil { coordinator.remoteLogoutNotice }

        #expect(repository.clearAttempts == 1)
        #expect(repository.forceArguments == [true])
        #expect(auth.signOutCount == 0)
        #expect(auth.isAnonymous)
        #expect(auth.anonymousSignInCount == 1)
        #expect(sync.calls == [.suspendForLogout, .resumeAfterLogout])
        #expect(!marker.isPending)
        #expect(coordinator.logoutState == .idle)

        coordinator.acknowledgeRemoteLogoutNotice()
        #expect(!coordinator.remoteLogoutNotice)
    }

    @Test("구독 전에 버퍼된 원격 무효화 신호도 코디네이터가 소비한다")
    func consumesRemoteInvalidationBufferedBeforeCoordinatorInit() async throws {
        let repository = RemoteLogoutRepository()
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        auth.simulateRemoteInvalidation()

        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: RemoteLogoutSync(),
            cleanupMarker: InMemoryLogoutCleanupMarker()
        )

        await waitUntil { coordinator.remoteLogoutNotice }

        #expect(repository.clearAttempts == 1)
        #expect(auth.isAnonymous)
    }

    @Test("원격 무효화 3분기 가드는 member와 anonymous를 건너뛰고 nil 세션만 정리한다")
    func remoteInvalidationThreeWayGuard() async throws {
        let memberRepository = RemoteLogoutRepository()
        let memberAuth = FakeAuthService()
        try await memberAuth.signIn(.google)
        let memberCoordinator = makeRemoteCoordinator(
            repository: memberRepository,
            auth: memberAuth
        )

        await memberCoordinator.handleRemoteSessionInvalidation()

        #expect(memberRepository.clearAttempts == 0)
        #expect(!memberCoordinator.remoteLogoutNotice)
        #expect(!memberAuth.isAnonymous)

        let anonymousRepository = RemoteLogoutRepository()
        let anonymousAuth = FakeAuthService()
        try await anonymousAuth.ensureIdentity()
        let anonymousCoordinator = makeRemoteCoordinator(
            repository: anonymousRepository,
            auth: anonymousAuth
        )

        await anonymousCoordinator.handleRemoteSessionInvalidation()

        #expect(anonymousRepository.clearAttempts == 0)
        #expect(!anonymousCoordinator.remoteLogoutNotice)
        #expect(anonymousAuth.isAnonymous)

        let missingRepository = RemoteLogoutRepository()
        let missingAuth = FakeAuthService()
        let missingCoordinator = makeRemoteCoordinator(
            repository: missingRepository,
            auth: missingAuth
        )

        missingAuth.simulateRemoteInvalidation()
        await waitUntil { missingCoordinator.remoteLogoutNotice }

        #expect(missingRepository.clearAttempts == 1)
        #expect(missingAuth.isAnonymous)
    }

    @Test("사용자 로그아웃 직후 도착한 지연 신호는 안내나 재정리를 만들지 않는다")
    func delayedInvalidationAfterUserLogoutDoesNotShowNotice() async throws {
        let repository = RemoteLogoutRepository()
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let coordinator = makeRemoteCoordinator(repository: repository, auth: auth)

        await coordinator.requestLogout()
        #expect(auth.isAnonymous)
        #expect(repository.clearAttempts == 1)

        auth.simulateRemoteInvalidation(removingCurrentSession: false)
        await settleAsyncStreamConsumer()

        #expect(repository.clearAttempts == 1)
        #expect(!coordinator.remoteLogoutNotice)
    }

    @Test("사용자 로그아웃 중 도착한 무효화는 진행 중 로그아웃에 합류해 무안내로 끝난다")
    func invalidationDuringUserLogoutJoinsWithoutNotice() async throws {
        let repository = RemoteLogoutRepository(holdsClear: true)
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let coordinator = makeRemoteCoordinator(repository: repository, auth: auth)

        let logout = Task { await coordinator.requestLogout() }
        await repository.waitUntilClearStarted()

        auth.simulateRemoteInvalidation(removingCurrentSession: false)
        await Task.yield()
        repository.releaseClear()
        await logout.value
        await settleAsyncStreamConsumer()

        #expect(repository.clearAttempts == 1)
        #expect(!coordinator.remoteLogoutNotice)
        #expect(coordinator.logoutState == .completed)
        #expect(auth.isAnonymous)
    }

    @Test("원격 정리 중 시작한 사용자 로그아웃은 같은 작업에 합류하고 완료 상태를 유지한다")
    func userLogoutDuringRemoteCleanupJoinsWithoutDuplicateClear() async throws {
        let repository = RemoteLogoutRepository(holdsClear: true)
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let coordinator = makeRemoteCoordinator(repository: repository, auth: auth)

        auth.simulateRemoteInvalidation()
        await repository.waitUntilClearStarted()

        let logout = Task { await coordinator.requestLogout() }
        await Task.yield()
        repository.releaseClear()
        await logout.value

        #expect(repository.clearAttempts == 1)
        #expect(coordinator.remoteLogoutNotice)
        #expect(coordinator.logoutState == .completed)
        #expect(auth.isAnonymous)
    }

    @Test("중복 무효화 신호는 익명 세션에서 무시되어 재정리와 재안내가 없다")
    func duplicateRemoteInvalidationIsIdempotent() async throws {
        let repository = RemoteLogoutRepository()
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let coordinator = makeRemoteCoordinator(repository: repository, auth: auth)

        auth.simulateRemoteInvalidation()
        await waitUntil { coordinator.remoteLogoutNotice }
        coordinator.acknowledgeRemoteLogoutNotice()

        auth.simulateRemoteInvalidation(removingCurrentSession: false)
        await settleAsyncStreamConsumer()

        #expect(repository.clearAttempts == 1)
        #expect(auth.anonymousSignInCount == 1)
        #expect(!coordinator.remoteLogoutNotice)
    }

    @Test("원격 무효화의 local clear 실패는 공용 cleanup-required와 pending marker를 유지한다")
    func remoteClearFailureRequiresSharedCleanup() async throws {
        let repository = RemoteLogoutRepository(clearFailuresRemaining: 1)
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let marker = InMemoryLogoutCleanupMarker()
        let sync = RemoteLogoutSync()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: sync,
            cleanupMarker: marker
        )

        auth.simulateRemoteInvalidation()
        await waitUntil { coordinator.needsCleanup }

        #expect(coordinator.remoteLogoutNotice)
        #expect(coordinator.logoutState == .cleanupRequired)
        #expect(coordinator.isLoginBlocked)
        #expect(marker.isPending)
        #expect(sync.calls == [.suspendForLogout])
    }

    @Test("원격 무효화의 익명 신원 발급 실패는 정리를 완료하고 사용자 로그아웃 실패 상태를 쓰지 않는다")
    func remoteEnsureIdentityFailureLeavesCleanupSafeAndUnblocked() async throws {
        let repository = RemoteLogoutRepository()
        let auth = FakeAuthService(ensureIdentityFailuresRemaining: 1)
        try await auth.signIn(.google)
        let marker = InMemoryLogoutCleanupMarker()
        let sync = RemoteLogoutSync()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: sync,
            cleanupMarker: marker
        )

        auth.simulateRemoteInvalidation()
        await waitUntil { coordinator.remoteLogoutNotice }

        #expect(repository.clearAttempts == 1)
        #expect(auth.currentUserID == nil)
        #expect(coordinator.logoutState == .idle)
        #expect(!coordinator.isLoginBlocked)
        #expect(!marker.isPending)
        #expect(sync.calls == [.suspendForLogout, .resumeAfterLogout])
    }

    @Test("대기 중 원격 무효화 task에 coalesce된 사용자 로그아웃은 stale member skip 후 .syncing에 고착되지 않는다")
    func coalescedUserLogoutIsNotStuckAfterStaleRemoteSkip() async throws {
        let repository = RemoteLogoutRepository()
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let coordinator = makeRemoteCoordinator(repository: repository, auth: auth)
        let gate = HoldableBodyGate()

        // 계정전환이 body를 hold → activeKind = .accountSwitch
        let accountSwitch = Task {
            await coordinator.runAccountSwitchTransition { await gate.hold() }
        }
        await gate.waitUntilHeld()

        // 원격 무효화 처리를 계정전환 뒤에 먼저 큐잉한다. remote를 user보다 먼저 생성하고 settle로
        // 충분히 양보해, remote가 activeKind=.logout을 설치하고 계정전환 완료를 기다리는 지점까지
        // 진행하게 만든다(이 구간 remote는 유일한 ready task라 block에 확실히 도달).
        let remoteInvalidation = Task { await coordinator.handleRemoteSessionInvalidation() }
        await settleAsyncStreamConsumer()

        // 사용자 로그아웃 → .syncing 설정 직후 대기 중인 원격 .logout task로 coalesce(사용자 body 드롭).
        // .syncing 관찰로 user가 진입해 coalesce까지 도달했음을 결정적으로 확인한 뒤 gate를 연다.
        let userLogout = Task { await coordinator.requestLogout() }
        await waitUntil { coordinator.logoutState == .syncing }

        gate.release()
        await accountSwitch.value
        await remoteInvalidation.value
        await userLogout.value

        // 원격 body는 member 세션이라 stale skip; coalesce된 사용자 로그아웃의 .syncing이 .idle로
        // 해제돼야 한다. 회귀(미수정) 시 여기서 .syncing 고착 → isLoginBlocked 영구 true.
        #expect(coordinator.logoutState == .idle)
        #expect(!coordinator.isLoginBlocked)
        #expect(repository.clearAttempts == 0)
        #expect(!coordinator.remoteLogoutNotice)

        // 로그아웃 기능이 계속 동작한다(회귀 시엔 진입 가드에 막혀 영구 무동작).
        await coordinator.requestLogout()
        #expect(auth.isAnonymous)
        #expect(coordinator.logoutState == .completed)
    }

    @Test("원격 clear 실패로 남은 cleanup-required는 재신호의 cleanup 성공으로 해제된다")
    func remoteReCleanupSuccessClearsStuckCleanupRequired() async throws {
        let repository = RemoteLogoutRepository(clearFailuresRemaining: 1)
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let marker = InMemoryLogoutCleanupMarker()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: RemoteLogoutSync(),
            cleanupMarker: marker
        )

        auth.simulateRemoteInvalidation()
        await waitUntil { coordinator.needsCleanup }
        #expect(coordinator.logoutState == .cleanupRequired)
        #expect(marker.isPending)

        auth.simulateRemoteInvalidation()
        await waitUntil { !coordinator.isLoginBlocked }

        #expect(repository.clearAttempts == 2)
        #expect(coordinator.logoutState == .idle)
        #expect(!marker.isPending)
        #expect(auth.isAnonymous)
    }
}

@MainActor
private func makeRemoteCoordinator(
    repository: RemoteLogoutRepository,
    auth: FakeAuthService
) -> SessionTransitionCoordinator {
    SessionTransitionCoordinator(
        repository: repository,
        authProvider: auth,
        connectivity: FakeConnectivityMonitor(isOnline: true),
        sync: RemoteLogoutSync(),
        cleanupMarker: InMemoryLogoutCleanupMarker()
    )
}

@MainActor
private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
    for _ in 0 ..< 1000 {
        if condition() {
            return
        }
        await Task.yield()
    }
}

@MainActor
private func settleAsyncStreamConsumer() async {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
}

@MainActor
private final class HoldableBodyGate {
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
        guard !isHeld else {
            return
        }
        await withCheckedContinuation { heldContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private enum RemoteLogoutRepositoryError: Error {
    case programmedClearFailure
}

@MainActor
private final class RemoteLogoutRepository: LogoutDataProviding {
    private var clearFailuresRemaining: Int
    private let holdsClear: Bool
    private var clearStartedContinuation: CheckedContinuation<Void, Never>?
    private var clearReleaseContinuation: CheckedContinuation<Void, Never>?
    private var didStartClear = false

    private(set) var clearAttempts = 0
    private(set) var forceArguments: [Bool] = []

    init(clearFailuresRemaining: Int = 0, holdsClear: Bool = false) {
        self.clearFailuresRemaining = clearFailuresRemaining
        self.holdsClear = holdsClear
    }

    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        false
    }

    func clearForLogout(force: Bool) async throws {
        clearAttempts += 1
        forceArguments.append(force)
        didStartClear = true
        clearStartedContinuation?.resume()
        clearStartedContinuation = nil
        if holdsClear {
            await withCheckedContinuation { clearReleaseContinuation = $0 }
        }
        if clearFailuresRemaining > 0 {
            clearFailuresRemaining -= 1
            throw RemoteLogoutRepositoryError.programmedClearFailure
        }
    }

    func waitUntilClearStarted() async {
        guard !didStartClear else {
            return
        }
        await withCheckedContinuation { clearStartedContinuation = $0 }
    }

    func releaseClear() {
        clearReleaseContinuation?.resume()
        clearReleaseContinuation = nil
    }
}

@MainActor
private final class RemoteLogoutSync: LogoutSyncing {
    enum Call: Equatable {
        case suspendForLogout
        case resumeAfterLogout
    }

    private(set) var calls: [Call] = []

    func pushPending() async {}

    func suspendPushForLogout() async {
        calls.append(.suspendForLogout)
    }

    func resumePushAfterLogout() {
        calls.append(.resumeAfterLogout)
    }
}
