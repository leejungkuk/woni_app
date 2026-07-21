//
//  SessionTransitionCoordinator.swift
//  woni_app
//

import Foundation
import Observation

@MainActor
protocol LogoutSyncing: AnyObject {
    func pushPending() async
    func suspendPushForLogout() async
    func resumePushAfterLogout()
}

extension SyncEngine: LogoutSyncing {}

@MainActor
protocol LogoutDataProviding {
    func hasUnsyncedEntriesForLogout() async throws -> Bool
    func clearForLogout(force: Bool) async throws
}

extension TransactionRepository: LogoutDataProviding {}

@MainActor
protocol LogoutCleanupMarking: AnyObject {
    var isPending: Bool { get }
    func markPending()
    func clear()
}

@MainActor
final class LogoutCleanupMarker: LogoutCleanupMarking {
    private static let pendingKey = "woni.logout-cleanup-pending"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isPending: Bool {
        defaults.bool(forKey: Self.pendingKey)
    }

    func markPending() {
        defaults.set(true, forKey: Self.pendingKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.pendingKey)
    }
}

@MainActor
final class InMemoryLogoutCleanupMarker: LogoutCleanupMarking {
    private(set) var isPending = false

    func markPending() {
        isPending = true
    }

    func clear() {
        isPending = false
    }
}

@MainActor
@Observable
final class SessionTransitionCoordinator {
    enum LogoutState: Equatable {
        case idle
        case syncing
        case awaitingUnsyncedConfirmation
        case signingOut
        case completed
        case failed
        case cleanupRequired
    }

    private enum TransitionKind {
        case logout
        case accountSwitch
    }

    private let repository: any LogoutDataProviding
    private let authProvider: any AuthProviding
    private let connectivity: any ConnectivityObserving
    private let sync: any LogoutSyncing
    private let cleanupMarker: any LogoutCleanupMarking

    private var activeKind: TransitionKind?
    private var activeTask: Task<Void, Never>?
    private var activeTransitionID: UUID?

    private(set) var logoutState: LogoutState = .idle

    init(
        repository: any LogoutDataProviding,
        authProvider: any AuthProviding,
        connectivity: any ConnectivityObserving,
        sync: any LogoutSyncing,
        cleanupMarker: any LogoutCleanupMarking
    ) {
        self.repository = repository
        self.authProvider = authProvider
        self.connectivity = connectivity
        self.sync = sync
        self.cleanupMarker = cleanupMarker
        if cleanupMarker.isPending {
            logoutState = .cleanupRequired
        }
    }

    var isLoggingOut: Bool {
        logoutState == .syncing || logoutState == .signingOut
    }

    var hasUnsyncedLogoutWarning: Bool {
        logoutState == .awaitingUnsyncedConfirmation
    }

    var hasLogoutFailure: Bool {
        logoutState == .failed
    }

    var needsCleanup: Bool {
        logoutState == .cleanupRequired
    }

    var isLoginBlocked: Bool {
        isLoggingOut || needsCleanup
    }

    func requestLogout() async {
        guard !isLoggingOut,
              logoutState != .awaitingUnsyncedConfirmation,
              logoutState != .cleanupRequired
        else {
            return
        }
        logoutState = .syncing

        await runLogout { [self] in
            do {
                let hasPendingEntries = try await repository.hasUnsyncedEntriesForLogout()
                if hasPendingEntries, !connectivity.isOnline {
                    logoutState = .awaitingUnsyncedConfirmation
                    return
                }

                if hasPendingEntries {
                    await sync.pushPending()
                }

                await performLogout(force: false)
            } catch {
                logoutState = .failed
            }
        }
    }

    func confirmForcedLogout() async {
        guard hasUnsyncedLogoutWarning else {
            return
        }
        await runLogout { [self] in
            await performLogout(force: true)
        }
    }

    func cancelForcedLogout() {
        guard hasUnsyncedLogoutWarning else {
            return
        }
        logoutState = .idle
    }

    func dismissLogoutFailure() {
        guard hasLogoutFailure else {
            return
        }
        logoutState = .idle
    }

    func retryCleanup() async {
        guard needsCleanup else {
            return
        }
        await runLogout { [self] in
            await performLogout(force: true)
        }
    }

    func runAccountSwitchTransition(
        _ body: @escaping @MainActor () async -> Void
    ) async {
        if activeKind == .accountSwitch, let task = activeTask {
            await task.value
            return
        }

        let prior = activeTask
        let transitionID = UUID()
        let task = Task { @MainActor [self, prior] in
            if let prior {
                await prior.value
            }
            await body()
            clearTransition(ifCurrent: transitionID)
        }
        activeKind = .accountSwitch
        activeTask = task
        activeTransitionID = transitionID
        await task.value
        clearTransition(ifCurrent: transitionID)
    }
}

