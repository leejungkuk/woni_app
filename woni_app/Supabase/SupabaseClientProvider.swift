//
//  SupabaseClientProvider.swift
//  woni_app
//

import Auth
import Foundation

enum SupabaseClientProvider {
    private static let redirectURLString = "woniapp://auth-callback"

    static func makeAuthClient(bundle: Bundle = .main) throws -> AuthClient {
        try makeAuthClient(config: SupabaseConfig.load(bundle: bundle))
    }

    static func makeAuthClient(config: SupabaseConfig) -> AuthClient {
        AuthClient(
            configuration: AuthClient.Configuration(
                url: config.authURL,
                headers: [
                    "apikey": config.anonKey
                ],
                redirectToURL: URL(string: redirectURLString),
                localStorage: KeychainLocalStorage(),
                logger: nil,
                autoRefreshToken: false
            )
        )
    }

    static func oauthRedirectURL() throws -> URL {
        guard let url = URL(string: redirectURLString) else {
            throw SupabaseClientProviderError.invalidOAuthRedirectURL
        }
        return url
    }
}

enum SupabaseClientProviderError: Error, Equatable {
    case invalidOAuthRedirectURL
}
