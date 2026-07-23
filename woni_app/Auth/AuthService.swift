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
    func revokeOtherSessions() async throws
    func probeSessionValidity() async
    func linkIdentity(_ provider: OAuthProvider) async throws
    func signIn(_ provider: OAuthProvider) async throws
    func signOut() async throws

    var sessionInvalidated: AsyncStream<Void> { get }
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
    private let sessionInvalidatedContinuation: AsyncStream<Void>.Continuation
    private var ensureIdentityTask: Task<Void, Error>?
    private var cachedAppleCredential: AppleIDTokenCredential?

    let sessionInvalidated: AsyncStream<Void>

    init(
        authClient: AuthClient,
        oauthRedirectURL: URL,
        appleIDTokenProvider: any AppleIDTokenProviding = AppleIDTokenProvider(),
        webOAuthSession: any WebOAuthAuthenticating = WebOAuthSession()
    ) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.authClient = authClient
        self.oauthRedirectURL = oauthRedirectURL
        self.appleIDTokenProvider = appleIDTokenProvider
        self.webOAuthSession = webOAuthSession
        sessionInvalidated = stream
        sessionInvalidatedContinuation = continuation
    }

    convenience init(bundle: Bundle = .main) throws {
        try self.init(
            authClient: SupabaseClientProvider.makeAuthClient(bundle: bundle),
            oauthRedirectURL: SupabaseClientProvider.oauthRedirectURL()
        )
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
        guard let session = authClient.currentSession else {
            return nil
        }

        return try await refreshSessionDetectingInvalidation(
            hadMemberSession: !session.user.isAnonymous
        ).accessToken
    }

    func revokeOtherSessions() async throws {
        try await authClient.signOut(scope: .others)
    }

    func probeSessionValidity() async {
        guard let session = authClient.currentSession,
              session.expiresAt - Date().timeIntervalSince1970 <= 90
        else {
            return
        }

        _ = try? await refreshSessionDetectingInvalidation(
            hadMemberSession: !session.user.isAnonymous
        )
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

    deinit {
        sessionInvalidatedContinuation.finish()
    }
}

private extension SupabaseAuthService {
    func refreshSessionDetectingInvalidation(hadMemberSession: Bool) async throws -> Session {
        do {
            return try await authClient.refreshSession()
        } catch AuthError.sessionMissing {
            if hadMemberSession {
                sessionInvalidatedContinuation.yield()
            }
            throw AuthError.sessionMissing
        }
    }

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
    private var signInError: Error?
    private var signInFailuresRemaining: Int
    private var signOutFailuresRemaining: Int
    private var ensureIdentityFailuresRemaining: Int
    private var revokeOtherSessionsFailuresRemaining: Int
    private var probeSessionValidityHandler: (() async -> Bool)?
    private var revokeOtherSessionsHandler: (() async -> Void)?
    private var session: SessionState?
    private var ensureIdentityTask: Task<Void, Never>?
    private let sessionInvalidatedContinuation: AsyncStream<Void>.Continuation

    private(set) var anonymousSignInCount = 0
    private(set) var refreshCount = 0
    private(set) var linkIdentityProviders: [OAuthProvider] = []
    private(set) var signInProviders: [OAuthProvider] = []
    private(set) var signOutCount = 0
    private(set) var revokeOtherSessionsCount = 0
    private(set) var probeSessionValidityCount = 0

    let sessionInvalidated: AsyncStream<Void>

    init(
        makeUserID: @escaping () -> UUID = { UUID() },
        makeSignedInUserID: @escaping () -> UUID = { UUID() },
        initialValue: String = "PLACEHOLDER_VALUE",
        refreshedValue: String = "PLACEHOLDER_REFRESHED_VALUE",
        linkIdentityError: Error? = nil,
        signInError: Error? = nil,
        ensureIdentityFailuresRemaining: Int = 0,
        signInFailuresRemaining: Int = 0,
        signOutFailuresRemaining: Int = 0,
        revokeOtherSessionsFailuresRemaining: Int = 0,
        probeSessionValidityHandler: (() async -> Bool)? = nil
    ) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.makeUserID = makeUserID
        self.makeSignedInUserID = makeSignedInUserID
        self.initialValue = initialValue
        self.refreshedValue = refreshedValue
        self.linkIdentityError = linkIdentityError
        self.signInError = signInError
        self.ensureIdentityFailuresRemaining = ensureIdentityFailuresRemaining
        self.signInFailuresRemaining = signInFailuresRemaining
        self.signOutFailuresRemaining = signOutFailuresRemaining
        self.revokeOtherSessionsFailuresRemaining = revokeOtherSessionsFailuresRemaining
        self.probeSessionValidityHandler = probeSessionValidityHandler
        sessionInvalidated = stream
        sessionInvalidatedContinuation = continuation
    }

    func ensureIdentity() async throws {
        if let task = ensureIdentityTask {
            await task.value
            return
        }
        guard session == nil else {
            return
        }
        if ensureIdentityFailuresRemaining > 0 {
            ensureIdentityFailuresRemaining -= 1
            throw FakeAuthServiceError.programmedEnsureIdentityFailure
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

    func revokeOtherSessions() async throws {
        revokeOtherSessionsCount += 1
        await revokeOtherSessionsHandler?()
        if revokeOtherSessionsFailuresRemaining > 0 {
            revokeOtherSessionsFailuresRemaining -= 1
            throw FakeAuthServiceError.programmedRevokeOtherSessionsFailure
        }
    }

    func probeSessionValidity() async {
        probeSessionValidityCount += 1
        if await probeSessionValidityHandler?() == true {
            simulateRemoteInvalidation()
        }
    }

    func setProbeSessionValidityHandler(_ handler: (() async -> Bool)?) {
        probeSessionValidityHandler = handler
    }

    func setRevokeOtherSessionsHandler(_ handler: (() async -> Void)?) {
        revokeOtherSessionsHandler = handler
    }

    func simulateRemoteInvalidation(removingCurrentSession: Bool = true) {
        if removingCurrentSession {
            session = nil
        }
        sessionInvalidatedContinuation.yield()
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
        if let signInError {
            throw signInError
        }
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
        signOutCount += 1
        if signOutFailuresRemaining > 0 {
            signOutFailuresRemaining -= 1
            throw FakeAuthServiceError.programmedSignOutFailure
        }
        session = nil
    }

    var currentUserID: UUID? {
        session?.userID
    }

    var isAnonymous: Bool {
        session?.isAnonymous ?? false
    }

    deinit {
        sessionInvalidatedContinuation.finish()
    }
}

private enum FakeAuthServiceError: Error {
    case programmedEnsureIdentityFailure
    case programmedSignInFailure
    case programmedSignOutFailure
    case programmedRevokeOtherSessionsFailure
}
