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
        let sync = FakeLoginSync()
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth)
        )

        await viewModel.linkIdentity(.google)

        #expect(auth.linkIdentityProviders == [.google])
        #expect(auth.signInProviders.isEmpty)
        #expect(auth.anonymousSignInCount == 1)
        #expect(auth.currentUserID == anonymousUserID)
        #expect(auth.isAnonymous == false)
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
        let sync = FakeLoginSync(localAnonymousEntryIDs: ["local-entry"])
        let viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth)
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
            coordinator: makeTestSessionCoordinator(authProvider: auth)
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
            coordinator: makeTestSessionCoordinator(authProvider: auth)
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
            coordinator: makeTestSessionCoordinator(authProvider: auth)
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

    init(localAnonymousEntryIDs: [String] = [], restoreFailuresRemaining: Int = 0) {
        self.localAnonymousEntryIDs = localAnonymousEntryIDs
        self.restoreFailuresRemaining = restoreFailuresRemaining
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
        calls.append(.pushPending)
    }

    func restoreAll() async throws {
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
