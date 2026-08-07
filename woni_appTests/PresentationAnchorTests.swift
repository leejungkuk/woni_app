//
//  PresentationAnchorTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// anchor 조건이 갖춰지지 않으면 폴백으로 덮지 않고 명시적으로 실패하는지 고정한다.
/// 폴백(scene 열거 순서·화면 밖 window)이 기기별 동작 차이의 원인이었다.
@MainActor
struct PresentationAnchorTests {
    @Test("후보 scene이 없으면 anchor를 만들지 않는다")
    func resolveWithoutScenesReturnsNil() {
        #expect(AuthenticationPresentationContextProvider.resolve(from: []) == nil)
    }

    @Test("anchor가 없으면 웹 OAuth는 세션을 열지 않고 실패한다")
    func webOAuthThrowsWhenAnchorIsMissing() async throws {
        let session = WebOAuthSession(makeContext: { nil })
        let url = try #require(URL(string: "https://auth.test.invalid/authorize"))

        await #expect(throws: WebOAuthSessionError.missingPresentationAnchor) {
            _ = try await session.authenticate(url: url, callbackScheme: "woniapp")
        }
    }

    @Test("anchor가 없으면 Apple 인증은 컨트롤러를 만들기 전에 실패한다")
    func appleThrowsWhenAnchorIsMissing() async {
        let provider = AppleIDTokenProvider(makeContext: { nil })

        await #expect(throws: AppleIDTokenError.missingPresentationAnchor) {
            _ = try await provider.requestCredential()
        }
    }
}
