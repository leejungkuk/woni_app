//
//  AuthServiceTests.swift
//  woni_appTests
//

import Auth
import Foundation
import Testing
@testable import woni_app

@MainActor
struct AuthServiceTests {
    @Test("ensureIdentity는 세션이 없을 때만 익명 세션을 만든다")
    func ensureIdentityIsIdempotent() async throws {
        let userID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let authService = FakeAuthService(
            makeUserID: { userID },
            initialValue: "PLACEHOLDER_VALUE_A"
        )

        #expect(authService.currentAccessToken() == nil)
        #expect(authService.currentUserID == nil)
        #expect(authService.isAnonymous == false)

        try await authService.ensureIdentity()
        try await authService.ensureIdentity()

        #expect(authService.anonymousSignInCount == 1)
        #expect(authService.currentAccessToken() == "PLACEHOLDER_VALUE_A")
        #expect(authService.currentUserID == userID)
        #expect(authService.isAnonymous)
    }

    @Test("ensureIdentity는 동시 호출에도 익명 sign-in을 1회만 수행한다")
    func ensureIdentityCoalescesConcurrentCalls() async throws {
        let authService = FakeAuthService()

        async let first: Void = authService.ensureIdentity()
        async let second: Void = authService.ensureIdentity()
        _ = try await(first, second)

        #expect(authService.anonymousSignInCount == 1)
        #expect(authService.isAnonymous)
    }

    @Test("signOut은 인메모리 세션 상태를 비운다")
    func signOutClearsTokenAndUserID() async throws {
        let userID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let authService = FakeAuthService(
            makeUserID: { userID },
            initialValue: "PLACEHOLDER_VALUE_B"
        )

        try await authService.ensureIdentity()
        try await authService.signOut()

        #expect(authService.currentAccessToken() == nil)
        #expect(authService.currentUserID == nil)
        #expect(authService.isAnonymous == false)
    }

    @Test("signOut 후 재-ensureIdentity는 새 익명 유저를 만든다")
    func reEnsureAfterSignOutMintsNewUser() async throws {
        let firstID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let secondID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        var ids = [firstID, secondID]
        let authService = FakeAuthService(makeUserID: { ids.removeFirst() })

        try await authService.ensureIdentity()
        #expect(authService.currentUserID == firstID)

        try await authService.signOut()
        #expect(authService.currentUserID == nil)

        try await authService.ensureIdentity()
        #expect(authService.currentUserID == secondID)
        #expect(authService.anonymousSignInCount == 2)
    }

    @Test("토큰 조회와 refresh는 현재 상태를 노출한다")
    func tokenExposureReflectsCurrentSessionState() async throws {
        let authService = FakeAuthService(
            initialValue: "PLACEHOLDER_VALUE_C",
            refreshedValue: "PLACEHOLDER_VALUE_D"
        )

        try await authService.ensureIdentity()

        #expect(authService.currentAccessToken() == "PLACEHOLDER_VALUE_C")

        let refreshed = try await authService.refreshedAccessToken()

        #expect(refreshed == "PLACEHOLDER_VALUE_D")
        #expect(authService.currentAccessToken() == "PLACEHOLDER_VALUE_D")
        #expect(authService.refreshCount == 1)
    }

    @Test("세션이 없으면 refresh는 nil을 반환하고 refreshCount를 올리지 않는다")
    func refreshWithoutSessionReturnsNil() async throws {
        let authService = FakeAuthService()

        let refreshed = try await authService.refreshedAccessToken()

        #expect(refreshed == nil)
        #expect(authService.refreshCount == 0)
        #expect(authService.currentAccessToken() == nil)
    }

    @Test("cleanup code refresh 실패는 sessionMissing을 다시 던지고 무효화 신호를 1회 보낸다")
    func cleanupRefreshEmitsInvalidationOnce() async throws {
        let harness = try makeSupabaseHarness(
            expiresIn: 30,
            responses: [.http(statusCode: 403, data: cleanupErrorData())]
        )
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)

        let error = await capturedError {
            _ = try await harness.service.refreshedAccessToken()
        }
        await recorder.settle()

