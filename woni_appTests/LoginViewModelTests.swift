//
//  LoginViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@MainActor
struct LoginViewModelTests {
    @Test("identity 연결 성공은 익명 UUID를 유지하고 pending push를 이어간다")
    func linkIdentityPreservesUserIDAndPushesPending() async throws {
        let anonymousUserID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let auth = FakeAuthService(makeUserID: { anonymousUserID })
        var revokeCountWhenPushStarted = 0
        let sync = FakeLoginSync(
            pushPendingHandler: { revokeCountWhenPushStarted = auth.revokeOtherSessionsCount }
        )
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.linkIdentity(.google)

        #expect(auth.linkIdentityProviders == [.google])
        #expect(auth.signInProviders.isEmpty)
        #expect(auth.anonymousSignInCount == 1)
        #expect(auth.currentUserID == anonymousUserID)
        #expect(auth.isAnonymous == false)
        #expect(auth.revokeOtherSessionsCount == 1)
        #expect(revokeCountWhenPushStarted == 1)
        #expect(sync.calls == [.pushPending])
        #expect(viewModel.flowState == .completed)
        #expect(viewModel.identityState == .signedIn)
    }

    @Test("identity 충돌은 확인 뒤 기존 계정 로그인과 restore를 수행하고 로컬 데이터를 보존한다")
    func identityConflictSignsInThenRestoresWithoutClearingLocalData() async throws {
        let anonymousUserID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let existingUserID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let auth = FakeAuthService(
            makeUserID: { anonymousUserID },
            makeSignedInUserID: { existingUserID },
            linkIdentityError: AuthServiceError.identityAlreadyExists
        )
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

        await viewModel.linkIdentity(.apple)

        #expect(viewModel.flowState == .awaitingSignInConfirmation(.apple))
        #expect(auth.signInProviders.isEmpty)
        #expect(sync.calls.isEmpty)
        #expect(sync.localAnonymousEntryIDs == ["local-entry"])

        await viewModel.confirmSignIn()

        #expect(auth.linkIdentityProviders == [.apple])
        #expect(auth.signInProviders == [.apple])
        #expect(auth.currentUserID == existingUserID)
        #expect(auth.isAnonymous == false)
        #expect(auth.revokeOtherSessionsCount == 1)
        #expect(revokeCountWhenRestoreStarted == 1)
        #expect(sync.calls == [.preserveLocalData, .restoreAll, .finishAccountSwitch])
        #expect(sync.didPreserveLocalData)
        #expect(sync.localAnonymousEntryIDs == ["local-entry"])
        #expect(viewModel.flowState == .completed)
        #expect(viewModel.identityState == .signedIn)
    }

    @Test("identity 충돌 취소는 기존 계정 로그인이나 restore를 시작하지 않는다")
    func cancellingConflictLeavesAnonymousSessionUntouched() async throws {
        let anonymousUserID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let auth = FakeAuthService(
            makeUserID: { anonymousUserID },
            linkIdentityError: AuthServiceError.identityAlreadyExists
        )
        let sync = FakeLoginSync(localAnonymousEntryIDs: ["local-entry"])
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.linkIdentity(.google)
        viewModel.cancelSignIn()

        #expect(viewModel.flowState == .idle)
        #expect(auth.signInProviders.isEmpty)
        #expect(auth.currentUserID == anonymousUserID)
        #expect(auth.isAnonymous)
        #expect(sync.calls.isEmpty)
        #expect(sync.localAnonymousEntryIDs == ["local-entry"])
    }

    @Test("로그인 성공 뒤 restore 실패는 인증 실패와 분리하고 restore만 재시도한다")
    func restoreFailureRetriesWithoutSigningInAgain() async {
        let auth = FakeAuthService(linkIdentityError: AuthServiceError.identityAlreadyExists)
        let sync = FakeLoginSync(restoreFailuresRemaining: 1)
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.linkIdentity(.google)
        await viewModel.confirmSignIn()

        #expect(viewModel.flowState == .restoreFailed)
        #expect(viewModel.identityState == .signedIn)
        #expect(auth.signInProviders == [.google])

        await viewModel.retryRestore()

        #expect(viewModel.flowState == .completed)
        #expect(auth.signInProviders == [.google])
        #expect(sync.calls == [.preserveLocalData, .restoreAll, .finishAccountSwitch, .restoreAll])
    }

