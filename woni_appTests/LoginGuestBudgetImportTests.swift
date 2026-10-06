//
//  LoginGuestBudgetImportTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 회원 세션의 토큰과 로그인 직전에 갱신해 쥔 비회원 토큰. 서로 달라야 옮기기가 어느 쪽을 실었는지 가려진다.
private let memberToken = "member-session-value"
private let guestToken = "guest-refreshed-value"

/// 로그인 흐름에 끼운 비회원 예산 옮기기. 동기화·옮기기·삭제·완료가 한 기록을 공유해
/// "`finishAccountSwitch` 뒤"·"삭제 앞" 같은 순서를 단언한다.
@MainActor
struct LoginGuestBudgetImportTests {
    @Test("GBI.S1-R1 비회원→회원 로그인은 finishAccountSwitch 뒤 비회원 토큰으로 한 번 옮기고 그 뒤에만 비회원 계정을 지운다")
    func guestSignInImportsBeforeDeletingGuestAccount() async throws {
        let fixture = try await LoginFixture.guest()

        await fixture.viewModel.signIn(.google)

        let memberID = try #require(fixture.auth.currentUserID)
        #expect(fixture.viewModel.flowState == .completed)
        #expect(fixture.log.steps == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(memberID),
            .importGuestBudget(guestToken),
            .signInCompleted,
            .deleteAnonymousAccount(guestToken)
        ])
    }

    @Test("GBI.S1-R1 옮기기가 실패하면 비회원 계정을 지우지 않고 복원 실패 창을 연다")
    func importFailureKeepsGuestAccountAndOpensRetryAlert() async throws {
        let fixture = try await LoginFixture.guest()
        fixture.importer.failuresRemaining = 1

        await fixture.viewModel.signIn(.google)

        let memberID = try #require(fixture.auth.currentUserID)
        // 완료는 곧 비회원 계정 삭제이고, 삭제는 cascade 로 예산까지 지운다(요청서 §2 결정 4).
        #expect(fixture.viewModel.flowState == .restoreFailed)
        #expect(fixture.viewModel.hasRestoreFailure)
        #expect(fixture.log.steps == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(memberID),
            .importGuestBudget(guestToken)
        ])
    }

    @Test("GBI.S1-R1 finishAccountSwitch 가 false 면 옮기지도 지우지도 않고 실패한다")
    func identityDriftSkipsImport() async throws {
        let fixture = try await LoginFixture.guest()
        fixture.sync.finishAccountSwitchResult = false

        await fixture.viewModel.signIn(.google)

        let memberID = try #require(fixture.auth.currentUserID)
        // 옮기면 지금 토큰의 다른 계정으로 비회원 예산이 복사되고 되돌릴 수 없다.
        #expect(fixture.viewModel.flowState == .failed)
        #expect(fixture.log.steps == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(memberID),
            .resumeAccountSwitch(memberID)
        ])
    }

    @Test("GBI.S1-R2 옮기기 실패 뒤 다시 시도는 restoreAll 없이 finishAccountSwitch 와 옮기기만 다시 하고 성공하면 지운다")
    func retryAfterImportFailureSkipsRestore() async throws {
        let fixture = try await LoginFixture.guest()
        fixture.importer.failuresRemaining = 1

        await fixture.viewModel.signIn(.google)
        await fixture.viewModel.retryRestore()

        let memberID = try #require(fixture.auth.currentUserID)
        #expect(fixture.viewModel.flowState == .completed)
        // push 가 이미 살아 있어 restoreAll 의 전체 덮어쓰기를 다시 돌리지 않는다 — restoreAll 은 한 번뿐이다.
        #expect(fixture.log.steps == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(memberID),
            .importGuestBudget(guestToken),
            .finishAccountSwitch(memberID),
            .importGuestBudget(guestToken),
            .signInCompleted,
            .deleteAnonymousAccount(guestToken)
        ])
    }

    @Test("GBI.S1-R2 다시 시도의 옮기기가 또 실패하면 지우지 않고 창을 다시 열며 한 번 더 다시 시도할 수 있다")
    func repeatedImportFailureKeepsRetryOpen() async throws {
        let fixture = try await LoginFixture.guest()
        fixture.importer.failuresRemaining = 2

        await fixture.viewModel.signIn(.google)
        await fixture.viewModel.retryRestore()

        let memberID = try #require(fixture.auth.currentUserID)
        let failedSteps: [LoginStepLog.Step] = [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(memberID),
            .importGuestBudget(guestToken),
            .finishAccountSwitch(memberID),
            .importGuestBudget(guestToken)
        ]
        #expect(fixture.viewModel.flowState == .restoreFailed)
        #expect(fixture.log.steps == failedSteps)

        await fixture.viewModel.retryRestore()

        #expect(fixture.viewModel.flowState == .completed)
        #expect(fixture.log.steps == failedSteps + [
            .finishAccountSwitch(memberID),
            .importGuestBudget(guestToken),
            .signInCompleted,
            .deleteAnonymousAccount(guestToken)
        ])
    }

    @Test("GBI.S1-R2 옮기기 실패 뒤 다시 시도의 finishAccountSwitch 가 false 면 옮기지 않고 실패한다")
    func retryIdentityDriftSkipsImport() async throws {
        let fixture = try await LoginFixture.guest()
        fixture.importer.failuresRemaining = 1

        await fixture.viewModel.signIn(.google)
        fixture.sync.finishAccountSwitchResult = false
        await fixture.viewModel.retryRestore()

        let memberID = try #require(fixture.auth.currentUserID)
        #expect(fixture.viewModel.flowState == .failed)
        #expect(fixture.log.steps == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(memberID),
            .importGuestBudget(guestToken),
            .finishAccountSwitch(memberID),
            .resumeAccountSwitch(memberID)
        ])
    }

    @Test("GBI.S1-R3 옮기기 실패 뒤 닫기는 옮기기를 더 부르지 않고 비회원 계정을 남긴 채 완료한다")
    func closeAfterImportFailureKeepsGuestAccount() async throws {
        let fixture = try await LoginFixture.guest()
        fixture.importer.failuresRemaining = 1

        await fixture.viewModel.signIn(.google)
        await fixture.viewModel.finishAfterRestoreFailure()
        // 창이 닫힌 뒤의 다시 시도는 아무것도 하지 않는다.
        await fixture.viewModel.retryRestore()

        let memberID = try #require(fixture.auth.currentUserID)
        #expect(fixture.viewModel.flowState == .completed)
        #expect(fixture.log.steps == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(memberID),
            .importGuestBudget(guestToken),
            .resumeAccountSwitch(memberID),
            .signInCompleted
        ])
    }

    @Test("GBI.S1-R4 스냅샷이 없으면 옮기지 않고 지금 흐름대로 완료한다")
    func missingSnapshotSkipsImport() async throws {
        // 세션이 없어 로그인 직전 토큰 갱신이 nil 이다 — 스냅샷이 없다.
        let fixture = LoginFixture(auth: FakeAuthService(initialValue: memberToken, refreshedValue: guestToken))

        await fixture.viewModel.signIn(.google)

        let memberID = try #require(fixture.auth.currentUserID)
        #expect(fixture.viewModel.flowState == .completed)
        #expect(fixture.log.steps == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(memberID),
            .signInCompleted
        ])
    }

    @Test("GBI.S1-R4 회원에서 회원으로 바뀐 로그인은 옮기지 않고 지금 흐름대로 완료한다")
    func memberSnapshotSkipsImport() async throws {
        let auth = FakeAuthService(initialValue: memberToken, refreshedValue: guestToken)
        try await auth.signIn(.apple)
        let fixture = LoginFixture(auth: auth)

        await fixture.viewModel.signIn(.google)

        let memberID = try #require(fixture.auth.currentUserID)
        #expect(fixture.viewModel.flowState == .completed)
        #expect(fixture.log.steps == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(memberID),
            .signInCompleted
        ])
    }

    @Test("GBI.S1-R4 신원이 바뀌지 않은 로그인은 옮기지 않고 지금 흐름대로 완료한다")
    func unchangedIdentitySkipsImport() async throws {
        let sharedUserID = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let auth = FakeAuthService(
            makeUserID: { sharedUserID },
            makeSignedInUserID: { sharedUserID },
            initialValue: memberToken,
            refreshedValue: guestToken
        )
        try await auth.ensureIdentity()
        let fixture = LoginFixture(auth: auth)

        await fixture.viewModel.signIn(.google)

        #expect(fixture.viewModel.flowState == .completed)
        #expect(fixture.log.steps == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(sharedUserID),
            .signInCompleted
        ])
    }

    @Test("GBI.S1-R5 restoreAll 이 실패하면 옮기지 않고, 다시 시도는 restoreAll 부터 한 뒤 옮긴다")
    func restoreFailureRetriesRestoreBeforeImport() async throws {
        let fixture = try await LoginFixture.guest()
        fixture.sync.restoreFailuresRemaining = 1

        await fixture.viewModel.signIn(.google)

        let restoreFailedSteps: [LoginStepLog.Step] = [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll
        ]
        #expect(fixture.viewModel.flowState == .restoreFailed)
        #expect(fixture.log.steps == restoreFailedSteps)

        await fixture.viewModel.retryRestore()

        let memberID = try #require(fixture.auth.currentUserID)
        #expect(fixture.viewModel.flowState == .completed)
        #expect(fixture.log.steps == restoreFailedSteps + [
            .restoreAll,
            .finishAccountSwitch(memberID),
            .importGuestBudget(guestToken),
            .signInCompleted,
            .deleteAnonymousAccount(guestToken)
        ])
    }

    @Test("GBI.S1-R5 옮기기 실패를 닫기로 끝낸 뒤 다음 로그인의 복원 실패는 다시 시도에서 restoreAll 부터 한다")
    func closedImportFailureDoesNotLeakIntoNextRestoreRetry() async throws {
        let fixture = try await LoginFixture.guest()
        fixture.importer.failuresRemaining = 1
        await fixture.viewModel.signIn(.google)
        await fixture.viewModel.finishAfterRestoreFailure()
        let firstMemberID = try #require(fixture.auth.currentUserID)

        fixture.sync.restoreFailuresRemaining = 1
        await fixture.viewModel.signIn(.apple)
        await fixture.viewModel.retryRestore()

        let secondMemberID = try #require(fixture.auth.currentUserID)
        #expect(fixture.viewModel.flowState == .completed)
        #expect(fixture.log.steps == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .finishAccountSwitch(firstMemberID),
            .importGuestBudget(guestToken),
            .resumeAccountSwitch(firstMemberID),
            .signInCompleted,
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreAll,
            .restoreAll,
            .finishAccountSwitch(secondMemberID),
            .signInCompleted
        ])
    }
}

