//
//  LoginViewModel.swift
//  woni_app
//

import Foundation
import Observation
import OSLog

protocol LoginSyncing {
    func beginAccountSwitch() async throws
    func finishAccountSwitch(expectedMemberID: UUID) async -> Bool
    func resumeAccountSwitch(expectedMemberID: UUID?) -> Bool
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
        case offline
        case restoreFailed
    }

    nonisolated static let logger = Logger(subsystem: "woni_app", category: "Login")

    private let authProvider: any AuthProviding
    private let sync: any LoginSyncing
    private let coordinator: SessionTransitionCoordinator
    private let connectivity: any ConnectivityObserving
    private var restoreTargetUserID: UUID?

    private(set) var flowState: FlowState = .idle

    init(
        authProvider: any AuthProviding,
        sync: any LoginSyncing,
        coordinator: SessionTransitionCoordinator,
        connectivity: any ConnectivityObserving
    ) {
        self.authProvider = authProvider
        self.sync = sync
        self.coordinator = coordinator
        self.connectivity = connectivity
    }

    var identityState: LoginIdentityState {
        authProvider.currentUserID != nil && !authProvider.isAnonymous ? .signedIn : .anonymous
    }

    var isWorking: Bool {
        switch flowState {
        case .linking, .signingIn, .restoring:
            true
        case .idle, .awaitingSignInConfirmation, .completed, .failed, .offline, .restoreFailed:
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

    var hasOfflineFailure: Bool {
        flowState == .offline
    }

    func linkIdentity(_ provider: OAuthProvider) async {
        guard !isWorking else {
            return
        }
        guard connectivity.isOnline else {
            flowState = .offline
            return
        }

        await coordinator.runAccountSwitchTransition { [self] in
            await performLinkIdentity(provider)
        }
    }

    func confirmSignIn() async {
        guard let provider = conflictProvider else {
            return
        }
        guard connectivity.isOnline else {
            flowState = .offline
            return
        }

        await coordinator.runAccountSwitchTransition { [self] in
            flowState = .signingIn(provider)
            do {
                try await sync.beginAccountSwitch()
            } catch {
                _ = sync.resumeAccountSwitch(expectedMemberID: nil)
                flowState = .failed
                return
            }

            do {
                try await authProvider.signIn(provider)
            } catch {
                _ = sync.resumeAccountSwitch(expectedMemberID: nil)
                flowState = Self.isNetworkConnectivityError(error) ? .offline : .failed
                return
            }

            guard let targetUserID = authProvider.currentUserID else {
                _ = sync.resumeAccountSwitch(expectedMemberID: nil)
                flowState = .failed
                return
            }
            restoreTargetUserID = targetUserID
            await revokeOtherSessionsBestEffort()
            guard authProvider.currentUserID == targetUserID else {
                restoreTargetUserID = nil
                _ = sync.resumeAccountSwitch(expectedMemberID: targetUserID)
                flowState = .failed
                return
            }

            flowState = .restoring
            do {
                try await sync.restoreAll()
                restoreTargetUserID = nil
                if await sync.finishAccountSwitch(expectedMemberID: targetUserID) {
                    flowState = .completed
                } else {
                    _ = sync.resumeAccountSwitch(expectedMemberID: targetUserID)
                    flowState = .failed
                }
            } catch {
                flowState = .restoreFailed
            }
        }
    }

    func retryRestore() async {
        guard hasRestoreFailure else {
            return
        }

        await coordinator.runAccountSwitchTransition { [self] in
            guard let targetUserID = restoreTargetUserID,
                  authProvider.currentUserID == targetUserID
            else {
                let targetUserID = restoreTargetUserID
                self.restoreTargetUserID = nil
                _ = sync.resumeAccountSwitch(expectedMemberID: targetUserID)
                flowState = .failed
                return
            }
            flowState = .restoring
            do {
                try await sync.restoreAll()
                self.restoreTargetUserID = nil
                if await sync.finishAccountSwitch(expectedMemberID: targetUserID) {
                    flowState = .completed
                } else {
                    _ = sync.resumeAccountSwitch(expectedMemberID: targetUserID)
                    flowState = .failed
                }
            } catch {
                flowState = .restoreFailed
            }
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

    func dismissOfflineFailure() {
        guard hasOfflineFailure else {
            return
        }
        flowState = .idle
    }

    func finishAfterRestoreFailure() async {
        guard hasRestoreFailure else {
            return
        }
        await coordinator.runAccountSwitchTransition { [self] in
            guard hasRestoreFailure else {
                return
            }
            let targetUserID = restoreTargetUserID
            restoreTargetUserID = nil
            flowState = sync.resumeAccountSwitch(expectedMemberID: targetUserID)
                ? .completed
                : .failed
        }
    }
}

private extension LoginViewModel {
    func performLinkIdentity(_ provider: OAuthProvider) async {
        flowState = .linking(provider)
        do {
            try await authProvider.linkIdentity(provider)
            guard let targetUserID = authProvider.currentUserID else {
                flowState = .failed
                return
            }
            await revokeOtherSessionsBestEffort()
            guard authProvider.currentUserID == targetUserID else {
                flowState = .failed
                return
            }
            await sync.pushPending()
            flowState = .completed
        } catch AuthServiceError.identityAlreadyExists {
            flowState = .awaitingSignInConfirmation(provider)
        } catch {
            flowState = Self.isNetworkConnectivityError(error) ? .offline : .failed
        }
    }

    func revokeOtherSessionsBestEffort() async {
        do {
            try await authProvider.revokeOtherSessions()
        } catch {
            Self.logger.error(
                "Failed to revoke other sessions after authentication: \(String(describing: error), privacy: .private)"
            )
        }
    }

    /// 연결성 부재로 해석 가능한 URLError 코드만 오프라인 안내에 매핑한다.
    /// NSURLErrorDomain 전체를 오프라인으로 보면 사용자 취소(.cancelled)나 서버 응답
    /// 파싱 실패(.badServerResponse) 등 비연결성 오류까지 "네트워크 확인" 안내로 오분류된다.
    nonisolated static let connectivityURLErrorCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
        .internationalRoamingOff,
        .callIsActive,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .timedOut
    ]

    static func isNetworkConnectivityError(_ error: Error) -> Bool {
        var errorCursor: NSError? = error as NSError
        var visitedErrors = Set<ObjectIdentifier>()

        while let currentError = errorCursor {
            guard visitedErrors.insert(ObjectIdentifier(currentError)).inserted else {
                return false
            }
            let urlErrorCode = (currentError as? URLError)?.code
            if let urlErrorCode, connectivityURLErrorCodes.contains(urlErrorCode) {
                return true
            }
            errorCursor = currentError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
