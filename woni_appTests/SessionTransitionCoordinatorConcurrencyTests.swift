//
//  SessionTransitionCoordinatorConcurrencyTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct SessionTransitionCoordinatorConcurrencyTests {
    @Test("계정전환이 진행 중이면 foreground 프로브는 전환 완료까지 대기한다")
    func foregroundProbeWaitsForAccountSwitch() async {
        let auth = FakeAuthService()
        let coordinator = makeTestSessionCoordinator(authProvider: auth)
        let gate = AccountSwitchBodyGate()

        let accountSwitch = Task {
            await coordinator.runAccountSwitchTransition {
                await gate.hold()
            }
        }
        await gate.waitUntilHeld()
        #expect(coordinator.isTransitioning)

        let probe = Task { await coordinator.runForegroundSessionProbe() }
        await Task.yield()

        #expect(auth.probeSessionValidityCount == 0)

        gate.release()
        await accountSwitch.value
        _ = await probe.value

        #expect(auth.probeSessionValidityCount == 1)
        #expect(!coordinator.isTransitioning)
    }

    @Test("foreground 프로브가 진행 중이면 계정전환은 프로브 완료까지 대기한다")
    func accountSwitchWaitsForForegroundProbe() async {
        let probeGate = AsyncBooleanGate()
        let auth = FakeAuthService(probeSessionValidityHandler: {
            await probeGate.holdReturningTrue()
        })
        let coordinator = makeTestSessionCoordinator(authProvider: auth)
        var accountSwitchExecutionCount = 0

        let probe = Task { await coordinator.runForegroundSessionProbe() }
        await probeGate.waitUntilHeld()
        #expect(coordinator.isTransitioning)

        let accountSwitch = Task {
            await coordinator.runAccountSwitchTransition {
                accountSwitchExecutionCount += 1
            }
        }
        await Task.yield()

        #expect(accountSwitchExecutionCount == 0)

        probeGate.release()
        _ = await probe.value
        await accountSwitch.value

        #expect(auth.probeSessionValidityCount == 1)
        #expect(accountSwitchExecutionCount == 1)
        #expect(!coordinator.isTransitioning)
    }

    @Test("동시 foreground 프로브 호출자는 같은 무효화 감지 outcome에 합류한다")
    func concurrentForegroundProbesShareOutcome() async {
        let probeGate = AsyncBooleanGate()
        let auth = FakeAuthService(probeSessionValidityHandler: {
            await probeGate.holdReturningFalse()
        })
        let coordinator = makeTestSessionCoordinator(authProvider: auth)

        let first = Task { await coordinator.runForegroundSessionProbe() }
        await probeGate.waitUntilHeld()

        let secondStarted = ContinuationSignal()
        let second = Task {
            secondStarted.signal()
            return await coordinator.runForegroundSessionProbe()
        }
        await secondStarted.wait()
        await Task.yield()

        #expect(auth.probeSessionValidityCount == 1)

        probeGate.release()
        let outcomes = await(first.value, second.value)

        #expect(outcomes.0 == false)
        #expect(outcomes.1 == false)
        #expect(auth.probeSessionValidityCount == 1)
    }

    @Test("같은 종류의 계정전환은 진행 중 작업에 합류하고 본문을 한 번만 실행한다")
    func sameKindAccountSwitchCoalesces() async {
        let auth = FakeAuthService()
        let coordinator = makeTestSessionCoordinator(authProvider: auth)
        let gate = AccountSwitchBodyGate()
        var executionCount = 0

        let first = Task {
            await coordinator.runAccountSwitchTransition {
                executionCount += 1
                await gate.hold()
            }
        }
        await gate.waitUntilHeld()

        let secondStarted = ContinuationSignal()
        let second = Task {
            secondStarted.signal()
            await coordinator.runAccountSwitchTransition {
                executionCount += 1
            }
        }
        await secondStarted.wait()

        #expect(executionCount == 1)

        gate.release()
        await first.value
        await second.value

        #expect(executionCount == 1)
    }

    @Test("같은 종류의 purge 전이는 진행 중 작업에 합류하고 본문을 한 번만 실행한다")
    func sameKindPurgeCoalesces() async {
        let coordinator = makeTestSessionCoordinator(authProvider: FakeAuthService())
        let gate = AccountSwitchBodyGate()
        var executionCount = 0

        let first = Task {
            await coordinator.runPurge {
                executionCount += 1
                await gate.hold()
            }
        }
        await gate.waitUntilHeld()
        let second = Task {
            await coordinator.runPurge {
                executionCount += 1
            }
        }
        await Task.yield()

        #expect(executionCount == 1)
        gate.release()
        await first.value
        await second.value
        #expect(executionCount == 1)
    }

    @Test("purge 진행 중 로그아웃은 purge 완료 뒤에만 실행된다")
    func logoutWaitsForPurge() async {
        let auth = FakeAuthService()
        let coordinator = makeTestSessionCoordinator(authProvider: auth)
        let gate = AccountSwitchBodyGate()
        var events: [String] = []

        let purge = Task {
            await coordinator.runPurge {
                events.append("purge-start")
                await gate.hold()
                events.append("purge-end")
            }
        }
        await gate.waitUntilHeld()
        let logout = Task {
            await coordinator.requestLogout()
            events.append("logout-end")
        }
        await Task.yield()

        #expect(events == ["purge-start"])
        gate.release()
        await purge.value
        await logout.value
        #expect(events == ["purge-start", "purge-end", "logout-end"])
    }

    @Test("로그아웃 진행 중 purge는 로그아웃 완료 뒤에만 실행된다")
    func purgeWaitsForLogout() async {
        let recorder = SessionTransitionEventRecorder()
        let sync = GatedAccountSwitchSync(recorder: recorder, holdsLogoutSuspension: true)
        let coordinator = SessionTransitionCoordinator(
            repository: RecordingLogoutRepository(recorder: recorder),
            authProvider: FakeAuthService(),
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: sync,
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {}
        )
        var purgeDidRun = false

        let logout = Task { await coordinator.requestLogout() }
        await sync.waitUntilLogoutSuspensionAcquired()
        let purge = Task {
            await coordinator.runPurge {
                purgeDidRun = true
            }
        }
        await Task.yield()

        #expect(!purgeDidRun)
        sync.releaseLogoutSuspension()
        await logout.value
        await purge.value
        #expect(purgeDidRun)
    }

    @Test("계정전환 restore가 끝난 뒤에만 로그아웃이 suspension을 획득하고 sign-out·clear한다")
    func logoutWaitsForAccountSwitchRestoreToSettle() async {
        let recorder = SessionTransitionEventRecorder()
        let repository = RecordingLogoutRepository(recorder: recorder)
        let auth = FakeAuthService()
        let sync = GatedAccountSwitchSync(recorder: recorder)
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: sync,
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {}
        )
        let loginViewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: coordinator,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            anonymousAccountDeleter: FakeAnonymousAccountDeleter()
        )

        let accountSwitch = Task { await loginViewModel.signIn(.google) }
        await sync.waitUntilRestoreStarted()

        let logoutStarted = ContinuationSignal()
        let logout = Task {
            logoutStarted.signal()
            await coordinator.requestLogout()
        }
        await logoutStarted.wait()

        #expect(auth.signOutCount == 0)
        #expect(repository.clearCount == 0)
        #expect(sync.suspensionOwnerCount == 1)
        #expect(coordinator.logoutState == .syncing)
        #expect(recorder.events == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreStarted
        ])

        sync.releaseRestore()
        await accountSwitch.value
        await logout.value

        #expect(recorder.events == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreStarted,
            .restoreFinished,
            .finishAccountSwitch,
            .suspendForLogout,
            .clearForLogout,
            .resumeAfterLogout
        ])
        #expect(sync.maximumSuspensionOwnerCount == 1)
        #expect(sync.invalidSuspensionToggleCount == 0)
        #expect(sync.suspensionOwnerCount == 0)
        #expect(auth.signOutCount == 1)
        #expect(repository.clearCount == 1)
        #expect(coordinator.logoutState == .completed)

        // 뷰가 없어 `.task`가 돌지 않으므로 신원 구독을 직접 시작한다.
        let identityObservation = Task { await loginViewModel.observeIdentity() }
        await waitUntil { loginViewModel.identityState == .anonymous }
        #expect(loginViewModel.identityState == .anonymous)
        identityObservation.cancel()
    }

    @Test("restore 실패 뒤 원격 logout이 suspension을 잡으면 close는 logout 완료까지 해제하지 않는다")
    func restoreFailureCloseWaitsForRemoteLogoutCompletion() async {
        let recorder = SessionTransitionEventRecorder()
        let repository = RecordingLogoutRepository(recorder: recorder)
        let auth = FakeAuthService()
        let sync = GatedAccountSwitchSync(
            recorder: recorder,
            restoreFailuresRemaining: 1,
            holdsLogoutSuspension: true
        )
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: sync,
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {}
        )
        let loginViewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: coordinator,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            anonymousAccountDeleter: FakeAnonymousAccountDeleter()
        )

        await loginViewModel.signIn(.google)
        #expect(loginViewModel.flowState == .restoreFailed)
        #expect(sync.suspensionOwnerCount == 1)

        try? await auth.signOut()
        let logout = Task { await coordinator.handleRemoteSessionInvalidation() }
        await sync.waitUntilLogoutSuspensionAcquired()

        var didFinishClose = false
        let close = Task {
            await loginViewModel.finishAfterRestoreFailure()
            didFinishClose = true
        }
        await Task.yield()

        #expect(!didFinishClose)
        #expect(sync.suspensionOwnerCount == 1)
        #expect(loginViewModel.flowState == .restoreFailed)

        sync.releaseLogoutSuspension()
        await logout.value
        await close.value

        #expect(didFinishClose)
        #expect(sync.suspensionOwnerCount == 0)
        #expect(sync.invalidSuspensionToggleCount == 0)
        #expect(recorder.events.suffix(4) == [
            .suspendForLogout,
            .clearForLogout,
            .resumeAfterLogout,
            .resumeAccountSwitch
        ])
        #expect(loginViewModel.flowState == .completed)
    }
}