/// 동기화·옮기기·삭제·완료가 함께 쓰는 기록.
@MainActor
private final class LoginStepLog {
    enum Step: Equatable {
        case beginAccountSwitch
        case resetSyncStateForAccountSwitch
        case restoreAll
        case finishAccountSwitch(UUID)
        case resumeAccountSwitch(UUID?)
        case pushPending
        case importGuestBudget(String)
        case signInCompleted
        case deleteAnonymousAccount(String)
    }

    private(set) var steps: [Step] = []

    func record(_ step: Step) {
        steps.append(step)
    }
}

@MainActor
private struct LoginFixture {
    let auth: FakeAuthService
    let log: LoginStepLog
    let sync: RecordingLoginSync
    let importer: RecordingGuestBudgetImporter
    let viewModel: LoginViewModel

    init(auth: FakeAuthService) {
        let log = LoginStepLog()
        self.auth = auth
        self.log = log
        sync = RecordingLoginSync(log: log)
        importer = RecordingGuestBudgetImporter(log: log)
        viewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: makeTestSessionCoordinator(authProvider: auth),
            connectivity: FakeConnectivityMonitor(isOnline: true),
            anonymousAccountDeleter: RecordingAnonymousAccountDeleter(log: log),
            guestBudgetImporter: importer,
            onSignInCompleted: { log.record(.signInCompleted) }
        )
    }

    /// 비회원 세션에서 시작한다 — 로그인 직전 캡처가 비회원 토큰을 갱신해 쥔다.
    static func guest() async throws -> LoginFixture {
        let auth = FakeAuthService(initialValue: memberToken, refreshedValue: guestToken)
        try await auth.ensureIdentity()
        return LoginFixture(auth: auth)
    }
}

