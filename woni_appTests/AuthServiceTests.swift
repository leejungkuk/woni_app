//
//  AuthServiceTests.swift
//  woni_appTests
//

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
}
