//
//  SettingsViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct SettingsViewModelTests {
    @Test("오프라인 미동기 항목은 로그아웃을 멈추고 강행 확인을 요구한다")
    func offlinePendingEntryRequiresConfirmationWithoutDataLoss() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction())
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let sync = FakeLogoutSync()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: sync,
            cleanupMarker: InMemoryLogoutCleanupMarker()
        )

        await coordinator.requestLogout()

        #expect(coordinator.logoutState == .awaitingUnsyncedConfirmation)
        #expect(auth.signOutCount == 0)
        #expect(sync.calls.isEmpty)
        #expect(try await repository.count() == 1)

        coordinator.cancelForcedLogout()

        #expect(coordinator.logoutState == .idle)
        #expect(try await repository.count() == 1)
    }

    @Test("미동기 경고에서 강행하면 로그아웃 후 로컬 데이터를 지우고 오프라인에서는 신원을 만들지 않는다")
    func forcedOfflineLogoutClearsAfterWarningWithoutIssuingIdentity() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction())
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let sync = FakeLogoutSync()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: sync,
            cleanupMarker: InMemoryLogoutCleanupMarker()
        )
        await coordinator.requestLogout()

        await coordinator.confirmForcedLogout()

        #expect(coordinator.logoutState == .completed)
        #expect(auth.signOutCount == 1)
        #expect(auth.anonymousSignInCount == 1)
        #expect(auth.currentUserID == nil)
        #expect(sync.calls == [.suspendForLogout, .resumeAfterLogout])
        #expect(try await repository.count() == 0)
    }

    @Test("signOut 뒤 local clear 실패는 오염 방지를 위해 push 정지를 유지하고 cleanup 재시도를 요구한다")
    func clearFailureAfterSignOutKeepsPushSuspended() async throws {
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let sync = FakeLogoutSync()
        let cleanupMarker = InMemoryLogoutCleanupMarker()
        let coordinator = SessionTransitionCoordinator(
            repository: FailingClearLogoutRepository(),
            authProvider: auth,
            connectivity: connectivity,
            sync: sync,
            cleanupMarker: cleanupMarker
        )

        await coordinator.requestLogout()

        #expect(coordinator.logoutState == .cleanupRequired)
        #expect(coordinator.needsCleanup)
        #expect(auth.signOutCount == 1)
        #expect(auth.currentUserID == nil)
        #expect(sync.calls == [.suspendForLogout])
        #expect(cleanupMarker.isPending)
    }

    @Test("cleanup-required에서 재시도하면 로컬을 비우고 로그아웃을 완결한다")
    func retryCleanupCompletesLogoutAfterTransientClearFailure() async throws {
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let sync = FakeLogoutSync()
        let cleanupMarker = InMemoryLogoutCleanupMarker()
        let repository = ClearFailsOnceLogoutRepository()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: sync,
            cleanupMarker: cleanupMarker
        )

        await coordinator.requestLogout()

        #expect(coordinator.logoutState == .cleanupRequired)
        #expect(cleanupMarker.isPending)
        #expect(sync.calls == [.suspendForLogout])

        await coordinator.retryCleanup()

        #expect(coordinator.logoutState == .completed)
        #expect(!cleanupMarker.isPending)
        #expect(repository.didClear)
        #expect(auth.signOutCount == 1)
        #expect(auth.currentUserID != nil)
        #expect(sync.calls == [.suspendForLogout, .suspendForLogout, .resumeAfterLogout])
    }

    @Test("빠른 중복 로그아웃 탭은 단일 로그아웃만 수행한다")
    func concurrentRequestLogoutRunsSingleLogout() async throws {
        let repository = GatedClearLogoutRepository()
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let sync = FakeLogoutSync()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: sync,
            cleanupMarker: InMemoryLogoutCleanupMarker()
        )

        let first = Task { await coordinator.requestLogout() }
        await repository.waitUntilClearStarted()
        await coordinator.requestLogout()

        #expect(auth.signOutCount == 1)
        #expect(repository.clearAttempts == 1)

        repository.releaseClear()
        await first.value

        #expect(coordinator.logoutState == .completed)
        #expect(auth.signOutCount == 1)
        #expect(auth.anonymousSignInCount == 2)
        #expect(repository.clearAttempts == 1)
        #expect(sync.calls == [.suspendForLogout, .resumeAfterLogout])
    }

    @Test("cleanup 마커가 남아 있으면 코디네이터가 cleanup-required로 시작한다")
    func coordinatorStartsInCleanupRequiredWhenMarkerPending() throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        let auth = FakeAuthService()
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let sync = FakeLogoutSync()
        let cleanupMarker = InMemoryLogoutCleanupMarker()
        cleanupMarker.markPending()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: sync,
            cleanupMarker: cleanupMarker
        )

        #expect(coordinator.logoutState == .cleanupRequired)
        #expect(coordinator.needsCleanup)
        #expect(coordinator.isLoginBlocked)
    }

    @Test("재생성된 SettingsViewModel은 진행 중 로그아웃 상태를 공유하고 두 번째 로그아웃을 시작하지 않는다")
    func recreatedViewModelSharesInFlightLogout() async throws {
        let repository = PendingThenClearLogoutRepository()
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let sync = GatedPushLogoutSync()
        let cleanupMarker = InMemoryLogoutCleanupMarker()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: sync,
            cleanupMarker: cleanupMarker
        )
        let loginViewModel = LoginViewModel(
            authProvider: auth,
            sync: FakeSettingsLoginSync(),
            coordinator: coordinator,
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )
        let firstViewModel = SettingsViewModel(
            loginViewModel: loginViewModel,
            coordinator: coordinator
        )
        let recreatedViewModel = SettingsViewModel(
            loginViewModel: loginViewModel,
            coordinator: coordinator
        )

        let firstLogout = Task { await firstViewModel.requestLogout() }
        await sync.waitUntilPushStarted()

        #expect(firstViewModel.logoutState == .syncing)
        #expect(recreatedViewModel.logoutState == .syncing)
        #expect(!cleanupMarker.isPending)

        await recreatedViewModel.requestLogout()
        #expect(auth.signOutCount == 0)
        #expect(repository.clearCount == 0)
        #expect(sync.pushCount == 1)

        sync.releasePush()
        await firstLogout.value

        #expect(firstViewModel.logoutState == .completed)
        #expect(recreatedViewModel.logoutState == .completed)
        #expect(auth.signOutCount == 1)
        #expect(repository.clearCount == 1)
        #expect(sync.pushCount == 1)
    }

    @Test("cleanup 재시도 진행 중에도, 완료 전까지 로그인 진입을 막는다")
    func loginStaysBlockedWhileCleanupRetryInFlight() async throws {
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let sync = FakeLogoutSync()
        let cleanupMarker = InMemoryLogoutCleanupMarker()
        cleanupMarker.markPending()
        let repository = GatedClearLogoutRepository()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: sync,
            cleanupMarker: cleanupMarker
        )

        #expect(coordinator.isLoginBlocked)

        let retry = Task { await coordinator.retryCleanup() }
        await repository.waitUntilClearStarted()

        #expect(coordinator.logoutState == .signingOut)
        #expect(coordinator.isLoginBlocked)

        repository.releaseClear()
        await retry.value

        #expect(coordinator.logoutState == .completed)
        #expect(!coordinator.isLoginBlocked)
        #expect(!cleanupMarker.isPending)
    }

    @Test("signOut 실패로 멤버 세션이 남으면 cleanup 마커를 지우고 쓰기를 재개한다")
    func signOutFailureClearsMarkerAndResumesMemberWrites() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        let auth = FakeAuthService(signOutFailuresRemaining: 1)
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let sync = FakeLogoutSync()
        let cleanupMarker = InMemoryLogoutCleanupMarker()
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: sync,
            cleanupMarker: cleanupMarker
        )

        await coordinator.requestLogout()

        #expect(coordinator.logoutState == .failed)
        #expect(auth.signOutCount == 1)
        #expect(auth.currentUserID != nil)
        #expect(sync.calls == [.suspendForLogout, .resumeAfterLogout])
        #expect(!cleanupMarker.isPending)
    }

    @Test("부트스트랩은 미완료 로그아웃 마커를 push 조립 전에 clear한다")
    func bootstrapRecoversIncompleteLogoutBeforeSyncComposition() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction())
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let cleanupMarker = InMemoryLogoutCleanupMarker()
        cleanupMarker.markPending()

        try await AppDependencyFactory.recoverIncompleteLogout(
            repository: repository,
            authProvider: auth,
            cleanupMarker: cleanupMarker
        )

        #expect(auth.signOutCount == 1)
        #expect(auth.currentUserID == nil)
        #expect(try await repository.count() == 0)
        #expect(!cleanupMarker.isPending)
    }

    @Test("부트스트랩 복구는 sign-out 실패에도 로컬 정리를 완수하고 마커를 clear한다")
    func bootstrapRecoveryClearsLocalEvenWhenSignOutFails() async throws {
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction())
        // sign-out이 네트워크 실패로 throw해도(실 Supabase는 로컬 세션 제거 후 원격 revoke throw)
        // 부팅 복구가 막히지 않고 로컬 정리·마커 clear를 완수하는지 검증한다.
        let auth = FakeAuthService(signOutFailuresRemaining: 1)
        try await auth.ensureIdentity()
        let cleanupMarker = InMemoryLogoutCleanupMarker()
        cleanupMarker.markPending()

        try await AppDependencyFactory.recoverIncompleteLogout(
            repository: repository,
            authProvider: auth,
            cleanupMarker: cleanupMarker
        )

        #expect(auth.signOutCount == 1)
        #expect(try await repository.count() == 0)
        #expect(!cleanupMarker.isPending)
    }
}

