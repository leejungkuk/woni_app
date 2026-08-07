//
//  LoginViewModelTests.swift
//  woni_appTests
//

import AuthenticationServices
import Foundation
import Testing
@testable import woni_app

// swiftlint:disable file_length

@MainActor
struct LoginViewModelTests {
    @Test(
        "로그인은 provider와 무관하게 인증 1회로 계정 전환을 열고 restore 뒤 완료한다",
        arguments: [OAuthProvider.google, .apple]
    )
    func signInCompletesThroughRestore(_ provider: OAuthProvider) async throws {
        let signedInUserID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let auth = FakeAuthService(makeSignedInUserID: { signedInUserID })
        var revokeCountWhenRestoreStarted = 0
        let sync = FakeLoginSync(
            localAnonymousEntryIDs: ["local-entry"],
            restoreAllHandler: { revokeCountWhenRestoreStarted = auth.revokeOtherSessionsCount }
        )
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(provider)

        // 계정 이력에 따라 갈래가 남아 있으면 인증이 2회가 되어 이 배열이 늘어난다.
        #expect(auth.signInProviders == [provider])
        #expect(auth.currentUserID == signedInUserID)
        #expect(auth.isAnonymous == false)
        #expect(auth.revokeOtherSessionsCount == 1)
        #expect(revokeCountWhenRestoreStarted == 1)
        // 리셋이 restoreAll보다 뒤로 밀리면 restore로 받은 서버 행까지 다시 import 대상이 된다.
        #expect(sync.calls == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(signedInUserID)
        ])
        #expect(!sync.isPushSuspended)
        #expect(sync.mergePushCount == 1)
        #expect(sync.localAnonymousEntryIDs == ["local-entry"])
        #expect(viewModel.flowState == .completed)
        #expect(viewModel.identityState == .signedIn)
    }

    @Test(
        "인증 취소는 알럿 없이 idle로 돌아가고 suspension을 해제한다",
        arguments: [OAuthProvider.google, .apple]
    )
    func userCancellationReturnsToIdleAndResumesAccountSwitch(_ provider: OAuthProvider) async {
        // 취소 오류 타입이 provider마다 다르므로 실제 경로와 같은 타입을 주입해야 판정이 검증된다.
        let cancellation: any Error = provider == .google
            ? ASWebAuthenticationSessionError(.canceledLogin)
            : ASAuthorizationError(.canceled)
        let auth = FakeAuthService(signInError: cancellation)
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(provider)

        #expect(auth.signInProviders == [provider])
        // 취소도 begin 이후의 중단 경로다 — resume이 빠지면 push suspend가 남아 동기화가 멈춘다.
        #expect(sync.calls == [.beginAccountSwitch, .resumeAccountSwitch(nil)])
        #expect(!sync.isPushSuspended)
        #expect(viewModel.flowState == .idle)
        #expect(!viewModel.hasFailure)
        #expect(!viewModel.hasOfflineFailure)
        #expect(!viewModel.hasRestoreFailure)
    }

    @Test("취소 판정은 두 provider의 취소 오류만 true로 접는다")
    func userCancellationIsRecognizedForBothProviders() {
        #expect(LoginViewModel.isUserCancellation(ASWebAuthenticationSessionError(.canceledLogin)))
        #expect(LoginViewModel.isUserCancellation(ASAuthorizationError(.canceled)))
        // 같은 도메인의 비취소 오류까지 접으면 실패가 조용히 묻힌다.
        #expect(!LoginViewModel.isUserCancellation(
            ASWebAuthenticationSessionError(.presentationContextNotProvided)
        ))
        #expect(!LoginViewModel.isUserCancellation(ASAuthorizationError(.failed)))
        #expect(!LoginViewModel.isUserCancellation(URLError(.notConnectedToInternet)))
    }

    @Test("로그인 성공 뒤 restore 실패는 인증 실패와 분리하고 restore만 재시도한다")
    func restoreFailureRetriesWithoutSigningInAgain() async {
        let auth = FakeAuthService()
        let sync = FakeLoginSync(restoreFailuresRemaining: 1)
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.google)

        #expect(viewModel.flowState == .restoreFailed)
        #expect(viewModel.identityState == .signedIn)
        #expect(auth.signInProviders == [.google])

        await viewModel.retryRestore()

        #expect(viewModel.flowState == .completed)
        #expect(auth.signInProviders == [.google])
        let targetUserID = auth.currentUserID
        #expect(sync.calls == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .restoreAll,
            .finishAccountSwitch(targetUserID)
        ])
        #expect(!sync.isPushSuspended)
        #expect(sync.mergePushCount == 1)
    }

    @Test("signIn 실패는 suspension을 해제해 이후 재시도의 push를 복구한다")
    func signInFailureResumesAccountSwitchBeforeRetry() async {
        let auth = FakeAuthService(signInFailuresRemaining: 1)
        let sync = FakeLoginSync(localAnonymousEntryIDs: ["local-entry"])
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.google)

        #expect(viewModel.flowState == .failed)
        #expect(sync.calls == [.beginAccountSwitch, .resumeAccountSwitch(nil)])
        #expect(!sync.isPushSuspended)

        await viewModel.signIn(.google)

        #expect(viewModel.flowState == .completed)
        #expect(sync.calls == [
            .beginAccountSwitch,
            .resumeAccountSwitch(nil),
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(auth.currentUserID)
        ])
        #expect(sync.localAnonymousEntryIDs == ["local-entry"])
    }

    @Test("커서 리셋 실패는 signIn과 restore 전에 중단하고 suspension을 해제해 재시도할 수 있다")
    func pullCursorResetFailureStopsSignInFailClosedAndAllowsRetry() async {
        let auth = FakeAuthService()
        let sync = FakeLoginSync(beginAccountSwitchFailuresRemaining: 1)
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.google)

        #expect(auth.signInProviders.isEmpty)
        #expect(sync.calls == [.beginAccountSwitch, .resumeAccountSwitch(nil)])
        #expect(!sync.isPushSuspended)
        #expect(viewModel.flowState == .failed)

        await viewModel.signIn(.google)

        #expect(auth.signInProviders == [.google])
        #expect(sync.calls == [
            .beginAccountSwitch,
            .resumeAccountSwitch(nil),
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(auth.currentUserID)
        ])
        #expect(!sync.isPushSuspended)
        #expect(viewModel.flowState == .completed)
    }

    @Test("revoke 중 계정이 바뀌면 해당 계정의 restore를 시작하지 않는다")
    func changedTargetUserAfterRevokeSkipsRestore() async {
        let auth = FakeAuthService()
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        auth.setRevokeOtherSessionsHandler {
            try? await auth.signOut()
        }
        await viewModel.signIn(.google)

        #expect(auth.signInProviders == [.google])
        #expect(auth.revokeOtherSessionsCount == 1)
        let targetUserID = sync.lastResumeTarget
        #expect(sync.calls == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .resumeAccountSwitch(targetUserID)
        ])
        #expect(!sync.isPushSuspended)
        #expect(viewModel.flowState == .failed)
    }

    @Test("계정 전환 sync 리셋은 restoreAll보다 먼저 호출된다")
    func resetSyncStateIsCalledBeforeRestoreAll() async throws {
        let auth = FakeAuthService()
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.google)

        let resetIndex = try #require(sync.calls.firstIndex(of: .resetSyncStateForAccountSwitch))
        let restoreIndex = try #require(sync.calls.firstIndex(of: .restoreAll))
        #expect(resetIndex < restoreIndex)
    }

    @Test("sync 리셋 실패는 restore 전에 중단하고 suspension을 해제한다")
    func resetSyncStateFailureStopsBeforeRestore() async {
        let auth = FakeAuthService()
        let sync = FakeLoginSync(resetSyncStateFailuresRemaining: 1)
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.google)

        // 리셋이 실패하면 익명 데이터가 새 계정으로 올라가지 않는다 — 조용히 진행하지 않고 실패로 드러낸다.
        #expect(sync.calls == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .resumeAccountSwitch(auth.currentUserID)
        ])
        #expect(!sync.isPushSuspended)
        #expect(viewModel.flowState == .failed)
    }

    @Test("revoke 실패는 로그인 성공과 restore를 막지 않는다")
    func revokeFailureIsBestEffort() async {
        let auth = FakeAuthService(revokeOtherSessionsFailuresRemaining: 1)
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.apple)

        #expect(auth.revokeOtherSessionsCount == 1)
        #expect(sync.calls == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(auth.currentUserID)
        ])
        #expect(sync.mergePushCount == 1)
        #expect(viewModel.flowState == .completed)
    }

    @Test("오프라인 진입은 OAuth를 시작하지 않고 전용 안내 상태가 된다")
    func offlineSignInDoesNotStartOAuth() async {
        let auth = FakeAuthService()
        let sync = FakeLoginSync()
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: connectivity
        )

        await viewModel.signIn(.google)

        #expect(auth.signInProviders.isEmpty)
        #expect(sync.calls.isEmpty)
        #expect(viewModel.flowState == .offline)
        #expect(viewModel.hasOfflineFailure)
    }

    @Test("사전 확인 뒤 오프라인이 되면 계정 전환도 OAuth도 시작하지 않는다")
    func offlineAfterInitialCheckDoesNotBeginAccountSwitch() async {
        let auth = FakeAuthService()
        let connectivity = OfflineAfterInitialCheckConnectivity()
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: connectivity
        )

        await viewModel.signIn(.apple)

        #expect(auth.signInProviders.isEmpty)
        #expect(sync.calls.isEmpty)
        #expect(viewModel.flowState == .offline)
    }

    @Test("사전 확인 뒤 발생한 실제 auth 네트워크 오류도 오프라인 안내로 매핑한다")
    func signInNetworkErrorMapsToOfflineState() async {
        let auth = FakeAuthService(signInError: URLError(.networkConnectionLost))
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.google)

        #expect(auth.signInProviders == [.google])
        #expect(sync.calls == [.beginAccountSwitch, .resumeAccountSwitch(nil)])
        #expect(!sync.isPushSuspended)
        #expect(viewModel.flowState == .offline)
    }
}