    @Test("기존 계정 signIn 실패는 이번 격리를 롤백해 이후 link push를 복구한다")
    func signInFailureRollsBackExclusionBeforeLaterLink() async {
        let auth = FakeAuthService(
            linkIdentityError: AuthServiceError.identityAlreadyExists,
            signInFailuresRemaining: 1
        )
        let sync = FakeLoginSync(localAnonymousEntryIDs: ["local-entry"])
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.linkIdentity(.google)
        await viewModel.confirmSignIn()

        #expect(viewModel.flowState == .failed)
        #expect(sync.calls == [.preserveLocalData, .rollbackAccountSwitch])
        #expect(sync.didPreserveLocalData == false)

        auth.setLinkIdentityError(nil)
        await viewModel.linkIdentity(.google)

        #expect(viewModel.flowState == .completed)
        #expect(sync.calls == [.preserveLocalData, .rollbackAccountSwitch, .pushPending])
    }

    @Test("revoke 중 계정이 바뀌면 해당 계정의 restore를 시작하지 않는다")
    func changedTargetUserAfterRevokeSkipsRestore() async {
        let auth = FakeAuthService(linkIdentityError: AuthServiceError.identityAlreadyExists)
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.linkIdentity(.google)
        auth.setRevokeOtherSessionsHandler {
            try? await auth.signOut()
        }
        await viewModel.confirmSignIn()

        #expect(auth.signInProviders == [.google])
        #expect(auth.revokeOtherSessionsCount == 1)
        #expect(sync.calls == [.preserveLocalData, .finishAccountSwitch])
        #expect(viewModel.flowState == .failed)
    }

    @Test("revoke 실패는 로그인 성공과 restore를 막지 않는다")
    func revokeFailureIsBestEffort() async {
        let auth = FakeAuthService(
            linkIdentityError: AuthServiceError.identityAlreadyExists,
            revokeOtherSessionsFailuresRemaining: 1
        )
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.linkIdentity(.apple)
        await viewModel.confirmSignIn()

        #expect(auth.revokeOtherSessionsCount == 1)
        #expect(sync.calls == [.preserveLocalData, .restoreAll, .finishAccountSwitch])
        #expect(viewModel.flowState == .completed)
    }

    @Test("오프라인 link 진입은 OAuth를 시작하지 않고 전용 안내 상태가 된다")
    func offlineLinkDoesNotStartOAuth() async {
        let auth = FakeAuthService()
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: FakeLoginSync(),
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: connectivity
        )

        await viewModel.linkIdentity(.google)

        #expect(auth.linkIdentityProviders.isEmpty)
        #expect(auth.anonymousSignInCount == 0)
        #expect(viewModel.flowState == .offline)
        #expect(viewModel.hasOfflineFailure)
    }

    @Test("충돌 확인 뒤 오프라인이 되면 보존과 기존 계정 OAuth를 시작하지 않는다")
    func offlineConfirmSignInDoesNotStartPreservationOrOAuth() async {
        let auth = FakeAuthService(linkIdentityError: AuthServiceError.identityAlreadyExists)
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: connectivity
        )

        await viewModel.linkIdentity(.apple)
        connectivity.setOnline(false)
        await viewModel.confirmSignIn()

        #expect(auth.signInProviders.isEmpty)
        #expect(sync.calls.isEmpty)
        #expect(viewModel.flowState == .offline)
    }

    @Test("사전 확인 뒤 발생한 실제 auth 네트워크 오류도 오프라인 안내로 매핑한다")
    func authNetworkErrorMapsToOfflineState() async {
        let auth = FakeAuthService(linkIdentityError: URLError(.notConnectedToInternet))
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: FakeLoginSync(),
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.linkIdentity(.google)

        #expect(auth.linkIdentityProviders == [.google])
        #expect(viewModel.flowState == .offline)
    }

    @Test("기존 계정 signIn 중 발생한 실제 네트워크 오류도 오프라인 안내로 매핑한다")
    func signInNetworkErrorMapsToOfflineState() async {
        let auth = FakeAuthService(
            linkIdentityError: AuthServiceError.identityAlreadyExists,
            signInError: URLError(.networkConnectionLost)
        )
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.linkIdentity(.google)
        await viewModel.confirmSignIn()

        #expect(auth.signInProviders == [.google])
        #expect(sync.calls == [.preserveLocalData, .rollbackAccountSwitch])
        #expect(viewModel.flowState == .offline)
    }
}