        #expect(error as? AuthError == .sessionMissing)
        #expect(recorder.count == 1)
        #expect(await harness.fetch.refreshRequestCount == 1)
        #expect(harness.client.currentSession == nil)
    }

    @Test("익명 세션의 cleanup refresh 실패는 sessionMissing만 던지고 무효화 신호를 보내지 않는다")
    func anonymousCleanupRefreshDoesNotEmitInvalidation() async throws {
        let harness = try makeSupabaseHarness(
            expiresIn: 30,
            responses: [.http(statusCode: 403, data: cleanupErrorData())],
            isAnonymous: true
        )
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)

        let error = await capturedError {
            _ = try await harness.service.refreshedAccessToken()
        }
        await recorder.settle()

        #expect(error as? AuthError == .sessionMissing)
        #expect(!recorder.hasEvents)
        #expect(await harness.fetch.refreshRequestCount == 1)
        #expect(harness.client.currentSession == nil)
    }

    @Test("5xx refresh 실패는 무효화 신호를 보내지 않는다")
    func serverFailureDoesNotEmitInvalidation() async throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "error_code": "unexpected_failure",
            "message": "temporary"
        ])
        let harness = try makeSupabaseHarness(
            expiresIn: 30,
            responses: [.http(statusCode: 500, data: data)]
        )
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)

        let error = await capturedError {
            _ = try await harness.service.refreshedAccessToken()
        }
        await recorder.settle()

        guard case .api = error as? AuthError else {
            Issue.record("5xx는 AuthError.api여야 합니다")
            return
        }
        #expect(!recorder.hasEvents)
        #expect(harness.client.currentSession != nil)
    }

    @Test("transport refresh 실패는 무효화 신호를 보내지 않는다")
    func transportFailureDoesNotEmitInvalidation() async throws {
        let harness = try makeSupabaseHarness(
            expiresIn: 30,
            responses: [.transport(URLError(.notConnectedToInternet))]
        )
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)

        let error = await capturedError {
            _ = try await harness.service.refreshedAccessToken()
        }
        await recorder.settle()

        #expect(error is URLError)
        #expect(!recorder.hasEvents)
        #expect(harness.client.currentSession != nil)
    }

    @Test("다른 세션 revoke는 현재 세션을 유지하고 무효화 신호를 보내지 않는다")
    func revokeOtherSessionsKeepsCurrentSession() async throws {
        let harness = try makeSupabaseHarness(
            expiresIn: 300,
            responses: [.http(statusCode: 200, data: Data())]
        )
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)
        let originalSession = try #require(harness.client.currentSession)

        try await harness.service.revokeOtherSessions()
        await recorder.settle()

        #expect(harness.client.currentSession == originalSession)
        #expect(!recorder.hasEvents)
        #expect(await harness.fetch.logoutScopes == ["others"])
    }

    @Test("다른 세션 revoke 뒤 연속 refresh 두 번은 무효화 신호를 한 번만 보낸다")
    func revokedSessionSignalsOnlyOnFirstRefresh() async throws {
        let harness = try makeSupabaseHarness(
            expiresIn: 300,
            responses: [
                .http(statusCode: 200, data: Data()),
                .http(statusCode: 403, data: cleanupErrorData())
            ]
        )
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)

        try await harness.service.revokeOtherSessions()
        let firstError = await capturedError {
            _ = try await harness.service.refreshedAccessToken()
        }
        let secondValue = try await harness.service.refreshedAccessToken()
        await recorder.settle()

        #expect(firstError as? AuthError == .sessionMissing)
        #expect(secondValue == nil)
        #expect(recorder.count == 1)
        #expect(await harness.fetch.refreshRequestCount == 1)
    }

    @Test("유효 기간이 충분한 세션 probe는 refresh하지 않는다")
    func probeSkipsSessionWithEnoughValidity() async throws {
        let harness = try makeSupabaseHarness(
            expiresIn: 300,
            responses: [.http(statusCode: 200, data: refreshedSessionData())]
        )
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)

        let outcome = await harness.service.probeSessionValidity()
        await recorder.settle()

        #expect(outcome)
        #expect(await harness.fetch.refreshRequestCount == 0)
        #expect(!recorder.hasEvents)
    }

    @Test("임박하거나 만료된 세션 probe는 refresh를 시도한다")
    func probeRefreshesExpiringSession() async throws {
        for expiresIn: TimeInterval in [60, -10] {
            let harness = try makeSupabaseHarness(
                expiresIn: expiresIn,
                responses: [.http(statusCode: 200, data: refreshedSessionData())]
            )
            let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)

            let outcome = await harness.service.probeSessionValidity()
            await recorder.settle()

            #expect(outcome)
            #expect(await harness.fetch.refreshRequestCount == 1)
            #expect(!recorder.hasEvents)
            #expect(harness.client.currentSession?.accessToken == placeholderRefreshedValue)
        }
    }

    @Test("임박 세션 probe의 cleanup 실패는 무효화 신호를 보낸다")
    func probeCleanupFailureEmitsInvalidation() async throws {
        let harness = try makeSupabaseHarness(
            expiresIn: 60,
            responses: [.http(statusCode: 403, data: cleanupErrorData())]
        )
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)

        let outcome = await harness.service.probeSessionValidity()
        await recorder.settle()

        #expect(!outcome)
        #expect(await harness.fetch.refreshRequestCount == 1)
        #expect(recorder.count == 1)
        #expect(harness.client.currentSession == nil)
    }

    @Test("임박 세션 probe의 기타 오류는 fail-open으로 true를 반환한다")
    func probeOtherFailureReturnsTrue() async throws {
        let harness = try makeSupabaseHarness(
            expiresIn: 60,
            responses: [.transport(URLError(.notConnectedToInternet))]
        )
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)

        let outcome = await harness.service.probeSessionValidity()
        await recorder.settle()

        #expect(outcome)
        // transport 오류는 SDK가 자동 재시도할 수 있어 정확 횟수 대신 시도 여부만 고정한다
        // (0이면 만료 미임박 skip 분기로 빠진 것 — 오류 분기 미진입).
        #expect(await harness.fetch.refreshRequestCount >= 1)
        #expect(!recorder.hasEvents)
        #expect(harness.client.currentSession != nil)
    }

    @Test("구독 전에 발생한 무효화 신호는 최신 1개가 보존된다")
    func invalidationBeforeSubscriptionIsBuffered() async throws {
        let harness = try makeSupabaseHarness(
            expiresIn: 30,
            responses: [.http(statusCode: 403, data: cleanupErrorData())]
        )

        _ = await capturedError {
            _ = try await harness.service.refreshedAccessToken()
        }
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)
        await recorder.settle()

        #expect(recorder.count == 1)
    }

    @Test("우리 signOut은 원격 무효화 신호를 보내지 않는다")
    func signOutDoesNotEmitInvalidation() async throws {
        let harness = try makeSupabaseHarness(
            expiresIn: 300,
            responses: [.http(statusCode: 200, data: Data())]
        )
        let recorder = InvalidationRecorder(stream: harness.service.sessionInvalidated)

        try await harness.service.signOut()
        await recorder.settle()

        #expect(harness.client.currentSession == nil)
        #expect(!recorder.hasEvents)
    }

    @Test("Fake revoke는 호출 수와 실패 주입을 지원한다")
    func fakeRevokeSupportsFailureInjection() async {
        let authService = FakeAuthService(revokeOtherSessionsFailuresRemaining: 1)

        let firstError = await capturedError {
            try await authService.revokeOtherSessions()
        }
        let secondError = await capturedError {
            try await authService.revokeOtherSessions()
        }

        #expect(firstError != nil)
        #expect(secondError == nil)
        #expect(authService.revokeOtherSessionsCount == 2)
    }

    @Test("Fake 원격 무효화 시뮬레이션은 세션을 비우고 신호를 보낸다")
    func fakeRemoteInvalidationClearsSessionAndSignals() async throws {
        let authService = FakeAuthService()
        try await authService.signIn(.google)
        let recorder = InvalidationRecorder(stream: authService.sessionInvalidated)

        authService.simulateRemoteInvalidation()
        await recorder.settle()

        #expect(authService.currentUserID == nil)
        #expect(recorder.count == 1)
    }

    @Test("Fake probe는 호출 결과로 무효화 신호를 주입할 수 있다")
    func fakeProbeSupportsInvalidationInjection() async throws {
        let authService = FakeAuthService(probeSessionValidityHandler: { false })
        try await authService.signIn(.apple)
        let recorder = InvalidationRecorder(stream: authService.sessionInvalidated)

        let outcome = await authService.probeSessionValidity()
        await recorder.settle()

        #expect(!outcome)
        #expect(authService.probeSessionValidityCount == 1)
        #expect(authService.currentUserID == nil)
        #expect(recorder.count == 1)
    }
}

