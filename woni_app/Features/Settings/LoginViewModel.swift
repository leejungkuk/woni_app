//
//  LoginViewModel.swift
//  woni_app
//

import AuthenticationServices
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
    private(set) var identity: IdentitySnapshot

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
        // 초기값을 스트림 첫 이벤트에 기대면 생성~첫 이벤트 사이에 이미 로그인한 사용자에게
        // "비회원"이 노출되고, 그 구간 길이는 기기 스케줄링에 좌우된다.
        identity = IdentitySnapshot(from: authProvider)
    }

    var identityState: LoginIdentityState {
        identity.userID != nil && !identity.isAnonymous ? .signedIn : .anonymous
    }

    var signedInEmail: String? {
        identity.email
    }

    /// 신원 변경 구독을 시작한다. 뷰는 `.task`에서, 뷰가 없는 테스트는 직접 호출한다.
    /// `init`에서 시작하지 않는 이유: `settingsDestination()`이 재평가마다 새 인스턴스를 만들어
    /// 버려지는 인스턴스가 구독을 갖게 된다. 구독 직후 현재 값을 한 번 더 읽어, 생성~구독
    /// 사이에 일어난 변화를 메운다.
    func observeIdentity() async {
        let changes = authProvider.identityDidChange
        refreshIdentity()
        for await _ in changes {
            refreshIdentity()
        }
    }

    var isWorking: Bool {
        switch flowState {
        case .signingIn, .restoring:
            true
        case .idle, .completed, .failed, .offline, .restoreFailed:
            false
        }
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

    func signIn(_ provider: OAuthProvider) async {
        guard !isWorking else {
            return
        }
        guard connectivity.isOnline else {
            flowState = .offline
            return
        }

        await coordinator.runAccountSwitchTransition { [self] in
            await performSignIn(provider)
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
    /// 인증 성공 직후 동기로 신원을 맞춘다. 스트림에 기대면 `flowState`가 `.completed`가 되어
    /// 시트가 닫히는 시점보다 갱신이 늦을 수 있고(별도 Task로 브리지된다) 그 창은 기기 성능에
    /// 좌우된다 — 사용자가 겪은 "시트는 닫혔는데 설정 화면이 그대로"가 정확히 그 증상이다.
    func refreshIdentity() {
        identity = IdentitySnapshot(from: authProvider)
    }

    func performSignIn(_ provider: OAuthProvider) async {
        guard connectivity.isOnline else {
            flowState = .offline
            return
        }

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
            refreshIdentity()
        } catch {
            // 취소도 `beginAccountSwitch` 이후의 중단 경로다. resume을 건너뛰면 push suspend가
            // 남아 동기화가 조용히 멈춘다 — 알럿 유무와 무관하게 항상 먼저 해제한다.
            _ = sync.resumeAccountSwitch(expectedMemberID: nil)
            if Self.isUserCancellation(error) {
                flowState = .idle
            } else {
                flowState = Self.isNetworkConnectivityError(error) ? .offline : .failed
            }
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

extension LoginViewModel {
    /// 취소 오류 타입이 provider마다 다르다 — Google 웹 인증은 `ASWebAuthenticationSessionError`,
    /// Apple은 `ASAuthorizationError`. 한쪽만 잡으면 provider별로 알럿 유무가 갈린다.
    static func isUserCancellation(_ error: Error) -> Bool {
        if let error = error as? ASWebAuthenticationSessionError {
            return error.code == .canceledLogin
        }
        if let error = error as? ASAuthorizationError {
            return error.code == .canceled
        }
        return false
    }
}