@MainActor
extension LoginViewModelTests {
    @Test("세션 없음과 익명 세션에서는 이메일을 노출하지 않는다")
    func signedInEmailIsNilBeforeSignIn() async throws {
        let auth = FakeAuthService(signedInEmail: "member@example.test")
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: FakeLoginSync(),
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        #expect(viewModel.signedInEmail == nil)

        try await auth.ensureIdentity()

        #expect(auth.isAnonymous)
        #expect(viewModel.signedInEmail == nil)
    }

    @Test("로그인 성공 뒤 이메일을 노출한다")
    func signedInEmailAppearsAfterSignIn() async {
        let expectedEmail = "existing@example.test"
        let auth = FakeAuthService(signedInEmail: expectedEmail)
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: FakeLoginSync(),
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.apple)

        #expect(viewModel.flowState == .completed)
        #expect(viewModel.signedInEmail == expectedEmail)
    }

    @Test("signIn 실패 후에는 이메일을 노출하지 않는다")
    func signedInEmailStaysNilAfterSignInFailure() async {
        let auth = FakeAuthService(
            signedInEmail: "existing@example.test",
            signInFailuresRemaining: 1
        )
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: FakeLoginSync(),
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.google)

        #expect(viewModel.flowState == .failed)
        #expect(viewModel.signedInEmail == nil)
    }

    @Test("restore 재시도 시 계정이 바뀌면 restore를 다시 시작하지 않는다")
    func retryRestoreSkipsWhenTargetUserChanged() async {
        let auth = FakeAuthService()
        let sync = FakeLoginSync(restoreFailuresRemaining: 1)
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.google)
        #expect(viewModel.flowState == .restoreFailed)

        try? await auth.signOut()
        await viewModel.retryRestore()

        #expect(viewModel.flowState == .failed)
        let targetUserID = sync.lastResumeTarget
        #expect(sync.calls == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .resumeAccountSwitch(targetUserID)
        ])
        #expect(!sync.isPushSuspended)
    }

    @Test("연결성과 무관한 URLError는 오프라인이 아닌 일반 실패로 남는다")
    func nonConnectivityURLErrorStaysFailed() async {
        let auth = FakeAuthService(signInError: URLError(.badServerResponse))
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: FakeLoginSync(),
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.signIn(.google)

        #expect(auth.signInProviders == [.google])
        #expect(viewModel.flowState == .failed)
    }

    @Test(
        "계정 전환 종료표는 finish 성공만 병합하고 나머지는 신원 가드 resume 또는 suspend 유지로 끝난다",
        arguments: AccountSwitchEndingScenario.allCases
    )
    func accountSwitchEndingTable(_ scenario: AccountSwitchEndingScenario) async throws {
        let targetUserID = try #require(
            UUID(uuidString: "61616161-6161-6161-6161-616161616161")
        )
        let auth = FakeAuthService(
            makeSignedInUserID: { targetUserID },
            signInFailuresRemaining: scenario == .signInFailure ? 1 : 0
        )
        let sync = FakeLoginSync(
            restoreFailuresRemaining: scenario.needsRestoreFailure ? 1 : 0,
            // finishDrift는 restore 뒤 신원이 예상 밖 인증 member로 바뀐 안전 임계 케이스를 모델링한다:
            // 실제 SyncEngine에선 finish도 resume(target)도 fail-closed(false)라 suspend가 유지된다(High-A).
            finishAccountSwitchResult: scenario != .finishDrift,
            resumeAccountSwitchResult: scenario != .finishDrift
        )
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        if scenario == .revokeRevalidationFailure {
            auth.setRevokeOtherSessionsHandler {
                try? await auth.signOut()
            }
        }
        await viewModel.signIn(.google)

        if scenario == .retryTargetMismatch {
            try? await auth.signOut()
            await viewModel.retryRestore()
        } else if scenario == .abandonRestore {
            await viewModel.finishAfterRestoreFailure()
        }

        #expect(sync.calls == scenario.expectedCalls(targetUserID: targetUserID))
        #expect(viewModel.flowState == scenario.expectedFlowState)
        #expect(sync.isPushSuspended == scenario.expectsSuspension)
        #expect(sync.mergePushCount == scenario.expectedMergePushCount)
    }
}