private let placeholderCurrentValue = "PLACEHOLDER_CURRENT_VALUE"
private let placeholderRefreshedValue = "PLACEHOLDER_REFRESHED_VALUE"
private let placeholderRefreshCredential = "PLACEHOLDER_REFRESH_CREDENTIAL"

private func cleanupErrorData() throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "error_code": ["refresh", "token", "not", "found"].joined(separator: "_"),
        "message": "refresh credential missing"
    ])
}

@MainActor
private func capturedError(_ operation: () async throws -> Void) async -> Error? {
    do {
        try await operation()
        return nil
    } catch {
        return error
    }
}

@MainActor
private final class InvalidationRecorder {
    private(set) var count = 0
    private var task: Task<Void, Never>?

    var hasEvents: Bool {
        switch count {
        case 0:
            false
        default:
            true
        }
    }

    init(stream: AsyncStream<Void>) {
        task = Task { [weak self, stream] in
            for await _ in stream {
                guard !Task.isCancelled else {
                    return
                }
                self?.count += 1
            }
        }
    }

    func settle() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }

    deinit {
        task?.cancel()
    }
}

private struct SupabaseAuthHarness {
    let service: SupabaseAuthService
    let client: AuthClient
    let fetch: AuthFetchStub
}

@MainActor
private func makeSupabaseHarness(
    expiresIn: TimeInterval,
    responses: [AuthFetchStub.StubResponse],
    isAnonymous: Bool = false
) throws -> SupabaseAuthHarness {
    let authURL = try #require(URL(string: "https://auth.test.invalid/v1"))
    let redirectURL = try #require(URL(string: "woniapp://auth-callback"))
    let storage = AuthTestLocalStorage()
    let session = makeSession(
        accessToken: placeholderCurrentValue,
        expiresIn: expiresIn,
        isAnonymous: isAnonymous
    )
    try storage.store(
        key: "woni.auth-tests.session",
        value: JSONEncoder().encode(session)
    )
    let fetch = AuthFetchStub(responses: responses)
    let client = AuthClient(
        configuration: AuthClient.Configuration(
            url: authURL,
            storageKey: "woni.auth-tests.session",
            localStorage: storage,
            fetch: { request in
                try await fetch.respond(to: request)
            },
            autoRefreshToken: false
        )
    )
    let service = SupabaseAuthService(
        authClient: client,
        oauthRedirectURL: redirectURL
    )
    return SupabaseAuthHarness(service: service, client: client, fetch: fetch)
}