@MainActor
private final class RecordingLoginSync: LoginSyncing {
    private let log: LoginStepLog
    var restoreFailuresRemaining = 0
    /// 호출마다 바꿀 수 있다 — 처음 `true`, 다시 시도에서 `false` 같은 갈래를 만든다.
    var finishAccountSwitchResult = true

    init(log: LoginStepLog) {
        self.log = log
    }

    func beginAccountSwitch() async throws {
        log.record(.beginAccountSwitch)
    }

    func finishAccountSwitch(expectedMemberID: UUID) async -> Bool {
        log.record(.finishAccountSwitch(expectedMemberID))
        return finishAccountSwitchResult
    }

    func resumeAccountSwitch(expectedMemberID: UUID?) -> Bool {
        log.record(.resumeAccountSwitch(expectedMemberID))
        return true
    }

    func pushPending() async {
        log.record(.pushPending)
    }

    func restoreAll() async throws {
        log.record(.restoreAll)
        if restoreFailuresRemaining > 0 {
            restoreFailuresRemaining -= 1
            throw RecordingLoginSyncError.restoreFailed
        }
    }

    func resetSyncStateForAccountSwitch() async throws {
        log.record(.resetSyncStateForAccountSwitch)
    }

    func hasPendingPush() async throws -> Bool {
        false
    }
}

private enum RecordingLoginSyncError: Error {
    case restoreFailed
}

@MainActor
private final class RecordingGuestBudgetImporter: GuestBudgetImporting {
    private let log: LoginStepLog
    var failuresRemaining = 0

    init(log: LoginStepLog) {
        self.log = log
    }

    func importGuestBudget(guestAccessToken: String) async throws {
        log.record(.importGuestBudget(guestAccessToken))
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw GuestBudgetImportError.incompleteCategoryMapping
        }
    }
}

@MainActor
private final class RecordingAnonymousAccountDeleter: AnonymousAccountDeleting {
    private let log: LoginStepLog

    init(log: LoginStepLog) {
        self.log = log
    }

    func deleteAccount(accessToken: String) async throws {
        log.record(.deleteAnonymousAccount(accessToken))
    }
}
