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
    private var activeSession: ASWebAuthenticationSession?
    private var presentationContext: AuthenticationPresentationContextProvider?
    private var continuation: CheckedContinuation<URL, Error>?

    func authenticate(url: URL, callbackScheme: String?) async throws -> URL {
        guard activeSession == nil else {
            throw WebOAuthSessionError.flowInProgress
        }
        guard let callbackScheme, !callbackScheme.isEmpty else {
            throw WebOAuthSessionError.missingCallbackScheme
        }
        guard let presentationContext = AuthenticationPresentationContextProvider.current() else {
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
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        else {
            return nil
        }
        let anchor = windowScene.windows.first(where: \.isKeyWindow)
            ?? ASPresentationAnchor(windowScene: windowScene)
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
