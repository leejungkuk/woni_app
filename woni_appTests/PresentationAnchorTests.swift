//
//  PresentationAnchorTests.swift
//  woni_appTests
//

import Foundation
import Testing
import UIKit
@testable import woni_app

/// anchor 조건이 갖춰지지 않으면 폴백으로 덮지 않고 명시적으로 실패하는지 고정한다.
/// 폴백(scene 열거 순서·화면 밖 window)이 기기별 동작 차이의 원인이었다.
@MainActor
struct PresentationAnchorTests {
    @Test("후보 scene이 없으면 anchor를 만들지 않는다")
    func resolveWithoutScenesReturnsNil() {
        #expect(AuthenticationPresentationContextProvider.resolve(from: []) == nil)
    }

    /// key window가 정확히 하나일 때만 고른다는 판정을 고정한다. 이 단언이 없으면 조건을
    /// "하나라도 있으면"으로 되돌려도 아무 테스트가 깨지지 않는다 — 그 완화가 곧 어느 window에
    /// 띄울지 열거 순서가 정하는 옛 동작이다.
    ///
    /// `UIWindowScene`은 합성할 수 없어 테스트 호스트 앱의 실제 scene을 쓴다. 같은 scene을 두 번
    /// 넣어 후보를 둘로 만든다 — 멀티 scene에서 key window가 둘인 상황과 판정 입력이 같다.
    @Test("key window 후보가 둘 이상이면 고르지 않고 실패한다")
    func resolveWithAmbiguousCandidatesReturnsNil() throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindows = scenes
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .filter(\.isKeyWindow)
        try #require(
            keyWindows.count == 1,
            "테스트 호스트 앱에 전면 key window가 정확히 하나 있어야 이 판정을 세울 수 있다"
        )

        #expect(AuthenticationPresentationContextProvider.resolve(from: scenes) != nil)
        #expect(AuthenticationPresentationContextProvider.resolve(from: scenes + scenes) == nil)
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
