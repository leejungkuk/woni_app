//
//  AuthService.swift
//  woni_app
//

import Auth
import Foundation
import OSLog

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
    func probeSessionValidity() async -> Bool
    /// 매번 새 Apple credential을 요청하며, 시트 취소와 오류는 호출자에게 그대로 전달한다.
    func requestAppleAuthorizationCode() async throws -> String?
    func linkIdentity(_ provider: OAuthProvider) async throws
    func signIn(_ provider: OAuthProvider) async throws
    func signOut() async throws

    var sessionInvalidated: AsyncStream<Void> { get }
    /// 신원 변경 알림. 접근할 때마다 **새 구독 스트림**을 돌려주는 팬아웃이다 — 단일 소비자
    /// 스트림이면 구독자들이 이벤트를 나눠 가져 화면에 살아 있는 소비자가 갱신을 놓친다.
    var identityDidChange: AsyncStream<Void> { get }
    var currentUserID: UUID? { get }
    var currentUserEmail: String? { get }
    var isAnonymous: Bool { get }
    var hasAppleIdentity: Bool { get }
}

/// 특정 시점의 신원을 값으로 고정한 스냅샷. 신원을 SwiftUI가 관찰 가능한 저장 상태로
/// 옮기기 위한 매개다 — `AuthProviding`은 `@Observable`이 아니라 직접 읽으면 관찰 의존성이
/// 등록되지 않는다.
struct IdentitySnapshot: Equatable {
    let userID: UUID?
    let email: String?
    let isAnonymous: Bool

    init(from provider: any AuthProviding) {
        userID = provider.currentUserID
        email = provider.currentUserEmail
        isAnonymous = provider.isAnonymous
    }
}

/// 신원 변경을 다중 구독자에게 팬아웃한다(`LedgerChangeBroadcaster`와 같은 패턴).
@MainActor
private final class IdentityChangeBroadcaster {
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    var changes: AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    func broadcast() {
        continuations.values.forEach { $0.yield(()) }
    }

    deinit {
        continuations.values.forEach { $0.finish() }
    }
}

/// `AuthClient` 래핑. 프로젝트 기본 격리(`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`)로
/// MainActor 격리되며, in-flight task로 동시 `ensureIdentity` 호출을 유착해
/// 익명 sign-in이 신원당 1회만 발생하도록 보장한다(D3′ 지연·1회 발급).
final class SupabaseAuthService: AuthProviding {
    nonisolated static let logger = Logger(subsystem: "woni_app", category: "Auth")

    private let authClient: AuthClient
    private let oauthRedirectURL: URL
    private let appleIDTokenProvider: any AppleIDTokenProviding
    private let webOAuthSession: any WebOAuthAuthenticating
    private let sessionInvalidatedContinuation: AsyncStream<Void>.Continuation
    private let identityBroadcaster = IdentityChangeBroadcaster()
    private var ensureIdentityTask: Task<Void, Error>?
    private var authStateObservationTask: Task<Void, Never>?
    private var cachedAppleCredential: AppleIDTokenCredential?

    let sessionInvalidated: AsyncStream<Void>

    /// SDK 리스너는 첫 구독자에서 한 번만 붙인다. `onAuthStateChange`는 attach마다
    /// initialSession을 emit하며 만료 세션 refresh까지 유발하므로(SDK `AuthClient.swift:1491-1505`)
    /// 구독자 수만큼 반복되면 안 된다.
    var identityDidChange: AsyncStream<Void> {
        if authStateObservationTask == nil {
            authStateObservationTask = Task { [identityBroadcaster, authClient] in
                for await _ in authClient.authStateChanges {
                    identityBroadcaster.broadcast()
                }
            }
        }
        return identityBroadcaster.changes
    }

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

    func probeSessionValidity() async -> Bool {
        guard let session = authClient.currentSession,
              session.expiresAt - Date().timeIntervalSince1970 <= 90
        else {
            return true
        }

        do {
            _ = try await refreshSessionDetectingInvalidation(
                hadMemberSession: !session.user.isAnonymous
            )
            return true
        } catch AuthError.sessionMissing {
            return false
        } catch {
            return true
        }
    }