@MainActor
extension LoginViewModelTests {
    @Test("스트림 이벤트가 하나도 없어도 생성 시점의 신원을 그대로 노출한다")
    func identitySnapshotMatchesProviderAtInit() async throws {
        let auth = FakeAuthService(signedInEmail: "member@example.test")
        try await auth.signIn(.google)

        let viewModel = makeIdentityViewModel(auth: auth)

        #expect(viewModel.identityState == .signedIn)
        #expect(viewModel.signedInEmail == "member@example.test")
    }

    @Test("신원 변경은 구독 중인 모든 인스턴스에 전달된다")
    func identityChangeReachesEveryObserver() async throws {
        let auth = FakeAuthService(signedInEmail: "member@example.test")
        let live = makeIdentityViewModel(auth: auth)
        let extra = makeIdentityViewModel(auth: auth)
        let liveObservation = Task { await live.observeIdentity() }
        let extraObservation = Task { await extra.observeIdentity() }
        await Task.yield()

        try await auth.signIn(.google)
        await Task.yield()

        #expect(live.identityState == .signedIn)
        #expect(extra.identityState == .signedIn)
        liveObservation.cancel()
        extraObservation.cancel()
    }

    @Test("구독이 늦게 시작돼도 그 시점의 신원으로 수렴한다")
    func lateObservationConvergesToCurrentIdentity() async throws {
        let auth = FakeAuthService(signedInEmail: "member@example.test")
        let viewModel = makeIdentityViewModel(auth: auth)

        // 구독자가 없는 동안 일어난 변경이라 스트림 이벤트로는 전달되지 않는다.
        try await auth.signIn(.google)

        #expect(viewModel.identityState == .anonymous)

        let observation = Task { await viewModel.observeIdentity() }
        await Task.yield()

        #expect(viewModel.identityState == .signedIn)
        #expect(viewModel.signedInEmail == "member@example.test")
        observation.cancel()
    }
}

