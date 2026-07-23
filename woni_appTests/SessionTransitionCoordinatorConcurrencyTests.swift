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
        await probe.value

        #expect(auth.probeSessionValidityCount == 1)
        #expect(!coordinator.isTransitioning)
    }

    @Test("foreground 프로브가 진행 중이면 계정전환은 프로브 완료까지 대기한다")
    func accountSwitchWaitsForForegroundProbe() async {
        let probeGate = AsyncBooleanGate()
        let auth = FakeAuthService(probeSessionValidityHandler: {
            await probeGate.holdReturningFalse()
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
        await probe.value
        await accountSwitch.value

        #expect(auth.probeSessionValidityCount == 1)
        #expect(accountSwitchExecutionCount == 1)
        #expect(!coordinator.isTransitioning)
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

    @Test("계정전환 restore가 끝난 뒤에만 로그아웃이 suspension을 획득하고 sign-out·clear한다")
    func logoutWaitsForAccountSwitchRestoreToSettle() async {
        let recorder = SessionTransitionEventRecorder()
        let repository = RecordingLogoutRepository(recorder: recorder)
        let auth = FakeAuthService(linkIdentityError: AuthServiceError.identityAlreadyExists)
        let sync = GatedAccountSwitchSync(recorder: recorder)
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: sync,
            cleanupMarker: InMemoryLogoutCleanupMarker()
        )
        let loginViewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: coordinator,
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await loginViewModel.linkIdentity(.google)
        #expect(loginViewModel.flowState == .awaitingSignInConfirmation(.google))

        let accountSwitch = Task { await loginViewModel.confirmSignIn() }
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
        #expect(recorder.events == [.beginAccountSwitch, .restoreStarted])

        sync.releaseRestore()
        await accountSwitch.value
        await logout.value

        #expect(recorder.events == [
            .beginAccountSwitch,
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
        #expect(loginViewModel.identityState == .anonymous)
    }

    @Test("restore 실패 뒤 원격 logout이 suspension을 잡으면 close는 logout 완료까지 해제하지 않는다")
    func restoreFailureCloseWaitsForRemoteLogoutCompletion() async {
        let recorder = SessionTransitionEventRecorder()
        let repository = RecordingLogoutRepository(recorder: recorder)
        let auth = FakeAuthService(linkIdentityError: AuthServiceError.identityAlreadyExists)
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
            cleanupMarker: InMemoryLogoutCleanupMarker()
        )
        let loginViewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: coordinator,
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await loginViewModel.linkIdentity(.google)
        await loginViewModel.confirmSignIn()
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

@MainActor
private final class AccountSwitchBodyGate {
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
private final class SessionTransitionEventRecorder {
    enum Event: Equatable {
        case beginAccountSwitch
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
private final class RecordingLogoutRepository: LogoutDataProviding {
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
private final class GatedAccountSwitchSync: LoginSyncing, LogoutSyncing {
    private let recorder: SessionTransitionEventRecorder
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

    init(
        recorder: SessionTransitionEventRecorder,
        restoreFailuresRemaining: Int = 0,
        holdsLogoutSuspension: Bool = false
    ) {
        self.recorder = recorder
        self.restoreFailuresRemaining = restoreFailuresRemaining
        self.holdsLogoutSuspension = holdsLogoutSuspension
    }

    func beginAccountSwitch() async {
        acquireSuspension()
        recorder.record(.beginAccountSwitch)
    }

    func finishAccountSwitch(expectedMemberID _: UUID) async -> Bool {
        recorder.record(.finishAccountSwitch)
        releaseSuspension()
        return true
    }

    func resumeAccountSwitch(expectedMemberID _: UUID?) -> Bool {
        recorder.record(.resumeAccountSwitch)
        releaseSuspensionIfNeeded()
        return true
    }

    func pushPending() async {}

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
