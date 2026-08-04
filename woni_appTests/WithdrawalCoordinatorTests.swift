//
//  WithdrawalCoordinatorTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 탈퇴 오케스트레이션(코드 수집 → DELETE → 정리)의 순서와 종단 상태를 검증한다.
/// HTTP 계약은 `MemberServiceTests`가 이미 고정했으므로 여기서는 대역으로 대체한다.
@Suite(.serialized)
@MainActor
struct WithdrawalCoordinatorTests {
    @Test("Apple 회원은 코드를 실어 삭제하고 정리 뒤 완료가 된다")
    func appleMemberWithdrawsWithAuthorizationCode() async throws {
        let auth = FakeAuthService(hasAppleIdentity: true, appleAuthorizationCode: "apple-code")
        try await auth.signIn(.apple)
        let harness = WithdrawalHarness(auth: auth)

        harness.coordinator.prepareWithdrawal()
        #expect(harness.coordinator.state == .awaitingConfirmation(isAppleLinked: true))

        await harness.coordinator.confirmWithdrawal()

        #expect(harness.service.codes == ["apple-code"])
        #expect(harness.repository.forceArguments == [true])
        #expect(auth.signOutCount == 1)
        #expect(auth.isAnonymous)
        #expect(harness.coordinator.state == .completed(appleUnlinkPending: false))
    }

    @Test("Apple 시트가 오류로 끝나도 삭제는 계속하고 연동 해제만 사용자 몫으로 남긴다")
    func appleSheetFailureStillWithdraws() async throws {
        let auth = FakeAuthService(hasAppleIdentity: true, appleAuthorizationCode: "apple-code")
        auth.appleAuthorizationCodeError = WithdrawalTestError.appleSheetCancelled
        try await auth.signIn(.apple)
        let harness = WithdrawalHarness(auth: auth)

        harness.coordinator.prepareWithdrawal()
        await harness.coordinator.confirmWithdrawal()

        #expect(harness.service.codes == [nil])
        #expect(harness.repository.forceArguments == [true])
        #expect(harness.coordinator.state == .completed(appleUnlinkPending: true))
    }

    @Test("Apple 코드가 비어 돌아와도 삭제는 계속한다")
    func missingAppleAuthorizationCodeStillWithdraws() async throws {
        let auth = FakeAuthService(hasAppleIdentity: true)
        try await auth.signIn(.apple)
        let harness = WithdrawalHarness(auth: auth)

        harness.coordinator.prepareWithdrawal()
        await harness.coordinator.confirmWithdrawal()

        #expect(auth.requestAppleAuthorizationCodeCount == 1)
        #expect(harness.service.codes == [nil])
        #expect(harness.coordinator.state == .completed(appleUnlinkPending: true))
    }

    @Test("Google 회원은 Apple 시트를 열지 않는다")
    func googleMemberSkipsAppleSheet() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let harness = WithdrawalHarness(auth: auth)

        harness.coordinator.prepareWithdrawal()
        #expect(harness.coordinator.state == .awaitingConfirmation(isAppleLinked: false))

        await harness.coordinator.confirmWithdrawal()

