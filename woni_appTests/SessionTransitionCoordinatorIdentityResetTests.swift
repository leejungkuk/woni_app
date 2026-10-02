//
//  SessionTransitionCoordinatorIdentityResetTests.swift
//  woni_appTests
//
//  신원 리셋 세대. 루트는 이 값 하나로 계정이 바뀐 뒤 통계 탭을 이번 달 첫 화면부터 다시 연다 —
//  로그아웃 정리는 원장 변경 신호를 내지 않아 이것이 없으면 이전 계정 집계가 남는다.
//

import Foundation
import Testing
@testable import woni_app

@MainActor
struct SessionTransitionCoordinatorIdentityResetTests {
    @Test("로그아웃은 로컬 정리가 끝나야 세대를 올린다 — 정리 실패는 그대로이고 재시도 성공에서 오른다")
    func logoutBumpsGenerationOnlyAfterLocalCleanup() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let cleanup = FailingOnceCleanup()
        let coordinator = makeTestSessionCoordinator(authProvider: auth, onLogoutCleanup: cleanup.run)

        await coordinator.requestLogout()

        #expect(coordinator.needsCleanup)
        #expect(coordinator.identityResetGeneration == 0)

        await coordinator.retryCleanup()

        #expect(coordinator.logoutState == .completed)
        #expect(coordinator.identityResetGeneration == 1)
    }

    @Test("원격 로그아웃은 정리를 마치면 세대를 올린다")
    func remoteLogoutBumpsGeneration() async throws {
        let auth = FakeAuthService()
        try await auth.signIn(.google)
        let coordinator = makeTestSessionCoordinator(authProvider: auth)

        auth.simulateRemoteInvalidation()
        await waitUntil { coordinator.remoteLogoutNotice }

        #expect(coordinator.identityResetGeneration == 1)
    }

    @Test("탈퇴 정리는 신원이 없는 비회원이어도 로컬을 비우면 세대를 올린다")
    func withdrawalCleanupWithoutIdentityBumpsGeneration() async {
        let coordinator = makeTestSessionCoordinator(authProvider: FakeAuthService())

        let didCleanUp = await coordinator.performWithdrawalCleanup()

        #expect(didCleanUp)
        #expect(coordinator.identityResetGeneration == 1)
    }

    @Test("계정 전환은 신원이 바뀐 경우에만 세대를 올린다 — 취소처럼 그대로면 오르지 않는다")
    func accountSwitchBumpsGenerationOnlyWhenIdentityChanges() async throws {
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let coordinator = makeTestSessionCoordinator(authProvider: auth)

        await coordinator.runAccountSwitchTransition {}

        #expect(coordinator.identityResetGeneration == 0)

        await coordinator.runAccountSwitchTransition {
            try? await auth.signIn(.apple)
        }

        #expect(coordinator.identityResetGeneration == 1)
    }
}

/// 첫 정리만 실패시켜 cleanup-required 를 만든 뒤 재시도는 통과시킨다.
@MainActor
private final class FailingOnceCleanup {
    private var failuresRemaining = 1

    func run() async throws {
        guard failuresRemaining > 0 else {
            return
        }
        failuresRemaining -= 1
        throw FailingOnceCleanupError.programmedFailure
    }
}

private enum FailingOnceCleanupError: Error {
    case programmedFailure
}
