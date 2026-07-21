//
//  SupabaseConfig.swift
//  woni_app
//

import Foundation

struct SupabaseConfig: Equatable {
    let supabaseURL: URL
    let anonKey: String

    var authURL: URL {
        supabaseURL
            .appendingPathComponent("auth")
            .appendingPathComponent("v1")
    }

    static func load(bundle: Bundle = .main) throws -> SupabaseConfig {
        let urlString = try requiredInfoString("SUPABASE_URL", bundle: bundle)
        let anonKey = try requiredInfoString("SUPABASE_ANON_KEY", bundle: bundle)

        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              !scheme.isEmpty,
              let host = url.host,
              !host.isEmpty
        else {
            throw SupabaseConfigError.invalidURL(key: "SUPABASE_URL")
        }

        return SupabaseConfig(supabaseURL: url, anonKey: anonKey)
    }

    private static func requiredInfoString(_ key: String, bundle: Bundle) throws -> String {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
            throw SupabaseConfigError.missingValue(key: key)
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$(") else {
            throw SupabaseConfigError.missingValue(key: key)
        }

        return value
    }
}

enum SupabaseConfigError: LocalizedError, Equatable {
    case missingValue(key: String)
    case invalidURL(key: String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(key):
            return "\(key) is missing. Define it in Config/Secrets.xcconfig."
        case let .invalidURL(key):
            return "\(key) must be a valid URL. Define it in Config/Secrets.xcconfig."
        }
    }
}