        #expect(auth.requestAppleAuthorizationCodeCount == 0)
        #expect(harness.service.codes == [nil])
        #expect(harness.coordinator.state == .completed(appleUnlinkPending: false))
    }

    @Test("익명 사용자는 시트 없이 삭제되고 새 익명 신원을 받는다")
    func anonymousUserDeletesData() async throws {
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let harness = WithdrawalHarness(auth: auth)

        harness.coordinator.prepareWithdrawal()
        await harness.coordinator.confirmWithdrawal()

        #expect(auth.requestAppleAuthorizationCodeCount == 0)
        #expect(harness.repository.forceArguments == [true])
        #expect(auth.anonymousSignInCount == 2)
        #expect(harness.coordinator.state == .completed(appleUnlinkPending: false))
    }

    @Test("오프라인에서는 확인 단계로 가지 않고 서버·로컬 어느 쪽도 건드리지 않는다")
    func offlineStopsBeforeConfirmation() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let harness = WithdrawalHarness(auth: auth, isOnline: false)

        harness.coordinator.prepareWithdrawal()

        #expect(harness.coordinator.state == .offline)
        #expect(harness.service.codes.isEmpty)
        #expect(harness.repository.forceArguments.isEmpty)
        #expect(harness.sync.calls.isEmpty)

        harness.coordinator.dismissOffline()
        #expect(harness.coordinator.state == .idle)
    }

    @Test("타임아웃 같은 모호한 실패는 코드 없이 1회만 재호출한다")
    func ambiguousFailureRetriesOnceWithoutCode() async throws {
        let auth = FakeAuthService(hasAppleIdentity: true, appleAuthorizationCode: "apple-code")
        try await auth.signIn(.apple)
        let harness = WithdrawalHarness(
            auth: auth,
            service: WithdrawalServiceStub(errors: [APIError.transport(URLError(.timedOut))])
        )

        harness.coordinator.prepareWithdrawal()
        await harness.coordinator.confirmWithdrawal()

        // 1회용 코드는 첫 요청에서 소진됐으므로 재호출에 실어서는 안 된다.
        #expect(harness.service.codes == ["apple-code", nil])
        #expect(harness.repository.forceArguments == [true])
        #expect(harness.coordinator.state == .completed(appleUnlinkPending: false))
    }

    @Test("재호출도 실패하면 로컬을 지우지 않고 정지시킨 push를 되살린다")
    func retryFailureKeepsLocalDataAndResumesPush() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let harness = WithdrawalHarness(
            auth: auth,
            service: WithdrawalServiceStub(errors: [
                APIError.transport(URLError(.networkConnectionLost)),
                APIError.transport(URLError(.timedOut))
            ])
        )

        harness.coordinator.prepareWithdrawal()
        await harness.coordinator.confirmWithdrawal()

        #expect(harness.service.codes.count == 2)
        #expect(harness.repository.forceArguments.isEmpty)
        #expect(auth.signOutCount == 0)
        // resume만으로는 정지 때 취소된 debounce가 되살아나지 않으므로 pushPending까지 불려야 한다.
        #expect(harness.sync.calls == [.suspend, .resume, .push])
        #expect(harness.coordinator.state == .failed)

        harness.coordinator.dismissFailure()
        #expect(harness.coordinator.state == .idle)
    }

    @Test("명시적 실패·사용자 중단·연결 실패는 재호출하지 않는다")
    func unambiguousFailuresDoNotRetry() async throws {
        let errors: [APIError] = [
            .httpStatus(code: 500, message: "server error"),
            .httpStatus(code: 429, message: "too many requests"),
            .transport(URLError(.cancelled)),
            .transport(URLError(.cannotFindHost))
        ]

        for error in errors {
            let auth = FakeAuthService()
            try await auth.signIn(.google)
            let harness = WithdrawalHarness(
                auth: auth,
                service: WithdrawalServiceStub(errors: [error])
            )

            harness.coordinator.prepareWithdrawal()
            await harness.coordinator.confirmWithdrawal()

            #expect(harness.service.codes.count == 1)
            #expect(harness.repository.forceArguments.isEmpty)
            #expect(harness.coordinator.state == .failed)
        }
    }

    @Test("정리가 실패하면 완료·실패 대신 기존 cleanup 재시도 경로만 남긴다")
    func cleanupFailureLeavesOnlyCleanupAlert() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let harness = WithdrawalHarness(
            auth: auth,
            repository: WithdrawalRepository(clearFailuresRemaining: 1)
        )

        harness.coordinator.prepareWithdrawal()
        await harness.coordinator.confirmWithdrawal()

        #expect(harness.service.codes.count == 1)
        #expect(harness.session.logoutState == .cleanupRequired)
        #expect(harness.coordinator.state == .idle)
    }

    @Test("미동기 항목이 남아 있어도 경고 없이 강제로 정리한다")
    func unsyncedEntriesAreForceCleared() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let harness = WithdrawalHarness(
            auth: auth,
            repository: WithdrawalRepository(hasUnsyncedEntries: true)
        )

        harness.coordinator.prepareWithdrawal()
        await harness.coordinator.confirmWithdrawal()

        #expect(harness.repository.forceArguments == [true])
        #expect(harness.session.logoutState != .awaitingUnsyncedConfirmation)
        #expect(harness.coordinator.state == .completed(appleUnlinkPending: false))
    }

    @Test("탈퇴 진행 중 로그아웃 요청은 탈퇴 정리 뒤로 직렬화된다")
    func logoutDuringWithdrawalIsSerialized() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let gate = WithdrawalGate()
        let harness = WithdrawalHarness(auth: auth, service: WithdrawalServiceStub(gate: gate))

        harness.coordinator.prepareWithdrawal()
        let withdrawal = Task { await harness.coordinator.confirmWithdrawal() }
        await gate.waitUntilHeld()

        let logout = Task { await harness.session.requestLogout() }
        await settleTransitions()
        #expect(harness.repository.forceArguments.isEmpty)

        gate.release()
        await withdrawal.value
        await logout.value

        #expect(harness.repository.forceArguments == [true, false])
        #expect(harness.coordinator.state == .completed(appleUnlinkPending: false))
    }

    @Test("확인 이후 종단 상태를 처리할 때까지 다른 진입을 막는다")
    func blocksOtherEntryUntilTerminalStateIsHandled() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let gate = WithdrawalGate()
        let harness = WithdrawalHarness(auth: auth, service: WithdrawalServiceStub(gate: gate))

        harness.coordinator.prepareWithdrawal()
        #expect(!harness.coordinator.isBlockingOtherEntry)

        let withdrawal = Task { await harness.coordinator.confirmWithdrawal() }
        await gate.waitUntilHeld()
        #expect(harness.coordinator.state == .deleting)
        #expect(harness.coordinator.isBlockingOtherEntry)

        gate.release()
        await withdrawal.value
        #expect(harness.coordinator.isBlockingOtherEntry)

        harness.coordinator.acknowledgeCompletion()
        #expect(!harness.coordinator.isBlockingOtherEntry)
    }

    @Test("삭제 왕복이 실패로 끝난 뒤 무효화된 세션은 기존 강제 정리 경로가 수습한다")
    func invalidatedSessionAfterFailureFallsBackToForceCleanup() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let harness = WithdrawalHarness(
            auth: auth,
            service: WithdrawalServiceStub(errors: [
                APIError.transport(URLError(.timedOut)),
                APIError.transport(URLError(.timedOut))
            ])
        )

        harness.coordinator.prepareWithdrawal()
        await harness.coordinator.confirmWithdrawal()
        #expect(harness.coordinator.state == .failed)
        #expect(harness.repository.forceArguments.isEmpty)

        // 서버에서는 삭제가 끝났는데 앱만 옛 세션을 들고 있는 경우(S15). 전용 영속 상태 없이
        // 다음 refresh의 sessionMissing → sessionInvalidated 체인이 강제 정리로 수습한다.
        auth.simulateRemoteInvalidation()
        await waitUntilNoticed { harness.session.remoteLogoutNotice }

        #expect(harness.repository.forceArguments == [true])
        #expect(auth.isAnonymous)
    }
}