@MainActor
private func makeIdentityViewModel(auth: FakeAuthService) -> LoginViewModel {
    LoginViewModel(
        authProvider: auth,
        sync: FakeLoginSync(),
        coordinator: makeTestSessionCoordinator(authProvider: auth),
        connectivity: FakeConnectivityMonitor(isOnline: true)
    )
}

enum AccountSwitchEndingScenario: CaseIterable {
    case signInFailure
    case revokeRevalidationFailure
    case finishSuccess
    case finishDrift
    case restoreFailure
    case retryTargetMismatch
    case abandonRestore

    var needsRestoreFailure: Bool {
        self == .restoreFailure || self == .retryTargetMismatch || self == .abandonRestore
    }

    func expectedCalls(targetUserID: UUID) -> [FakeLoginSync.Call] {
        switch self {
        case .signInFailure:
            [.beginAccountSwitch, .resumeAccountSwitch(nil)]
        case .revokeRevalidationFailure:
            [.beginAccountSwitch, .resetSyncStateForAccountSwitch, .resumeAccountSwitch(targetUserID)]
        case .finishSuccess:
            [
                .beginAccountSwitch,
                .resetSyncStateForAccountSwitch,
                .restoreAll,
                .finishAccountSwitch(targetUserID)
            ]
        case .finishDrift:
            [
                .beginAccountSwitch,
                .resetSyncStateForAccountSwitch,
                .restoreAll,
                .finishAccountSwitch(targetUserID),
                .resumeAccountSwitch(targetUserID)
            ]
        case .restoreFailure:
            [.beginAccountSwitch, .resetSyncStateForAccountSwitch, .restoreAll]
        case .retryTargetMismatch, .abandonRestore:
            [
                .beginAccountSwitch,
                .resetSyncStateForAccountSwitch,
                .restoreAll,
                .resumeAccountSwitch(targetUserID)
            ]
        }
    }