private extension SessionTransitionCoordinator {
    func runLogout(_ body: @escaping @MainActor () async -> Void) async {
        if activeKind == .logout, let task = activeTask {
            await task.value
            return
        }

        let prior = activeTask
        let transitionID = UUID()
        let task = Task { @MainActor [self, prior] in
            if let prior {
                await prior.value
            }
            await body()
            clearTransition(ifCurrent: transitionID)
        }
        activeKind = .logout
        activeTask = task
        activeTransitionID = transitionID
        await task.value
        clearTransition(ifCurrent: transitionID)
    }

    func clearTransition(ifCurrent transitionID: UUID) {
        guard activeTransitionID == transitionID else {
            return
        }
        activeKind = nil
        activeTask = nil
        activeTransitionID = nil
    }

    func performLogout(force: Bool) async {
        logoutState = .signingOut
        await sync.suspendPushForLogout()
        var didClearLocalData = false

        do {
            if !force {
                let hasUnsyncedEntries = try await repository.hasUnsyncedEntriesForLogout()
                if hasUnsyncedEntries {
                    logoutState = .awaitingUnsyncedConfirmation
                    sync.resumePushAfterLogout()
                    return
                }
            }
            cleanupMarker.markPending()
            if authProvider.currentUserID != nil {
                try await authProvider.signOut()
            }
            try await repository.clearForLogout(force: force)
            didClearLocalData = true
            cleanupMarker.clear()
            if connectivity.isOnline {
                try await authProvider.ensureIdentity()
            }
            logoutState = .completed
        } catch LogoutDataError.unsyncedEntriesRemain {
            // 방어적 경로: 사전 체크와 suspendPushForLogout의 쓰기 정지 때문에 현재 코드에서는
            // 도달하지 않는다. 도달한다면 이미 markPending·sign-out이 지나 세션이 소멸했을 수
            // 있으므로, 멤버 로컬 데이터가 남은 채 로그인/push가 재개되지 않도록 격리를 유지한다
            // (아래 else와 동일한 cleanup-required: 로그인 차단·push 정지·마커 pending →
            // 재시작 시 recoverIncompleteLogout이 완결). marker clear·resume을 하지 않는다.
            logoutState = .cleanupRequired
            return
        } catch {
            // 실패 "단계"가 아니라 현재 상태(세션 생존 여부 + 로컬 정리 완료 여부)로 분기한다.
            // 세션 생존(currentUserID)이 "멤버로 계속 안전하게 push할 수 있는가"의 SSOT이기 때문이다.
            if authProvider.currentUserID != nil {
                // 세션이 아직 살아있는 경우. sign-out 이전 pending 조회 실패가 주된 경로이고,
                // sign-out이 세션을 유지한 채 실패한 경우도 포함한다(Supabase는 대개 로컬 세션을
                // 먼저 제거하므로 sign-out 실패는 보통 아래 else로 간다). 멤버로 계속 쓸 수 있으므로
                // 로그아웃 의도를 철회해 정상 쓰기를 재개하고, 재시작 force-clear 마커도 제거한다.
                cleanupMarker.clear()
                sync.resumePushAfterLogout()
                logoutState = .failed
            } else if didClearLocalData {
                // 세션 소멸 + 로컬 clear·마커 해제까지 끝났고 이후(익명 재발급)만 실패한 경우.
                // 로그아웃이 성립했으므로 쓰기를 재개한다(익명 신원은 다음 online에 지연 발급).
                sync.resumePushAfterLogout()
                logoutState = .failed
            } else {
                // 세션은 소멸했으나 로컬 clear가 아직 안 된 경우(clear 실패, 또는 sign-out이 로컬
                // 세션을 제거한 뒤 throw해 clear에 이르지 못한 경우). 남은 멤버 로컬 데이터가 새 익명
                // 신원으로 전송되지 않도록 push 정지를 유지한다(resume 호출 안 함 → 마커 pending 유지
                // → 재시작 시 recoverIncompleteLogout이 완결). 로그인 진입을 막아 데이터 혼합을
                // 방지하고, 세션 내 cleanup 재시도(retryCleanup) 경로를 노출한다.
                logoutState = .cleanupRequired
            }
            return
        }

        sync.resumePushAfterLogout()
    }
}