    func requestAppleAuthorizationCode() async throws -> String? {
        // 항상 새로 발급받는다. authorizationCode는 수명 5분·1회용이라 `cachedAppleCredential`을
        // 재사용하면 서버가 revoke를 조용히 건너뛴 채 탈퇴만 끝난다. 아래 `signIn(_:)`이 캐시를
        // 재사용하는 것과 반대로 동작하는 이유가 이것이므로 두 경로를 합치지 마라.
        try await appleIDTokenProvider.requestCredential().authorizationCode
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
                // 캐시는 연동 충돌 뒤 `signIn(.apple)`이 시트를 다시 띄우지 않게 하려는 것이라
                // `openIDConnectCredentials`만 쓴다. 1회용 authorizationCode는 떼어내 보관하지 않는다.
                cachedAppleCredential = AppleIDTokenCredential(
                    idToken: credential.idToken,
                    nonce: credential.nonce,
                    authorizationCode: nil
                )
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
        // .notice는 디스크에 영구 저장된다. §10 실기 검증에서 시나리오를 다 돌린 뒤
        // log collect로 회수해야 기기별 차이를 사후에 대조할 수 있다.
        Self.logger.notice("signIn started (\(String(describing: provider), privacy: .public))")
        do {
            switch provider {
            case .google:
                // launchFlow를 넘겨 SDK 기본 웹 세션을 우회한다. SDK 세션은 scene 미연결 anchor를
                // 쓰고 start() 반환값을 버려, 표시 실패 시 무한 대기로 고착된다.
                _ = try await authClient.signInWithOAuth(
                    provider: .google,
                    redirectTo: oauthRedirectURL,
                    queryParams: [("prompt", "select_account")]
                ) { [webOAuthSession, oauthRedirectURL] url in
                    try await webOAuthSession.authenticate(
                        url: url,
                        callbackScheme: oauthRedirectURL.scheme
                    )
                }
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
        } catch {
            Self.logger.error(
                """
                signIn failed (\(String(describing: provider), privacy: .public)): \
                \(String(describing: error), privacy: .private)
                """
            )
            throw error
        }
        Self.logger.notice("signIn succeeded (\(String(describing: provider), privacy: .public))")
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

    var currentUserEmail: String? {
        authClient.currentSession?.user.email
    }

    var isAnonymous: Bool {
        authClient.currentSession?.user.isAnonymous ?? false
    }

    var hasAppleIdentity: Bool {
        authClient.currentSession?.user.identities?.contains { $0.provider == "apple" } ?? false
    }

    deinit {
        sessionInvalidatedContinuation.finish()
        authStateObservationTask?.cancel()
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
        var email: String?
    }

    private let makeUserID: () -> UUID
    private let makeSignedInUserID: () -> UUID
    private let initialValue: String
    private let refreshedValue: String
    private let signedInEmail: String?
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
    private let identityBroadcaster = IdentityChangeBroadcaster()

    private(set) var anonymousSignInCount = 0
    private(set) var refreshCount = 0
    private(set) var linkIdentityProviders: [OAuthProvider] = []
    private(set) var signInProviders: [OAuthProvider] = []
    private(set) var signOutCount = 0
    private(set) var revokeOtherSessionsCount = 0
    private(set) var probeSessionValidityCount = 0
    private(set) var requestAppleAuthorizationCodeCount = 0

    var hasAppleIdentity: Bool
    var appleAuthorizationCode: String?
    /// 설정하면 `requestAppleAuthorizationCode()`가 이 오류를 던진다(시트 취소·SIWA 실패 재현).
    var appleAuthorizationCodeError: Error?

    let sessionInvalidated: AsyncStream<Void>

    var identityDidChange: AsyncStream<Void> {
        identityBroadcaster.changes
    }

    init(
        makeUserID: @escaping () -> UUID = { UUID() },
        makeSignedInUserID: @escaping () -> UUID = { UUID() },
        initialValue: String = "PLACEHOLDER_VALUE",
        refreshedValue: String = "PLACEHOLDER_REFRESHED_VALUE",
        signedInEmail: String? = nil,
        linkIdentityError: Error? = nil,
        signInError: Error? = nil,
        ensureIdentityFailuresRemaining: Int = 0,
        signInFailuresRemaining: Int = 0,
        signOutFailuresRemaining: Int = 0,
        revokeOtherSessionsFailuresRemaining: Int = 0,
        probeSessionValidityHandler: (() async -> Bool)? = nil,
        hasAppleIdentity: Bool = false,
        appleAuthorizationCode: String? = nil
    ) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.makeUserID = makeUserID
        self.makeSignedInUserID = makeSignedInUserID
        self.initialValue = initialValue
        self.refreshedValue = refreshedValue
        self.signedInEmail = signedInEmail
        self.linkIdentityError = linkIdentityError
        self.signInError = signInError
        self.ensureIdentityFailuresRemaining = ensureIdentityFailuresRemaining
        self.signInFailuresRemaining = signInFailuresRemaining
        self.signOutFailuresRemaining = signOutFailuresRemaining
        self.revokeOtherSessionsFailuresRemaining = revokeOtherSessionsFailuresRemaining
        self.probeSessionValidityHandler = probeSessionValidityHandler
        self.hasAppleIdentity = hasAppleIdentity
        self.appleAuthorizationCode = appleAuthorizationCode
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
                isAnonymous: true,
                email: nil
            )
            identityBroadcaster.broadcast()
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

    func probeSessionValidity() async -> Bool {
        probeSessionValidityCount += 1
        let outcome = await probeSessionValidityHandler?() ?? true
        if !outcome {
            simulateRemoteInvalidation()
        }
        return outcome
    }

    func requestAppleAuthorizationCode() async throws -> String? {
        requestAppleAuthorizationCodeCount += 1
        if let appleAuthorizationCodeError {
            throw appleAuthorizationCodeError
        }
        return appleAuthorizationCode
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
            identityBroadcaster.broadcast()
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
        session?.email = signedInEmail
        identityBroadcaster.broadcast()
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
            isAnonymous: false,
            email: nil
        )
        session?.email = signedInEmail
        // 실제 서비스의 hasAppleIdentity는 세션의 연동 provider에서 나온다. 대역도 같은 출처를 따라야
        // 세션을 만든 provider와 Apple 연동 여부가 어긋나지 않는다.
        hasAppleIdentity = provider == .apple
        identityBroadcaster.broadcast()
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
        identityBroadcaster.broadcast()
    }

    var currentUserID: UUID? {
        session?.userID
    }

    var currentUserEmail: String? {
        session?.email
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