extension SessionTransitionCoordinatorConcurrencyTests {
    @Test("anonymous 무효화는 계정전환 시작·신원 발급·sync reset·종료 순서로 무음 처리된다")
    func anonymousInvalidationReissuesIdentityInOrderWithoutRestoreOrNotice() async throws {
        let oldUserID = UUID()
        let newUserID = UUID()
        var userIDs = [oldUserID, newUserID]
        let auth = FakeAuthService(makeUserID: { userIDs.removeFirst() })
        try await auth.ensureIdentity()
        let recorder = SessionTransitionEventRecorder()
        let sync = GatedAccountSwitchSync(recorder: recorder, authProvider: auth)
        let repository = RecordingLogoutRepository(recorder: recorder)
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: sync,
            anonymousSync: sync,
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {}
        )

        auth.simulateRemoteInvalidation(kind: .anonymous)
        await waitUntil { sync.finishedAccountSwitchCount == 1 }

        #expect(recorder.events == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .finishAccountSwitch
        ])
        #expect(sync.memberIDsAtBegin == [nil])
        #expect(sync.memberIDsAtReset == [newUserID])
        #expect(sync.memberIDsAtFinish == [newUserID])
        #expect(auth.currentUserID == newUserID)
        #expect(auth.anonymousSignInCount == 2)
        #expect(repository.clearCount == 0)
        #expect(!coordinator.remoteLogoutNotice)
        #expect(!coordinator.isLoggingOut)
    }

    @Test("purge 진행 중 계정전환은 purge 완료 뒤에만 실행된다")
    func accountSwitchWaitsForPurge() async {
        let auth = FakeAuthService()
        let coordinator = makeTestSessionCoordinator(authProvider: auth)
        let gate = AccountSwitchBodyGate()
        var events: [String] = []

        let purge = Task {
            await coordinator.runPurge {
                events.append("purge-start")
                await gate.hold()
                events.append("purge-end")
            }
        }
        await gate.waitUntilHeld()
        let accountSwitch = Task {
            await coordinator.runAccountSwitchTransition {
                events.append("switch-end")
            }
        }
        await Task.yield()

        #expect(events == ["purge-start"])
        gate.release()
        await purge.value
        await accountSwitch.value
        #expect(events == ["purge-start", "purge-end", "switch-end"])
    }

    @Test("계정전환 진행 중 purge는 전환 완료 뒤에만 실행된다")
    func purgeWaitsForAccountSwitch() async {
        let auth = FakeAuthService()
        let coordinator = makeTestSessionCoordinator(authProvider: auth)
        let gate = AccountSwitchBodyGate()
        var events: [String] = []

        let accountSwitch = Task {
            await coordinator.runAccountSwitchTransition {
                events.append("switch-start")
                await gate.hold()
                events.append("switch-end")
            }
        }
        await gate.waitUntilHeld()
        let purge = Task {
            await coordinator.runPurge {
                events.append("purge-end")
            }
        }
        await Task.yield()

        #expect(events == ["switch-start"])
        gate.release()
        await accountSwitch.value
        await purge.value
        #expect(events == ["switch-start", "switch-end", "purge-end"])
    }
}

