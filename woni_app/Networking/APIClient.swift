//
//  APIClient.swift
//  woni_app
//

import Foundation

/// URLSession 기반 공통 클라이언트. 응답 봉투(`APIEnvelope`)를 벗겨 `data` 만 돌려준다.
/// 봉투 `success=false` 면 `APIError.server` 로 throw → 호출부는 `code` 로 분기.
struct APIClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let token: () -> String?

    init(
        session: URLSession = .shared,
        token: @escaping () -> String? = { ProcessInfo.processInfo.environment["ACCESS_TOKEN"] }
    ) {
        self.session = session
        self.token = token
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let request = try makeRequest(path, method: "GET", query: query)
        return try await send(request)
    }

    func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        var request = try makeRequest(path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw APIError.encoding(error)
        }
        return try await send(request)
    }
}

private extension APIClient {
    func makeRequest(
        _ path: String,
        method: String,
        query: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard var components = URLComponents(string: APIConfig.baseURL + path) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let value = token()?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            request.setValue("Bearer \(value)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard !data.isEmpty else {
            if let statusCode, !isSuccessStatus(statusCode) {
                throw APIError.httpStatus(
                    code: statusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: statusCode)
                )
            }
            throw APIError.emptyResponse
        }

        let envelope: APIEnvelope<T>
        do {
            envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        } catch {
            if let statusCode, !isSuccessStatus(statusCode) {
                throw APIError.httpStatus(
                    code: statusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: statusCode)
                )
            }
            throw APIError.decoding(error)
        }

        guard envelope.success else {
            throw APIError.server(
                code: envelope.code ?? "UNKNOWN",
                message: envelope.message ?? "알 수 없는 오류가 발생했습니다."
            )
        }
        if let statusCode, !isSuccessStatus(statusCode) {
            throw APIError.httpStatus(
                code: statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: statusCode)
            )
        }
        guard let payload = envelope.data else {
            throw APIError.emptyResponse
        }
        return payload
    }

    func isSuccessStatus(_ statusCode: Int) -> Bool {
        (200..<300).contains(statusCode)
    }
}
