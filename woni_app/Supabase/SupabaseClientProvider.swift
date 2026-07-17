//
//  SupabaseClientProvider.swift
//  woni_app
//

import Auth
import Foundation

enum SupabaseClientProvider {
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
                localStorage: KeychainLocalStorage(),
                logger: nil
            )
        )
    }
}
