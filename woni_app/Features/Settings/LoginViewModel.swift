//
//  LoginViewModel.swift
//  woni_app
//

import AuthenticationServices
import Foundation
import Observation
import OSLog

extension SyncEngine: LoginSyncing {}

enum LoginIdentityState: Equatable {
    case anonymous
    case signedIn
}

/// 로그인 직전 익명 계정을 삭제 대상으로 지목하기 위한 값. 토큰은 메모리에만 두고
/// 로그·영속 저장에 남기지 않는다.
private struct AnonymousAccountSnapshot {
    let identity: IdentitySnapshot
    let accessToken: String
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
    private let anonymousAccountDeleter: any AnonymousAccountDeleting
    private let onSignInCompleted: @MainActor () async -> Void
    private var restoreTargetUserID: UUID?
    /// restore 실패 후 재시도 창에서만 살아 있는 스냅샷. `restoreTargetUserID`와 수명을 정확히
    /// 맞춘다 — 창이 닫힌 뒤에도 남아 있으면 다음 로그인이 남의 익명 계정을 지운다.
    private var restoreAnonymousAccount: AnonymousAccountSnapshot?

    private(set) var flowState: FlowState = .idle
    private(set) var identity: IdentitySnapshot

    init(
        authProvider: any AuthProviding,
        sync: any LoginSyncing,
        coordinator: SessionTransitionCoordinator,
        connectivity: any ConnectivityObserving,
        anonymousAccountDeleter: any AnonymousAccountDeleting,
        onSignInCompleted: @escaping @MainActor () async -> Void = {}
    ) {
        self.authProvider = authProvider
        self.sync = sync
        self.coordinator = coordinator
        self.connectivity = connectivity
        self.anonymousAccountDeleter = anonymousAccountDeleter
        self.onSignInCompleted = onSignInCompleted
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
                restoreAnonymousAccount = nil
                _ = sync.resumeAccountSwitch(expectedMemberID: targetUserID)
                flowState = .failed
                return
            }
            flowState = .restoring
            do {
                try await sync.restoreAll()
                self.restoreTargetUserID = nil
                if await sync.finishAccountSwitch(expectedMemberID: targetUserID) {
                    // 재시도로 성공한 것도 완전 이관이다. 여기서 `.completed`를 직접 세우면
                    // 익명 정리가 통째로 건너뛰어지고, 스냅샷은 창이 닫히며 사라져 영영 못 지운다.
                    let anonymousAccount = restoreAnonymousAccount
                    restoreAnonymousAccount = nil
                    await completeSignIn(anonymousAccount)
                } else {
                    restoreAnonymousAccount = nil
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
            // 여기는 `finishAccountSwitch`가 아니라 `resume`으로 끝난다 — 게이트 A①이 성립하지
            // 않으므로 익명 정리를 하지 않는 것이 맞다. 스냅샷만 버린다.
            restoreAnonymousAccount = nil
            if sync.resumeAccountSwitch(expectedMemberID: targetUserID) {
                await onSignInCompleted()
                flowState = .completed
            } else {
                flowState = .failed
            }
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
        let anonymousAccount = await captureAnonymousAccount()
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
        do {
            // 익명 시절 이미 synced가 된 행은 push 대상이 아니라 새 계정으로 넘어가지 못한다.
            // restoreAll보다 먼저 되돌려야 한다 — 뒤로 가면 restore로 받은 서버 행까지 미푸시가 되어
            // 서버에 이미 있는 행을 다시 import한다.
            try await sync.resetSyncStateForAccountSwitch()
        } catch {
            restoreTargetUserID = nil
            _ = sync.resumeAccountSwitch(expectedMemberID: targetUserID)
            flowState = .failed
            return
        }
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
                await completeSignIn(anonymousAccount)
            } else {
                _ = sync.resumeAccountSwitch(expectedMemberID: targetUserID)
                flowState = .failed
            }
        } catch {
            // 재시도 창을 여는 유일한 경로다. 스냅샷을 여기 남겨야 `retryRestore`가 정리할 수 있다.
            // 창이 토큰 수명(~1시간)보다 길어지면 삭제가 401로 끝난다. 이 시점 세션은 이미 회원이라
            // 익명 토큰을 갱신할 수단이 없다 — 남는 결과가 고아 익명 계정이라 BACKLOG B16이 맡는다.
            restoreAnonymousAccount = anonymousAccount
            flowState = .restoreFailed
        }
    }

    /// 신원 갱신을 마친 뒤에만 완료로 전이한다(§5.1 L→M0→M). 신원 갱신을 스트림 이벤트에
    /// 기대면 시트 dismiss가 먼저 실행돼 설정 화면이 비회원인 채로 남을 수 있다(#6) —
    /// 저사양 기기일수록 그 창이 넓다. 여기서 순서 자체를 없앤다.
    ///
    /// 익명 정리는 완료 **뒤**에 둔다. 결과를 버리는 best-effort인데 앞에 두면 그 네트워크
    /// 왕복 동안 로그인 시트가 스피너를 문 채 닫히지 않는다(`interactiveDismissDisabled`).
    /// 정리가 늦어져 잔량 판정이 뒤집힐 여지는 없다 — 새 미푸시 행은 사용자가 쓸 때만 생기고,
    /// 그때는 삭제를 건너뛰는 쪽이 안전한 방향이다.
    func completeSignIn(_ anonymousAccount: AnonymousAccountSnapshot?) async {
        await onSignInCompleted()
        refreshIdentity()
        flowState = .completed
        await deleteAnonymousAccountIfFullyMigrated(anonymousAccount)
    }

    /// 익명 계정 삭제에 쓸 신원과 토큰을 계정 전환 시작 **전에** 고정한다. 토큰을 캡처 직전에
    /// 갱신하는 이유는 잔여 수명이 기기·세션 이력마다 달라 삭제 성패가 기기별로 갈리기 때문이다.
    /// 이 시점 세션은 아직 익명이라 회원 토큰이 섞일 위험이 없다. 토큰은 메모리에만 둔다.
    func captureAnonymousAccount() async -> AnonymousAccountSnapshot? {
        // 새 캡처가 곧 새 에피소드의 시작이다. 여기서 끊어야 이전 시도가 남긴 스냅샷이 토큰을 쥔
        // 채 살아남지 않는다 — `performSignIn`의 조기 return이 여러 갈래라 출구마다 지우면
        // 하나씩 새기 쉽다.
        restoreAnonymousAccount = nil
        do {
            guard let accessToken = try await authProvider.refreshedAccessToken() else {
                return nil
            }
            return AnonymousAccountSnapshot(
                identity: IdentitySnapshot(from: authProvider),
                accessToken: accessToken
            )
        } catch {
            Self.logger.error(
                """
                Failed to refresh the anonymous access token before sign-in: \
                \(String(describing: error), privacy: .private)
                """
            )
            return nil
        }
    }

    /// 로그인 뒤 익명 계정을 best-effort로 정리한다. `DELETE /api/v1/members/me`는 cascade로
    /// 그 신원의 거래 전량을 함께 지우므로 네 조건을 모두 만족할 때만 실행한다:
    /// `finishAccountSwitch` 성공(호출 지점) · 미푸시 잔량 0 · 스냅샷이 익명 · 신원이 실제로 바뀜.
    /// 하나라도 어긋나면 익명 계정과 그 데이터를 보존한다 — 현재와 같은 수준이지 악화가 아니다.
    func deleteAnonymousAccountIfFullyMigrated(_ account: AnonymousAccountSnapshot?) async {
        guard let account,
              account.identity.isAnonymous,
              account.identity.userID != authProvider.currentUserID
        else {
            Self.logger.notice("Skipped anonymous account cleanup: no replaced anonymous identity.")
            return
        }
        do {
            guard try await !sync.hasPendingPush() else {
                Self.logger.notice("Skipped anonymous account cleanup: local entries are not fully pushed.")
                return
            }
            try await anonymousAccountDeleter.deleteAccount(accessToken: account.accessToken)
        } catch {
            // 조용히 포기한다. 사용자에게 알리지 않고 재시도 큐도 만들지 않는다.
            Self.logger.error(
                """
                Failed to delete the anonymous account after sign-in: \
                \(String(describing: error), privacy: .private)
                """
            )
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
