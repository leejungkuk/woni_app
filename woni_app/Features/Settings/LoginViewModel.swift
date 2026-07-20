//
//  LoginViewModel.swift
//  woni_app
//

import Foundation
import Observation

protocol LoginSyncing {
    func preserveLocalDataForAccountSwitch() async throws -> UUID
    func rollbackLocalDataPreservation(batchID: UUID) async throws
    func finishAccountSwitch()
    func pushPending() async
    func restoreAll() async throws
}

extension SyncEngine: LoginSyncing {}

enum LoginIdentityState: Equatable {
    case anonymous
    case signedIn
}

@Observable
final class LoginViewModel {
    enum FlowState: Equatable {
        case idle
        case linking(OAuthProvider)
        case awaitingSignInConfirmation(OAuthProvider)
        case signingIn(OAuthProvider)
        case restoring
        case completed
        case failed
        case restoreFailed
    }

    private let authProvider: any AuthProviding
    private let sync: any LoginSyncing
    private var pendingRollbackBatchID: UUID?

    private(set) var flowState: FlowState = .idle
    private(set) var identityState: LoginIdentityState

    init(authProvider: any AuthProviding, sync: any LoginSyncing) {
        self.authProvider = authProvider
        self.sync = sync
        identityState = authProvider.currentUserID != nil && !authProvider.isAnonymous
            ? .signedIn
            : .anonymous
    }

    var isWorking: Bool {
        switch flowState {
        case .linking, .signingIn, .restoring:
            true
        case .idle, .awaitingSignInConfirmation, .completed, .failed, .restoreFailed:
            false
        }
    }

    var conflictProvider: OAuthProvider? {
        guard case let .awaitingSignInConfirmation(provider) = flowState else {
            return nil
        }
        return provider
    }

    var hasFailure: Bool {
        flowState == .failed
    }

    var hasRestoreFailure: Bool {
        flowState == .restoreFailed
    }

    func linkIdentity(_ provider: OAuthProvider) async {
        guard !isWorking else {
            return
        }
        if let pendingRollbackBatchID {
            do {
                try await sync.rollbackLocalDataPreservation(batchID: pendingRollbackBatchID)
                self.pendingRollbackBatchID = nil
            } catch {
                flowState = .failed
                return
            }
        }

        flowState = .linking(provider)
        do {
            try await authProvider.linkIdentity(provider)
            identityState = .signedIn
            await sync.pushPending()
            flowState = .completed
        } catch AuthServiceError.identityAlreadyExists {
            flowState = .awaitingSignInConfirmation(provider)
        } catch {
            flowState = .failed
        }
    }

    func confirmSignIn() async {
        guard let provider = conflictProvider else {
            return
        }

        flowState = .signingIn(provider)
        let preservationBatchID: UUID
        do {
            preservationBatchID = try await sync.preserveLocalDataForAccountSwitch()
        } catch {
            flowState = .failed
            return
        }

        do {
            try await authProvider.signIn(provider)
        } catch {
            do {
                try await sync.rollbackLocalDataPreservation(batchID: preservationBatchID)
            } catch {
                pendingRollbackBatchID = preservationBatchID
            }
            flowState = .failed
            return
        }

        identityState = .signedIn
        flowState = .restoring
        do {
            try await sync.restoreAll()
            sync.finishAccountSwitch()
            flowState = .completed
        } catch {
            sync.finishAccountSwitch()
            flowState = .restoreFailed
        }
    }

    func retryRestore() async {
        guard hasRestoreFailure else {
            return
        }

        flowState = .restoring
        do {
            try await sync.restoreAll()
            flowState = .completed
        } catch {
            flowState = .restoreFailed
        }
    }

    func cancelSignIn() {
        guard conflictProvider != nil else {
            return
        }
        flowState = .idle
    }

    func dismissFailure() {
        guard hasFailure else {
            return
        }
        flowState = .idle
    }

    func finishAfterRestoreFailure() {
        guard hasRestoreFailure else {
            return
        }
        flowState = .completed
    }
}
