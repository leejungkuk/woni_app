//
//  DataPurgeCoordinator.swift
//  woni_app
//

import Foundation
import Observation

protocol PurgeStateStoring {
    func markPurgePending(memberID: String) async throws
    func purgePendingMemberID() async throws -> String?
    func clearPurgeMarker() async throws
    func clearForPurge() async throws
}

/// purge 전용 suspend 게이트. `LogoutSyncing`의 boolean suspension은 로그아웃·계정 전환의
/// resume 경로가 되돌리므로, completionPending 중 그 전이가 끼어들어도 purge 게이트가
/// 유지되도록 별도 표면으로 분리한다.
@MainActor
protocol PurgeSyncing: AnyObject {
    func suspendPushForPurge() async
    func resumePushAfterPurge() async
}

extension SyncEngine: PurgeSyncing {}

@MainActor
@Observable
final class DataPurgeCoordinator {
    enum PurgeState: Equatable {
        case idle
        case awaitingConfirmation
        case deleting
        case completionPending(acknowledged: Bool)
        case completed
        case failed
        case offline
    }

    private enum FailureKind: Equatable {
        case retryableConfirmed
        case terminalConfirmed
        case ambiguous
    }

    private let session: SessionTransitionCoordinator
    private let purgeSync: any PurgeSyncing
    private let purgeStore: any PurgeStateStoring
    private let ledgerService: any LedgerPurging
    private let authProvider: any AuthProviding
    private let connectivity: any ConnectivityObserving
    private let onDataCleared: () -> Void
    private let retrySleep: (Duration) async -> Void
    private let maxAmbiguousRetries: Int
    @ObservationIgnored private var connectivityTask: Task<Void, Never>?

    private(set) var state: PurgeState = .idle

    init(
        session: SessionTransitionCoordinator,
        purgeSync: any PurgeSyncing,
        purgeStore: any PurgeStateStoring,
        ledgerService: any LedgerPurging,
        authProvider: any AuthProviding,
        connectivity: any ConnectivityObserving,
        onDataCleared: @escaping () -> Void,
        retrySleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        maxAmbiguousRetries: Int = 3
    ) {
        self.session = session
        self.purgeSync = purgeSync
        self.purgeStore = purgeStore
        self.ledgerService = ledgerService
        self.authProvider = authProvider
        self.connectivity = connectivity
        self.onDataCleared = onDataCleared
        self.retrySleep = retrySleep
        self.maxAmbiguousRetries = max(0, maxAmbiguousRetries)

        let changes = connectivity.changes
        connectivityTask = Task { @MainActor [weak self] in
            for await isOnline in changes {
                guard !Task.isCancelled else { return }
                if isOnline {
                    await self?.resumeIfPending()
                }
            }
        }
    }

    deinit {
        connectivityTask?.cancel()
    }

    var isBlockingOtherEntry: Bool {
        switch state {
        case .idle, .offline, .awaitingConfirmation, .completionPending:
            false
        case .deleting, .completed, .failed:
            true
        }
    }

    func prepare() {
        guard connectivity.isOnline else {
            state = .offline
            return
        }
        state = .awaitingConfirmation
    }

    func confirm() async {
        guard state == .awaitingConfirmation else { return }
        // 삭제 대상 신원은 확인 시점에 캡처한다. 큐 대기 중 로그아웃·계정 전환이 끼어들면
        // 실행 시점 신원으로 DELETE가 나가므로, body는 캡처와 일치할 때만 진행한다.
        guard let memberID = authProvider.currentUserID, !authProvider.isAnonymous else {
            state = .failed
            return
        }
        while state == .awaitingConfirmation {
            var didRun = false
            await session.runPurge { [self] in
                didRun = true
                guard authProvider.currentUserID == memberID else {
                    state = .failed
                    return
                }
                state = .deleting
                await performPurge(
                    memberID: memberID,
                    possiblyDeleted: false,
                    pendingAcknowledged: false
                )
            }
            if didRun { return }
        }
    }

    func cancel() {
        guard state == .awaitingConfirmation else { return }
        state = .idle
    }

    func acknowledgePending() {
        guard case .completionPending = state else { return }
        state = .completionPending(acknowledged: true)
    }

    func acknowledgeCompletion() {
        guard state == .completed else { return }
        state = .idle
    }

    func dismissFailure() {
        guard state == .failed else { return }
        state = .idle
    }

    func dismissOffline() {
        guard state == .offline else { return }
        state = .idle
    }

