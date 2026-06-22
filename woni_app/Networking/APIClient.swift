//
//  APIClient.swift
//  woni_app
//

import Foundation

/// URLSession 기반 공통 클라이언트. 응답 봉투(`APIEnvelope`)를 벗겨 `data` 만 돌려준다.
/// 봉투 `success=false` 면 `APIError.server` 로 throw → 호출부는 `code` 로 분기.
struct APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(string: APIConfig.baseURL + path) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let data: Data
        do {
            (data, _) = try await session.data(from: url)
        } catch {
            throw APIError.transport(error)
        }

        let envelope: APIEnvelope<T>
        do {
            envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }

        guard envelope.success else {
            throw APIError.server(
                code: envelope.code ?? "UNKNOWN",
                message: envelope.message ?? "알 수 없는 오류가 발생했습니다."
            )
        }
        guard let payload = envelope.data else {
            throw APIError.emptyResponse
        }
        return payload
    }
}
