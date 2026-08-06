//
//  WithdrawalCoordinator.swift
//  woni_app
//

import Foundation
import Observation

/// 탈퇴·데이터 삭제의 순서와 상태를 소유한다. 전이 직렬화·push 정지·로컬 정리는
/// `SessionTransitionCoordinator`에 위임한다(참조는 단방향이라 순환이 없다).
/// `@Observable`이 없으면 `SettingsViewModel`의 계산 프로퍼티를 통한 상태 변화가
/// SwiftUI를 invalidate하지 못해 알럿이 조용히 뜨지 않는다.
@MainActor
@Observable
final class WithdrawalCoordinator {
    enum WithdrawalState: Equatable {
        case idle
        case awaitingConfirmation(isAppleLinked: Bool)
        case deleting
        case completed(appleUnlinkPending: Bool)
        case failed
        case offline
    }

    private let session: SessionTransitionCoordinator
    private let authProvider: any AuthProviding
    private let connectivity: any ConnectivityObserving
    private let withdrawalService: any WithdrawalRequesting

    private(set) var state: WithdrawalState = .idle

    init(
        session: SessionTransitionCoordinator,
        authProvider: any AuthProviding,
        connectivity: any ConnectivityObserving,
        withdrawalService: any WithdrawalRequesting
    ) {
        self.session = session
        self.authProvider = authProvider
        self.connectivity = connectivity
        self.withdrawalService = withdrawalService
    }

    /// 확인 이후 종단 상태를 처리할 때까지 로그인·로그아웃 진입을 함께 막는다. 전이는 차단이
    /// 아니라 큐잉이라, 막지 않으면 삭제 완료 직후 새 익명 신원에 로그인이 시작된다.
    var isBlockingOtherEntry: Bool {
        switch state {
        case .idle, .offline, .awaitingConfirmation:
            return false
        case .deleting, .completed, .failed:
            return true
        }
    }

    func prepareWithdrawal() {
        guard connectivity.isOnline else {
            state = .offline
            return
        }
        state = .awaitingConfirmation(isAppleLinked: authProvider.hasAppleIdentity)
    }

    func confirmWithdrawal() async {
        await session.runWithdrawal { [self] in
            state = .deleting
            await session.suspendPushBeforeWithdrawal()

            var authorizationCode: String?
            if authProvider.hasAppleIdentity {
                // 코드를 못 얻어도 삭제는 멈추지 않는다. Apple 연동 해제만 사용자 몫으로 남는다.
                authorizationCode = try? await authProvider.requestAppleAuthorizationCode()
            }
            let appleUnlinkPending = authProvider.hasAppleIdentity && authorizationCode == nil

            do {
                try await withdrawRetryingAmbiguousFailure(authorizationCode: authorizationCode)
            } catch {
                await session.resumePushAfterFailedWithdrawal()
                state = .failed
                return
            }

            // 정리 실패는 기존 재시도 알럿이 맡는다. 완료·실패를 함께 세우면 알럿이 경쟁한다.
            let didCleanUp = await session.performWithdrawalCleanup()
            state = didCleanUp ? .completed(appleUnlinkPending: appleUnlinkPending) : .idle
        }
    }

    func cancelWithdrawal() {
        state = .idle
    }

    func acknowledgeCompletion() {
        state = .idle
    }

    func dismissFailure() {
        state = .idle
    }

    func dismissOffline() {
        state = .idle
    }

    /// 요청이 서버에 닿아 삭제가 끝났는데 응답만 잃었을 수 있는 경우에만 1회 재호출한다.
    /// 1회용 코드는 첫 요청에서 소진됐으므로 재호출에는 싣지 않는다(서버 삭제는 멱등).
    private func withdrawRetryingAmbiguousFailure(authorizationCode: String?) async throws {
        do {
            try await withdrawalService.withdraw(appleAuthorizationCode: authorizationCode)
        } catch {
            guard isAmbiguousFailure(error) else {
                throw error
            }
            try await withdrawalService.withdraw(appleAuthorizationCode: nil)
        }
    }

    /// `.cancelled`(사용자·시스템 중단)와 그 밖의 transport(DNS·TLS·연결 거부)는 서버에 닿지
    /// 못했고, `httpStatus`·`server`는 서버가 이미 판단을 끝냈으므로 모두 재호출 대상이 아니다.
    private func isAmbiguousFailure(_ error: Error) -> Bool {
        guard case let APIError.transport(underlying) = error,
              let code = (underlying as? URLError)?.code
        else {
            return false
        }
        return code == .timedOut || code == .networkConnectionLost
    }
}
