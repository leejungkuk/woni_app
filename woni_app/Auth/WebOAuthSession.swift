//
//  WebOAuthSession.swift
//  woni_app
//

import AuthenticationServices
import Foundation
import UIKit

protocol WebOAuthAuthenticating {
    func authenticate(url: URL, callbackScheme: String?) async throws -> URL
}

enum WebOAuthSessionError: Error, Equatable {
    case flowInProgress
    case missingCallbackScheme
    case missingPresentationAnchor
    case failedToStart
    case missingCallbackURL
}

final class WebOAuthSession: NSObject, WebOAuthAuthenticating {
    private let makeContext: @MainActor () -> AuthenticationPresentationContextProvider?
    private var activeSession: ASWebAuthenticationSession?
    private var presentationContext: AuthenticationPresentationContextProvider?
    private var continuation: CheckedContinuation<URL, Error>?

    init(
        makeContext: @escaping @MainActor () -> AuthenticationPresentationContextProvider? =
            { AuthenticationPresentationContextProvider.current() }
    ) {
        self.makeContext = makeContext
        super.init()
    }

    func authenticate(url: URL, callbackScheme: String?) async throws -> URL {
        guard activeSession == nil else {
            throw WebOAuthSessionError.flowInProgress
        }
        guard let callbackScheme, !callbackScheme.isEmpty else {
            throw WebOAuthSessionError.missingCallbackScheme
        }
        guard let presentationContext = makeContext() else {
            throw WebOAuthSessionError.missingPresentationAnchor
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.complete(callbackURL: callbackURL, error: error)
                }
            }
            session.presentationContextProvider = presentationContext
            self.presentationContext = presentationContext
            activeSession = session

            if !session.start() {
                complete(callbackURL: nil, error: WebOAuthSessionError.failedToStart)
            }
        }
    }
}

private extension WebOAuthSession {
    func complete(callbackURL: URL?, error: Error?) {
        let continuation = continuation
        self.continuation = nil
        activeSession = nil
        presentationContext = nil

        if let error {
            continuation?.resume(throwing: error)
        } else if let callbackURL {
            continuation?.resume(returning: callbackURL)
        } else {
            continuation?.resume(throwing: WebOAuthSessionError.missingCallbackURL)
        }
    }
}

final class AuthenticationPresentationContextProvider: NSObject {
    private let anchor: ASPresentationAnchor

    private init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    static func current() -> AuthenticationPresentationContextProvider? {
        resolve(from: UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene })
    }

    /// 폴백 없이 해석한다 — 전면 활성 scene의 key window가 아니면 anchor를 만들지 않는다.
    /// scene 열거 순서·화면 밖 window로 대체하면 기기마다 다른 결과가 나온다.
    ///
    /// key window는 전면 활성 scene **전체**에서 찾는다. scene 하나를 먼저 고르고 그 안에서만
    /// 찾으면 열거 순서가 결과를 가른다 — key window가 없는 scene이 먼저 오면 로그인이 통째로 막힌다.
    /// `isKeyWindow`는 앱 전체가 아니라 scene마다 성립하므로 후보가 둘 이상일 수 있고,
    /// 그때는 어느 쪽에 띄울지가 임의라 고르지 않고 실패시킨다.
    ///
    /// 지금은 `UIApplicationSupportsMultipleScenes`를 선언하지 않아 scene이 항상 하나뿐이라
    /// 이 두 분기에 도달하지 않는다. 선언하는 순간 열거 순서가 로그인 성패를 가르므로,
    /// 위 주석이 약속하는 "순서 무관"을 코드가 실제로 지키도록 맞춰 둔다.
    static func resolve(from scenes: [UIWindowScene]) -> AuthenticationPresentationContextProvider? {
        let candidates = scenes
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .filter(\.isKeyWindow)
        guard candidates.count == 1, let anchor = candidates.first else {
            return nil
        }
        return AuthenticationPresentationContextProvider(anchor: anchor)
    }
}

extension AuthenticationPresentationContextProvider: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

extension AuthenticationPresentationContextProvider: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }
}