@MainActor
private final class FakeLogoutSync: LogoutSyncing {
    enum Call: Equatable {
        case pushPending
        case suspendForLogout
        case resumeAfterLogout
    }

    private(set) var calls: [Call] = []

    func pushPending() async {
        calls.append(.pushPending)
    }

    func suspendPushForLogout() async {
        calls.append(.suspendForLogout)
    }

    func resumePushAfterLogout() {
        calls.append(.resumeAfterLogout)
    }
}

@MainActor
private final class FakeSettingsLoginSync: LoginSyncing {
    func beginAccountSwitch() async {}
    func finishAccountSwitch(expectedMemberID _: UUID) async -> Bool {
        true
    }

    func resumeAccountSwitch(expectedMemberID _: UUID?) -> Bool {
        true
    }

    func pushPending() async {}
    func restoreAll() async throws {}
}

@MainActor
private final class GatedPushLogoutSync: LogoutSyncing {
    private var pushStartedContinuation: CheckedContinuation<Void, Never>?
    private var pushReleaseContinuation: CheckedContinuation<Void, Never>?
    private var didStartPush = false
    private(set) var pushCount = 0

    func pushPending() async {
        pushCount += 1
        didStartPush = true
        pushStartedContinuation?.resume()
        pushStartedContinuation = nil
        await withCheckedContinuation { pushReleaseContinuation = $0 }
    }