@MainActor
private struct WithdrawalHarness {
    let auth: FakeAuthService
    let repository: WithdrawalRepository
    let sync: WithdrawalSync
    let service: WithdrawalServiceStub
    let session: SessionTransitionCoordinator
    let coordinator: WithdrawalCoordinator

    init(
        auth: FakeAuthService,
        isOnline: Bool = true,
        repository: WithdrawalRepository? = nil,
        service: WithdrawalServiceStub? = nil
    ) {
        let repository = repository ?? WithdrawalRepository()
        let service = service ?? WithdrawalServiceStub()
        let connectivity = FakeConnectivityMonitor(isOnline: isOnline)
        let sync = WithdrawalSync()
        let session = makeTestSessionCoordinator(
            authProvider: auth,
            repository: repository,
            connectivity: connectivity,
            logoutSync: sync
        )
        self.auth = auth
        self.repository = repository
        self.sync = sync
        self.service = service
        self.session = session
        coordinator = WithdrawalCoordinator(
            session: session,
            authProvider: auth,
            connectivity: connectivity,
            withdrawalService: service
        )
    }
}

private enum WithdrawalTestError: Error {
    case appleSheetCancelled
    case clearFailure
}

@MainActor
private final class WithdrawalServiceStub: WithdrawalRequesting {
    private var errors: [Error]
    private let gate: WithdrawalGate?

    private(set) var codes: [String?] = []

    init(errors: [Error] = [], gate: WithdrawalGate? = nil) {
        self.errors = errors
        self.gate = gate
    }

    func withdraw(appleAuthorizationCode: String?) async throws {
        codes.append(appleAuthorizationCode)
        await gate?.hold()
        guard !errors.isEmpty else {
            return
        }
        throw errors.removeFirst()
    }
}

@MainActor
private final class WithdrawalRepository: LogoutDataProviding {
    private let hasUnsyncedEntries: Bool
    private var clearFailuresRemaining: Int

    private(set) var forceArguments: [Bool] = []

    init(hasUnsyncedEntries: Bool = false, clearFailuresRemaining: Int = 0) {
        self.hasUnsyncedEntries = hasUnsyncedEntries
        self.clearFailuresRemaining = clearFailuresRemaining
    }

    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        hasUnsyncedEntries
    }

    func clearForLogout(force: Bool) async throws {
        forceArguments.append(force)
        if clearFailuresRemaining > 0 {
            clearFailuresRemaining -= 1
            throw WithdrawalTestError.clearFailure
        }
    }
}

@MainActor
private final class WithdrawalSync: LogoutSyncing {
    enum Call: Equatable {
        case suspend
        case resume
        case push
    }

    private(set) var calls: [Call] = []

    func pushPending() async {
        calls.append(.push)
    }

    func suspendPushForLogout() async {
        calls.append(.suspend)
    }

    func resumePushAfterLogout() {
        calls.append(.resume)
    }
}

@MainActor
private final class WithdrawalGate {
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
private func settleTransitions() async {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
}

@MainActor
private func waitUntilNoticed(_ condition: @escaping @MainActor () -> Bool) async {
    for _ in 0 ..< 1000 {
        if condition() {
            return
        }
        await Task.yield()
    }
}