    var expectedFlowState: LoginViewModel.FlowState {
        switch self {
        case .finishSuccess, .abandonRestore:
            .completed
        case .restoreFailure:
            .restoreFailed
        case .signInFailure, .revokeRevalidationFailure, .finishDrift, .retryTargetMismatch:
            .failed
        }
    }

    var expectsSuspension: Bool {
        // restoreFailure: restore 실패로 suspend 유지(retry 경로).
        // finishDrift: 예상 밖 인증 member로 drift → finish·resume(target) 모두 fail-closed로 suspend 유지(High-A).
        self == .restoreFailure || self == .finishDrift
    }

    var expectedMergePushCount: Int {
        self == .finishSuccess ? 1 : 0
    }
}

@MainActor
private final class OfflineAfterInitialCheckConnectivity: ConnectivityObserving {
    private var checkCount = 0

    var isOnline: Bool {
        defer { checkCount += 1 }
        return checkCount == 0
    }

    var changes: AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
final class FakeLoginSync: LoginSyncing {
    enum Call: Equatable {
        case beginAccountSwitch
        case finishAccountSwitch(UUID?)
        case resumeAccountSwitch(UUID?)
        case pushPending
        case restoreAll
        case resetSyncStateForAccountSwitch
    }

    private(set) var calls: [Call] = []
    private(set) var localAnonymousEntryIDs: [String]
    private(set) var isPushSuspended = false
    private(set) var mergePushCount = 0
    private var beginAccountSwitchFailuresRemaining: Int
    private var restoreFailuresRemaining: Int
    private var resetSyncStateFailuresRemaining: Int
    private let finishAccountSwitchResult: Bool
    private let resumeAccountSwitchResult: Bool
    private let restoreAllHandler: (() -> Void)?

    init(
        localAnonymousEntryIDs: [String] = [],
        beginAccountSwitchFailuresRemaining: Int = 0,
        restoreFailuresRemaining: Int = 0,
        resetSyncStateFailuresRemaining: Int = 0,
        finishAccountSwitchResult: Bool = true,
        resumeAccountSwitchResult: Bool = true,
        restoreAllHandler: (() -> Void)? = nil
    ) {
        self.localAnonymousEntryIDs = localAnonymousEntryIDs
        self.beginAccountSwitchFailuresRemaining = beginAccountSwitchFailuresRemaining
        self.restoreFailuresRemaining = restoreFailuresRemaining
        self.resetSyncStateFailuresRemaining = resetSyncStateFailuresRemaining
        self.finishAccountSwitchResult = finishAccountSwitchResult
        self.resumeAccountSwitchResult = resumeAccountSwitchResult
        self.restoreAllHandler = restoreAllHandler
    }

    var lastResumeTarget: UUID? {
        for case let .resumeAccountSwitch(target) in calls.reversed() {
            return target
        }
        return nil
    }

    func beginAccountSwitch() async throws {
        calls.append(.beginAccountSwitch)
        isPushSuspended = true
        if beginAccountSwitchFailuresRemaining > 0 {
            beginAccountSwitchFailuresRemaining -= 1
            throw FakeLoginSyncError.beginAccountSwitchFailed
        }
    }

    func finishAccountSwitch(expectedMemberID: UUID) async -> Bool {
        calls.append(.finishAccountSwitch(expectedMemberID))
        guard finishAccountSwitchResult else {
            return false
        }
        isPushSuspended = false
        mergePushCount += 1
        return true
    }

    func resumeAccountSwitch(expectedMemberID: UUID?) -> Bool {
        calls.append(.resumeAccountSwitch(expectedMemberID))
        guard resumeAccountSwitchResult else {
            return false
        }
        isPushSuspended = false
        return true
    }

    func pushPending() async {
        calls.append(.pushPending)
    }

    func restoreAll() async throws {
        restoreAllHandler?()
        calls.append(.restoreAll)
        if restoreFailuresRemaining > 0 {
            restoreFailuresRemaining -= 1
            throw FakeLoginSyncError.restoreFailed
        }
    }

    func resetSyncStateForAccountSwitch() async throws {
        calls.append(.resetSyncStateForAccountSwitch)
        if resetSyncStateFailuresRemaining > 0 {
            resetSyncStateFailuresRemaining -= 1
            throw FakeLoginSyncError.resetSyncStateFailed
        }
    }
}

private enum FakeLoginSyncError: Error {
    case beginAccountSwitchFailed
    case restoreFailed
    case resetSyncStateFailed
}
