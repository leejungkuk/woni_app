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
    private let tokenProvider: () -> String?
    private let tokenRefresher: () async throws -> String?

    init(
        session: URLSession = .shared,
        authProvider: (any AuthProviding)? = nil
    ) {
        self.session = session
        tokenProvider = { authProvider?.currentAccessToken() }
        tokenRefresher = {
            guard let authProvider else {
                return nil
            }
            return try await authProvider.refreshedAccessToken()
        }
        encoder = JSONEncoder()
        decoder = JSONDecoder()
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
        if let value = normalizedToken(tokenProvider()) {
            request.setValue("Bearer \(value)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// 401(UNAUTHORIZED) 응답을 만나면 토큰을 1회 refresh해 동일 요청을 1회만 재시도한다.
    /// 재시도도 실패하면 그 오류를 그대로 전파한다(무한 루프 금지).
    /// 여러 요청이 동시에 401을 받으면 각자 독립적으로 refresh를 호출할 수 있다(refresh
    /// 코얼레싱은 이 계층이 아니라 코디네이션 계층(step5 FIFO sync 엔진·step8 로그아웃)이
    /// 담당한다 — `AuthProviding.ensureIdentity`의 in-flight 유착과 동일한 계층 분리).
    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            return try await sendOnce(request)
        } catch {
            guard isUnauthorized(error) else {
                throw error
            }

            let refreshedToken = try await tokenRefresher()
            guard let refreshedToken = normalizedToken(refreshedToken) else {
                throw error
            }

            var retryRequest = request
            retryRequest.setValue(
                "Bearer \(refreshedToken)",
                forHTTPHeaderField: "Authorization"
            )
            return try await sendOnce(retryRequest)
        }
    }

    func sendOnce<T: Decodable>(_ request: URLRequest) async throws -> T {
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
        (200 ..< 300).contains(statusCode)
    }

    /// 재시도(refresh) 대상인 UNAUTHORIZED 여부. `sendOnce`는 실패 봉투를 status보다 먼저
    /// `APIError.server(code:)`로 매핑하고 `APIError.server`는 HTTP status를 보존하지 않으므로,
    /// 봉투로 디코딩되는 401은 `code == "UNAUTHORIZED"`로만 감지된다. 현재 서버 계약상 401은
    /// 필터 레벨 인증 실패까지 항상 `UNAUTHORIZED` code로만 응답하므로(다른 오류 code는 400/409)
    /// 이 조합으로 충분하다. 서버가 401에 다른 code(예: TOKEN_EXPIRED)를 도입하면 여기서
    /// 그 code도 refresh 대상으로 인정해야 한다.
    func isUnauthorized(_ error: Error) -> Bool {
        switch error {
        case let APIError.httpStatus(code, _):
            return code == 401
        case let APIError.server(code, _):
            return code == "UNAUTHORIZED"
        default:
            return false
        }
    }

    func normalizedToken(_ token: String?) -> String? {
        guard let value = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