@MainActor
private final class ContinuationSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isSignaled = false

    func signal() {
        isSignaled = true
        continuation?.resume()
        continuation = nil
    }

    func wait() async {
        guard !isSignaled else {
            return
        }
        await withCheckedContinuation { continuation = $0 }
    }
}

/// 신호가 대기보다 먼저 도착해도 흘리지 않는다. `isHeld`를 세운 뒤 continuation을 등록하기까지
/// 실행이 넘어갈 수 있어, 그 사이에 온 `release()`를 버리면 아무도 깨우지 않는 continuation에
/// 걸려 테스트가 영원히 멈춘다. 등록과 판정을 같은 동기 구간에 두어야 그 창이 사라진다.
@MainActor
private final class AccountSwitchBodyGate {
    private var heldContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isHeld = false
    private var isReleased = false

    func hold() async {
        isHeld = true
        heldContinuation?.resume()
        heldContinuation = nil
        await withCheckedContinuation { continuation in
            if isReleased {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
    }

    func waitUntilHeld() async {
        await withCheckedContinuation { continuation in
            if isHeld {
                continuation.resume()
            } else {
                heldContinuation = continuation
            }
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class AsyncBooleanGate {
    private var heldContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isHeld = false

    func holdReturningFalse() async -> Bool {
        isHeld = true
        heldContinuation?.resume()
        heldContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
        return false
    }

    func holdReturningTrue() async -> Bool {
        isHeld = true
        heldContinuation?.resume()
        heldContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
        return true
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

@MainActor
final class SessionTransitionEventRecorder {
    enum Event: Equatable {
        case beginAccountSwitch
        case resetSyncStateForAccountSwitch
        case restoreStarted
        case restoreFinished
        case finishAccountSwitch
        case suspendForLogout
        case clearForLogout
        case resumeAfterLogout
        case resumeAccountSwitch
    }

    private(set) var events: [Event] = []

    func record(_ event: Event) {
        events.append(event)
    }
}

@MainActor
final class RecordingLogoutRepository: LogoutDataProviding {
    private let recorder: SessionTransitionEventRecorder
    private(set) var clearCount = 0

    init(recorder: SessionTransitionEventRecorder) {
        self.recorder = recorder
    }

    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        false
    }

    func clearForLogout(force _: Bool) async throws {
        clearCount += 1
        recorder.record(.clearForLogout)
    }
}

@MainActor
final class GatedAccountSwitchSync: LoginSyncing, LogoutSyncing {
    private let recorder: SessionTransitionEventRecorder
    private let authProvider: (any AuthProviding)?
    private var restoreStartedContinuation: CheckedContinuation<Void, Never>?
    private var restoreReleaseContinuation: CheckedContinuation<Void, Never>?
    private var didStartRestore = false
    private var restoreFailuresRemaining: Int
    private let holdsLogoutSuspension: Bool
    private var logoutSuspensionStartedContinuation: CheckedContinuation<Void, Never>?
    private var logoutSuspensionReleaseContinuation: CheckedContinuation<Void, Never>?
    private var didAcquireLogoutSuspension = false

    private(set) var suspensionOwnerCount = 0
    private(set) var maximumSuspensionOwnerCount = 0
    private(set) var invalidSuspensionToggleCount = 0
    private(set) var memberIDsAtBegin: [UUID?] = []
    private(set) var memberIDsAtReset: [UUID?] = []
    private(set) var memberIDsAtFinish: [UUID?] = []
    private(set) var finishedAccountSwitchCount = 0

    init(
        recorder: SessionTransitionEventRecorder,
        restoreFailuresRemaining: Int = 0,
        holdsLogoutSuspension: Bool = false,
        authProvider: (any AuthProviding)? = nil
    ) {
        self.recorder = recorder
        self.restoreFailuresRemaining = restoreFailuresRemaining
        self.holdsLogoutSuspension = holdsLogoutSuspension
        self.authProvider = authProvider
    }

    func beginAccountSwitch() async throws {
        acquireSuspension()
        recorder.record(.beginAccountSwitch)
        memberIDsAtBegin.append(authProvider?.currentUserID)
    }

    func finishAccountSwitch(expectedMemberID _: UUID) async -> Bool {
        recorder.record(.finishAccountSwitch)
        memberIDsAtFinish.append(authProvider?.currentUserID)
        finishedAccountSwitchCount += 1
        releaseSuspension()
        return true
    }

    func resumeAccountSwitch(expectedMemberID _: UUID?) -> Bool {
        recorder.record(.resumeAccountSwitch)
        releaseSuspensionIfNeeded()
        return true
    }

    func pushPending() async {}

    func resetSyncStateForAccountSwitch() async throws {
        recorder.record(.resetSyncStateForAccountSwitch)
        memberIDsAtReset.append(authProvider?.currentUserID)
    }

    func hasPendingPush() async throws -> Bool {
        false
    }

    func restoreAll() async throws {
        didStartRestore = true
        recorder.record(.restoreStarted)
        restoreStartedContinuation?.resume()
        restoreStartedContinuation = nil
        if restoreFailuresRemaining > 0 {
            restoreFailuresRemaining -= 1
            throw GatedAccountSwitchSyncError.restoreFailed
        }
        await withCheckedContinuation { restoreReleaseContinuation = $0 }
        recorder.record(.restoreFinished)
    }

    func suspendPushForLogout() async {
        if suspensionOwnerCount == 0 {
            acquireSuspension()
        }
        recorder.record(.suspendForLogout)
        didAcquireLogoutSuspension = true
        logoutSuspensionStartedContinuation?.resume()
        logoutSuspensionStartedContinuation = nil
        if holdsLogoutSuspension {
            await withCheckedContinuation { logoutSuspensionReleaseContinuation = $0 }
        }
    }

    func resumePushAfterLogout() {
        recorder.record(.resumeAfterLogout)
        releaseSuspension()
    }

    func waitUntilRestoreStarted() async {
        guard !didStartRestore else {
            return
        }
        await withCheckedContinuation { restoreStartedContinuation = $0 }
    }

    func releaseRestore() {
        restoreReleaseContinuation?.resume()
        restoreReleaseContinuation = nil
    }

    func waitUntilLogoutSuspensionAcquired() async {
        guard !didAcquireLogoutSuspension else {
            return
        }
        await withCheckedContinuation { logoutSuspensionStartedContinuation = $0 }
    }

    func releaseLogoutSuspension() {
        logoutSuspensionReleaseContinuation?.resume()
        logoutSuspensionReleaseContinuation = nil
    }

    private func acquireSuspension() {
        if suspensionOwnerCount != 0 {
            invalidSuspensionToggleCount += 1
        }
        suspensionOwnerCount += 1
        maximumSuspensionOwnerCount = max(maximumSuspensionOwnerCount, suspensionOwnerCount)
    }

    private func releaseSuspension() {
        if suspensionOwnerCount != 1 {
            invalidSuspensionToggleCount += 1
        }
        suspensionOwnerCount = max(0, suspensionOwnerCount - 1)
    }

    private func releaseSuspensionIfNeeded() {
        if suspensionOwnerCount > 0 {
            releaseSuspension()
        }
    }
}

private enum GatedAccountSwitchSyncError: Error {
    case restoreFailed
}
