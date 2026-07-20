//
//  AuthService.swift
//  woni_app
//

import Auth
import Foundation

protocol AuthProviding {
    func ensureIdentity() async throws
    func currentAccessToken() -> String?
    func refreshedAccessToken() async throws -> String?
    func signOut() async throws

    var currentUserID: UUID? { get }
    var isAnonymous: Bool { get }
}

/// `AuthClient` 래핑. 프로젝트 기본 격리(`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`)로
/// MainActor 격리되며, in-flight task로 동시 `ensureIdentity` 호출을 유착해
/// 익명 sign-in이 신원당 1회만 발생하도록 보장한다(D3′ 지연·1회 발급).
final class SupabaseAuthService: AuthProviding {
    private let authClient: AuthClient
    private var ensureIdentityTask: Task<Void, Error>?

    init(authClient: AuthClient) {
        self.authClient = authClient
    }

    init(bundle: Bundle = .main) throws {
        authClient = try SupabaseClientProvider.makeAuthClient(bundle: bundle)
    }

    func ensureIdentity() async throws {
        if let task = ensureIdentityTask {
            try await task.value
            return
        }
        guard authClient.currentSession == nil else {
            return
        }

        let task = Task { [authClient] in
            _ = try await authClient.signInAnonymously()
        }
        ensureIdentityTask = task
        defer { ensureIdentityTask = nil }
        try await task.value
    }

    func currentAccessToken() -> String? {
        authClient.currentSession?.accessToken
    }

    func refreshedAccessToken() async throws -> String? {
        guard authClient.currentSession != nil else {
            return nil
        }

        return try await authClient.refreshSession().accessToken
    }

    func signOut() async throws {
        // 진행 중인 ensure를 먼저 정착시켜, 로그아웃 직후 늦게 완료된 익명 sign-in이
        // 세션을 되살리는 경합을 막는다(sign-in 실패는 무시 — 세션이 없어 sign-out은 무해).
        // 임의의 교차 호출 순서(로그아웃과 새 ensure 요청의 논리적 선후) 보장은 이 계층이
        // 아니라 코디네이션 계층(step5 FIFO sync 엔진·step8 로그아웃 흐름)이 담당한다.
        if let task = ensureIdentityTask {
            _ = try? await task.value
        }
        try await authClient.signOut()
    }

    var currentUserID: UUID? {
        authClient.currentSession?.user.id
    }

    var isAnonymous: Bool {
        authClient.currentSession?.user.isAnonymous ?? false
    }
}

/// 테스트 지원용 인메모리 신원 서비스. 실제 익명 sign-in의 async 틈과 동시성 유착을
/// 모사해, 동시 `ensureIdentity`에도 sign-in이 1회만 일어나는 계약을 검증할 수 있다.
final class FakeAuthService: AuthProviding {
    private struct SessionState {
        let userID: UUID
        var value: String
        let isAnonymous: Bool
    }

    private let makeUserID: () -> UUID
    private let initialValue: String
    private let refreshedValue: String
    private var session: SessionState?
    private var ensureIdentityTask: Task<Void, Never>?

    private(set) var anonymousSignInCount = 0
    private(set) var refreshCount = 0

    init(
        makeUserID: @escaping () -> UUID = { UUID() },
        initialValue: String = "PLACEHOLDER_VALUE",
        refreshedValue: String = "PLACEHOLDER_REFRESHED_VALUE"
    ) {
        self.makeUserID = makeUserID
        self.initialValue = initialValue
        self.refreshedValue = refreshedValue
    }

    func ensureIdentity() async throws {
        if let task = ensureIdentityTask {
            await task.value
            return
        }
        guard session == nil else {
            return
        }

        let task = Task {
            await Task.yield()
            anonymousSignInCount += 1
            session = SessionState(
                userID: makeUserID(),
                value: initialValue,
                isAnonymous: true
            )
        }
        ensureIdentityTask = task
        defer { ensureIdentityTask = nil }
        await task.value
    }

    func currentAccessToken() -> String? {
        session?.value
    }

    func refreshedAccessToken() async throws -> String? {
        guard session != nil else {
            return nil
        }

        refreshCount += 1
        session?.value = refreshedValue
        return session?.value
    }

    func signOut() async throws {
        // SupabaseAuthService.signOut과 동일한 경합 경계를 모사한다.
        if let task = ensureIdentityTask {
            await task.value
        }
        session = nil
    }

    var currentUserID: UUID? {
        session?.userID
    }

    var isAnonymous: Bool {
        session?.isAnonymous ?? false
    }
}
