//
//  SessionTransitionTestSupport.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@MainActor
func makeTestSessionCoordinator(
    authProvider: any AuthProviding,
    repository: (any LogoutDataProviding)? = nil,
    connectivity: (any ConnectivityObserving)? = nil,
    logoutSync: (any LogoutSyncing)? = nil,
    cleanupMarker: (any LogoutCleanupMarking)? = nil,
    onLogoutCleanup: @escaping @MainActor () async throws -> Void = {}
) -> SessionTransitionCoordinator {
    SessionTransitionCoordinator(
        repository: repository ?? NoopTestLogoutRepository(),
        authProvider: authProvider,
        connectivity: connectivity ?? FakeConnectivityMonitor(isOnline: true),
        sync: logoutSync ?? NoopTestLogoutSync(),
        cleanupMarker: cleanupMarker ?? InMemoryLogoutCleanupMarker(),
        onLogoutCleanup: onLogoutCleanup
    )
}

/// 조건이 성립할 때까지 기다린다. `await Task.yield()` 한 번은 대기 중인 task에게 실행 기회를
/// 주지만 **몇 개나** 진행되는지 보장하지 않아, 관찰자가 둘 이상이면 부하에 따라 결과가 갈린다
/// (실측 2026-08-08: 전체 스위트 부하에서 2회 재현, 단독 실행 10회는 전부 통과).
/// 조건 기반으로 기다려 실행 순서에 의존하지 않게 한다.
/// 소진되면 반드시 실패로 남긴다. 조용히 반환하면 조건이 성립하지 않은 채 다음 단계로 넘어가
/// 최종 단언만 우연히 통과하는 거짓 그린이 된다 — 대기가 무의미해지는 지점이 바로 여기다.
@MainActor
func waitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0 ..< 1000 {
        if condition() {
            return
        }
        await Task.yield()
    }
    Issue.record("조건이 제한 시간 안에 성립하지 않았습니다.", sourceLocation: sourceLocation)
}

@MainActor
private struct NoopTestLogoutRepository: LogoutDataProviding {
    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        false
    }

    func clearForLogout(force _: Bool) async throws {}
}

@MainActor
private final class NoopTestLogoutSync: LogoutSyncing {
    func pushPending() async {}
    func suspendPushForLogout() async {}
    func resumePushAfterLogout() {}
}
