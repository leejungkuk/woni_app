//
//  SessionTransitionTestSupport.swift
//  woni_appTests
//

import Foundation
@testable import woni_app

@MainActor
func makeTestSessionCoordinator(
    authProvider: any AuthProviding,
    repository: (any LogoutDataProviding)? = nil,
    connectivity: (any ConnectivityObserving)? = nil,
    logoutSync: (any LogoutSyncing)? = nil,
    cleanupMarker: (any LogoutCleanupMarking)? = nil
) -> SessionTransitionCoordinator {
    SessionTransitionCoordinator(
        repository: repository ?? NoopTestLogoutRepository(),
        authProvider: authProvider,
        connectivity: connectivity ?? FakeConnectivityMonitor(isOnline: true),
        sync: logoutSync ?? NoopTestLogoutSync(),
        cleanupMarker: cleanupMarker ?? InMemoryLogoutCleanupMarker()
    )
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
