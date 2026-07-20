//
//  AppleIDTokenProvider.swift
//  woni_app
//

import Auth
import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct AppleIDTokenCredential: Equatable {
    let idToken: String
    let nonce: String

    var openIDConnectCredentials: OpenIDConnectCredentials {
        OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
    }
}

protocol AppleIDTokenProviding {
    func requestCredential() async throws -> AppleIDTokenCredential
}

enum AppleIDTokenError: Error, Equatable {
    case flowInProgress
    case randomGenerationFailed
    case missingPresentationAnchor
    case invalidCredential
    case missingIdentityToken
}

final class AppleIDTokenProvider: NSObject, AppleIDTokenProviding {
    private var continuation: CheckedContinuation<AppleIDTokenCredential, Error>?
    private var currentNonce: String?
    private var presentationContext: AuthenticationPresentationContextProvider?

    func requestCredential() async throws -> AppleIDTokenCredential {
        guard continuation == nil else {
            throw AppleIDTokenError.flowInProgress
        }
        guard let presentationContext = AuthenticationPresentationContextProvider.current() else {
            throw AppleIDTokenError.missingPresentationAnchor
        }

        let nonce = try Self.randomNonce()
        currentNonce = nonce
        self.presentationContext = presentationContext

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email, .fullName]
            request.nonce = Self.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = presentationContext
            controller.performRequests()
        }
    }
}

extension AppleIDTokenProvider: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(with: .failure(AppleIDTokenError.invalidCredential))
            return
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              !idToken.isEmpty,
              let nonce = currentNonce
        else {
            finish(with: .failure(AppleIDTokenError.missingIdentityToken))
            return
        }

        finish(with: .success(AppleIDTokenCredential(idToken: idToken, nonce: nonce)))
    }

    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(with: .failure(error))
    }
}

private extension AppleIDTokenProvider {
    func finish(with result: Result<AppleIDTokenCredential, Error>) {
        let continuation = continuation
        self.continuation = nil
        currentNonce = nil
        presentationContext = nil
        continuation?.resume(with: result)
    }

    static func randomNonce(length: Int = 32) throws -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var randomByte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &randomByte) == errSecSuccess else {
                throw AppleIDTokenError.randomGenerationFailed
            }
            if Int(randomByte) < characters.count {
                result.append(characters[Int(randomByte)])
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
