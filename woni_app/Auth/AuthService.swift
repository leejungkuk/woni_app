//
//  AuthService.swift
//  woni_app
//

import Auth
import Foundation

enum OAuthProvider: Equatable {
    case google
    case apple
}

enum AuthServiceError: Error, Equatable {
    case identityAlreadyExists
    case missingAnonymousIdentity
    case identityChangedDuringLink
}

protocol AuthProviding {
    func ensureIdentity() async throws
    func currentAccessToken() -> String?
    func refreshedAccessToken() async throws -> String?
    func linkIdentity(_ provider: OAuthProvider) async throws
    func signIn(_ provider: OAuthProvider) async throws
    func signOut() async throws

    var currentUserID: UUID? { get }
    var isAnonymous: Bool { get }
}

/// `AuthClient` 래핑. 프로젝트 기본 격리(`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`)로
/// MainActor 격리되며, in-flight task로 동시 `ensureIdentity` 호출을 유착해
/// 익명 sign-in이 신원당 1회만 발생하도록 보장한다(D3′ 지연·1회 발급).
final class SupabaseAuthService: AuthProviding {
    private let authClient: AuthClient
    private let oauthRedirectURL: URL
    private let appleIDTokenProvider: any AppleIDTokenProviding
    private let webOAuthSession: any WebOAuthAuthenticating
    private var ensureIdentityTask: Task<Void, Error>?
    private var cachedAppleCredential: AppleIDTokenCredential?

    init(
        authClient: AuthClient,
        oauthRedirectURL: URL,
        appleIDTokenProvider: any AppleIDTokenProviding = AppleIDTokenProvider(),
        webOAuthSession: any WebOAuthAuthenticating = WebOAuthSession()
    ) {
        self.authClient = authClient
        self.oauthRedirectURL = oauthRedirectURL
        self.appleIDTokenProvider = appleIDTokenProvider
        self.webOAuthSession = webOAuthSession
    }

    init(bundle: Bundle = .main) throws {
        authClient = try SupabaseClientProvider.makeAuthClient(bundle: bundle)
        oauthRedirectURL = try SupabaseClientProvider.oauthRedirectURL()
        appleIDTokenProvider = AppleIDTokenProvider()
        webOAuthSession = WebOAuthSession()
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

    func linkIdentity(_ provider: OAuthProvider) async throws {
        try await ensureIdentity()
        guard let anonymousUserID = currentUserID, isAnonymous else {
            throw AuthServiceError.missingAnonymousIdentity
        }

        do {
            switch provider {
            case .google:
                let response = try await authClient.getLinkIdentityURL(
                    provider: .google,
                    redirectTo: oauthRedirectURL
                )
                let callbackURL = try await webOAuthSession.authenticate(
                    url: response.url,
                    callbackScheme: oauthRedirectURL.scheme
                )
                _ = try await authClient.session(from: callbackURL)
            case .apple:
                let credential = try await appleIDTokenProvider.requestCredential()
                cachedAppleCredential = credential
                _ = try await authClient.linkIdentityWithIdToken(
                    credentials: credential.openIDConnectCredentials
                )
                cachedAppleCredential = nil
            }
        } catch {
            let mappedError = Self.mapIdentityLinkError(error)
            if mappedError as? AuthServiceError != .identityAlreadyExists {
                cachedAppleCredential = nil
            }
            throw mappedError
        }

        guard currentUserID == anonymousUserID, !isAnonymous else {
            throw AuthServiceError.identityChangedDuringLink
        }
    }

    func signIn(_ provider: OAuthProvider) async throws {
        switch provider {
        case .google:
            _ = try await authClient.signInWithOAuth(
                provider: .google,
                redirectTo: oauthRedirectURL
            )
        case .apple:
            let credential: AppleIDTokenCredential
            if let cachedAppleCredential {
                credential = cachedAppleCredential
            } else {
                credential = try await appleIDTokenProvider.requestCredential()
            }
            _ = try await authClient.signInWithIdToken(
                credentials: credential.openIDConnectCredentials
            )
            cachedAppleCredential = nil
        }
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

private extension SupabaseAuthService {
    static func mapIdentityLinkError(_ error: Error) -> Error {
        guard let authError = error as? AuthError else {
            return error
        }
        if authError.errorCode == .identityAlreadyExists {
            return AuthServiceError.identityAlreadyExists
        }
        // Apple 직접 API는 errorCode로, Google 콜백은 PKCE 교환 오류의 associated code로 충돌을 전달한다.
        guard case let .pkceGrantCodeExchange(_, _, code) = authError else {
            return error
        }
        return code == ErrorCode.identityAlreadyExists.rawValue
            ? AuthServiceError.identityAlreadyExists
            : error
    }
}

/// 테스트 지원용 인메모리 신원 서비스. 실제 익명 sign-in의 async 틈과 동시성 유착을
/// 모사해, 동시 `ensureIdentity`에도 sign-in이 1회만 일어나는 계약을 검증할 수 있다.
final class FakeAuthService: AuthProviding {
    private struct SessionState {
        let userID: UUID
        var value: String
        var isAnonymous: Bool
    }

    private let makeUserID: () -> UUID
    private let makeSignedInUserID: () -> UUID
    private let initialValue: String
    private let refreshedValue: String
    private var linkIdentityError: Error?
    private var signInFailuresRemaining: Int
    private var session: SessionState?
    private var ensureIdentityTask: Task<Void, Never>?

    private(set) var anonymousSignInCount = 0
    private(set) var refreshCount = 0
    private(set) var linkIdentityProviders: [OAuthProvider] = []
    private(set) var signInProviders: [OAuthProvider] = []

    init(
        makeUserID: @escaping () -> UUID = { UUID() },
        makeSignedInUserID: @escaping () -> UUID = { UUID() },
        initialValue: String = "PLACEHOLDER_VALUE",
        refreshedValue: String = "PLACEHOLDER_REFRESHED_VALUE",
        linkIdentityError: Error? = nil,
        signInFailuresRemaining: Int = 0
    ) {
        self.makeUserID = makeUserID
        self.makeSignedInUserID = makeSignedInUserID
        self.initialValue = initialValue
        self.refreshedValue = refreshedValue
        self.linkIdentityError = linkIdentityError
        self.signInFailuresRemaining = signInFailuresRemaining
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

    func linkIdentity(_ provider: OAuthProvider) async throws {
        try await ensureIdentity()
        linkIdentityProviders.append(provider)
        if let linkIdentityError {
            throw linkIdentityError
        }
        session?.isAnonymous = false
    }

    func signIn(_ provider: OAuthProvider) async throws {
        signInProviders.append(provider)
        if signInFailuresRemaining > 0 {
            signInFailuresRemaining -= 1
            throw FakeAuthServiceError.programmedSignInFailure
        }
        session = SessionState(
            userID: makeSignedInUserID(),
            value: initialValue,
            isAnonymous: false
        )
    }

    func setLinkIdentityError(_ error: Error?) {
        linkIdentityError = error
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

private enum FakeAuthServiceError: Error {
    case programmedSignInFailure
}