    func suspendPushForLogout() async {}
    func resumePushAfterLogout() {}

    func waitUntilPushStarted() async {
        guard !didStartPush else {
            return
        }
        await withCheckedContinuation { pushStartedContinuation = $0 }
    }

    func releasePush() {
        pushReleaseContinuation?.resume()
        pushReleaseContinuation = nil
    }
}

@MainActor
private final class PendingThenClearLogoutRepository: LogoutDataProviding {
    private var pendingCheckCount = 0
    private(set) var clearCount = 0

    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        pendingCheckCount += 1
        return pendingCheckCount == 1
    }

    func clearForLogout(force _: Bool) async throws {
        clearCount += 1
    }
}

@MainActor
private struct FailingClearLogoutRepository: LogoutDataProviding {
    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        false
    }

    func clearForLogout(force _: Bool) async throws {
        throw FailingClearLogoutRepositoryError.programmedFailure
    }
}

private enum FailingClearLogoutRepositoryError: Error {
    case programmedFailure
}

/// clearForLogout를 continuation으로 붙잡아, clear가 진행 중인(`.signingOut`) 상태를
/// 결정적으로 관찰할 수 있게 하는 테스트 지원.
@MainActor
private final class GatedClearLogoutRepository: LogoutDataProviding {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    private(set) var clearAttempts = 0

    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        false
    }

    func clearForLogout(force _: Bool) async throws {
        clearAttempts += 1
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilClearStarted() async {
        guard !didStart else {
            return
        }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func releaseClear() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class ClearFailsOnceLogoutRepository: LogoutDataProviding {
    private var clearAttempts = 0
    private(set) var didClear = false

    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        false
    }

    func clearForLogout(force _: Bool) async throws {
        clearAttempts += 1
        if clearAttempts == 1 {
            throw FailingClearLogoutRepositoryError.programmedFailure
        }
        didClear = true
    }
}

private extension SettingsViewModelTests {
    static func makeTransaction() -> LocalTransaction {
        LocalTransaction(
            clientEntryID: UUID(),
            amount: Decimal(1000),
            currencyCode: "KRW",
            categoryID: 10,
            assetID: 20,
            transactionType: .expense,
            transactionDate: "2026-07-20",
            memo: nil,
            pending: true,
            appliedRate: nil,
            rateBaseDate: nil,
            krwAmount: Decimal(1000)
        )
    }
}