    func resumeIfPending() async {
        await session.runPurge { [self] in
            let acknowledged = pendingAcknowledged
            let marker: String
            do {
                guard let pendingMemberID = try await purgeStore.purgePendingMemberID() else {
                    if case .completionPending = state {
                        state = .idle
                    }
                    return
                }
                marker = pendingMemberID
            } catch {
                setPendingIfResumeOwnsState(acknowledged: acknowledged)
                return
            }

            guard authProvider.currentUserID?.uuidString == marker else {
                do {
                    try await purgeStore.clearPurgeMarker()
                    clearPendingIfResumeOwnsState()
                    // 포기한 purge가 닫아둔 게이트(재시작 startSuspended 포함)를 되돌려
                    // 새 신원의 push가 영구히 막히지 않게 한다.
                    await purgeSync.resumePushAfterPurge()
                } catch {
                    setPendingIfResumeOwnsState(acknowledged: acknowledged)
                }
                return
            }

            guard let memberID = authProvider.currentUserID else { return }
            state = .deleting
            await performPurge(
                memberID: memberID,
                possiblyDeleted: true,
                pendingAcknowledged: acknowledged
            )
        }
    }
}

private extension DataPurgeCoordinator {
    var pendingAcknowledged: Bool {
        guard case let .completionPending(acknowledged) = state else { return false }
        return acknowledged
    }

    func setPendingIfResumeOwnsState(acknowledged: Bool) {
        switch state {
        case .idle, .completionPending:
            state = .completionPending(acknowledged: acknowledged)
        case .offline, .awaitingConfirmation, .deleting, .completed, .failed:
            break
        }
    }

    func clearPendingIfResumeOwnsState() {
        if case .completionPending = state {
            state = .idle
        }
    }

    func performPurge(
        memberID: UUID,
        possiblyDeleted initiallyPossiblyDeleted: Bool,
        pendingAcknowledged: Bool
    ) async {
        await purgeSync.suspendPushForPurge()
        do {
            try await purgeStore.markPurgePending(memberID: memberID.uuidString)
        } catch {
            if initiallyPossiblyDeleted {
                state = .completionPending(acknowledged: pendingAcknowledged)
            } else {
                await purgeSync.resumePushAfterPurge()
                state = .failed
            }
            return
        }

        var possiblyDeleted = initiallyPossiblyDeleted
        var retries = 0
        while true {
            guard authProvider.currentUserID == memberID,
                  let accessToken = authProvider.currentAccessToken()
            else {
                await finishFailure(
                    possiblyDeleted: possiblyDeleted,
                    pendingAcknowledged: pendingAcknowledged
                )
                return
            }

            do {
                try await ledgerService.deleteAll(accessToken: accessToken)
                break
            } catch {
                let kind = failureKind(error)
                if kind == .ambiguous {
                    possiblyDeleted = true
                }
                if kind == .terminalConfirmed || retries >= maxAmbiguousRetries {
                    await finishFailure(
                        possiblyDeleted: possiblyDeleted,
                        pendingAcknowledged: pendingAcknowledged
                    )
                    return
                }
                retries += 1
                await retrySleep(.seconds(Int64(1 << min(retries - 1, 3))))
            }
        }

        retries = 0
        while true {
            do {
                try await purgeStore.clearForPurge()
                break
            } catch {
                guard retries < maxAmbiguousRetries else {
                    state = .completionPending(acknowledged: pendingAcknowledged)
                    return
                }
                retries += 1
                await retrySleep(.seconds(Int64(1 << min(retries - 1, 3))))
            }
        }

        onDataCleared()
        await purgeSync.resumePushAfterPurge()
        state = .completed
    }

    func finishFailure(possiblyDeleted: Bool, pendingAcknowledged: Bool) async {
        guard !possiblyDeleted else {
            state = .completionPending(acknowledged: pendingAcknowledged)
            return
        }
        do {
            try await purgeStore.clearPurgeMarker()
        } catch {
            state = .completionPending(acknowledged: pendingAcknowledged)
            return
        }
        await purgeSync.resumePushAfterPurge()
        state = .failed
    }

    private func failureKind(_ error: Error) -> FailureKind {
        switch error {
        case let APIError.server(code, _):
            switch code {
            case "TOO_MANY_REQUESTS":
                return .retryableConfirmed
            case "UNAUTHORIZED", "FORBIDDEN":
                return .terminalConfirmed
            default:
                return .ambiguous
            }
        case let APIError.httpStatus(code, _):
            return (400 ..< 500).contains(code) ? .terminalConfirmed : .ambiguous
        case let APIError.transport(underlying):
            guard let code = (underlying as? URLError)?.code else { return .ambiguous }
            switch code {
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .secureConnectionFailed:
                return .retryableConfirmed
            default:
                return .ambiguous
            }
        default:
            return .ambiguous
        }
    }
}