private func refreshedSessionData() throws -> Data {
    try AuthClient.Configuration.jsonEncoder.encode(
        makeSession(
            accessToken: placeholderRefreshedValue,
            expiresIn: 3600
        )
    )
}

private func makeSession(
    accessToken: String,
    expiresIn: TimeInterval,
    isAnonymous: Bool = false
) -> Session {
    let now = Date()
    return Session(
        accessToken: accessToken,
        tokenType: "bearer",
        expiresIn: expiresIn,
        expiresAt: now.addingTimeInterval(expiresIn).timeIntervalSince1970,
        refreshToken: placeholderRefreshCredential,
        user: User(
            id: UUID(),
            appMetadata: [:],
            userMetadata: [:],
            aud: "authenticated",
            createdAt: now,
            updatedAt: now,
            isAnonymous: isAnonymous
        )
    )
}

private final class AuthTestLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.withLock {
            values[key] = value
        }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock {
            values[key]
        }
    }

    func remove(key: String) throws {
        lock.withLock {
            values[key] = nil
        }
    }
}

private actor AuthFetchStub {
    enum StubResponse: @unchecked Sendable {
        case http(statusCode: Int, data: Data)
        case transport(URLError)
    }

    private var responses: [StubResponse]
    private(set) var refreshRequestCount = 0
    private(set) var logoutScopes: [String] = []

    init(responses: [StubResponse]) {
        self.responses = responses
    }

    func respond(to request: URLRequest) throws -> (Data, URLResponse) {
        if request.url?.path.hasSuffix("/token") == true {
            refreshRequestCount += 1
        }
        if request.url?.path.hasSuffix("/logout") == true {
            let components = request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)
            }
            logoutScopes.append(
                components?.queryItems?.first(where: { $0.name == "scope" })?.value ?? ""
            )
        }

        guard let response = responses.first else {
            throw URLError(.badServerResponse)
        }
        if responses.count > 1 {
            responses.removeFirst()
        }

        switch response {
        case let .http(statusCode, data):
            guard let url = request.url ?? URL(string: "https://auth.test.invalid"),
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: statusCode,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "application/json"]
                  )
            else {
                throw URLError(.badURL)
            }
            return (data, response)
        case let .transport(error):
            throw error
        }
    }
}