@MainActor
extension LoginViewModelTests {
    @Test("link 성공 뒤 revoke 중 계정이 바뀌면 pending push를 시작하지 않는다")
    func changedTargetUserAfterRevokeSkipsPushOnLinkPath() async {
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
        await viewModel.linkIdentity(.google)

        #expect(auth.linkIdentityProviders == [.google])
        #expect(auth.revokeOtherSessionsCount == 1)
        #expect(sync.calls.isEmpty)
        #expect(viewModel.flowState == .failed)
    }

    @Test("restore 재시도 시 계정이 바뀌면 restore를 다시 시작하지 않는다")
    func retryRestoreSkipsWhenTargetUserChanged() async {
        let auth = FakeAuthService(linkIdentityError: AuthServiceError.identityAlreadyExists)
        let sync = FakeLoginSync(restoreFailuresRemaining: 1)
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.linkIdentity(.google)
        await viewModel.confirmSignIn()
        #expect(viewModel.flowState == .restoreFailed)

        try? await auth.signOut()
        await viewModel.retryRestore()

        #expect(viewModel.flowState == .failed)
        #expect(sync.calls == [.preserveLocalData, .restoreAll, .finishAccountSwitch])
    }

    @Test("연결성과 무관한 URLError는 오프라인이 아닌 일반 실패로 남는다")
    func nonConnectivityURLErrorStaysFailed() async {
        let auth = FakeAuthService(linkIdentityError: URLError(.badServerResponse))
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: FakeLoginSync(),
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true)
        )

        await viewModel.linkIdentity(.google)

        #expect(auth.linkIdentityProviders == [.google])
        #expect(viewModel.flowState == .failed)
    }
}

@MainActor
private final class FakeLoginSync: LoginSyncing {
    enum Call: Equatable {
        case preserveLocalData
        case rollbackAccountSwitch
        case finishAccountSwitch
        case pushPending
        case restoreAll
    }

    private(set) var calls: [Call] = []
    private(set) var localAnonymousEntryIDs: [String]
    private(set) var didPreserveLocalData = false
    private var restoreFailuresRemaining: Int
    private let pushPendingHandler: (() -> Void)?
    private let restoreAllHandler: (() -> Void)?

    init(
        localAnonymousEntryIDs: [String] = [],
        restoreFailuresRemaining: Int = 0,
        pushPendingHandler: (() -> Void)? = nil,
        restoreAllHandler: (() -> Void)? = nil
    ) {
        self.localAnonymousEntryIDs = localAnonymousEntryIDs
        self.restoreFailuresRemaining = restoreFailuresRemaining
        self.pushPendingHandler = pushPendingHandler
        self.restoreAllHandler = restoreAllHandler
    }

    func preserveLocalDataForAccountSwitch() async throws -> UUID {
        calls.append(.preserveLocalData)
        didPreserveLocalData = true
        return try #require(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
    }

    func rollbackLocalDataPreservation(batchID _: UUID) async throws {
        calls.append(.rollbackAccountSwitch)
        didPreserveLocalData = false
    }

    func finishAccountSwitch() {
        calls.append(.finishAccountSwitch)
    }

    func pushPending() async {
        pushPendingHandler?()
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
}

private enum FakeLoginSyncError: Error {
    case restoreFailed
}
