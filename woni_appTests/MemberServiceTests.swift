//
//  MemberServiceTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 탈퇴 DELETE의 요청 계약(본문 유무·Content-Type·타임아웃·인증·401 재시도)을
/// URLProtocol 스텁으로 검증한다. 본문과 Content-Type이 어긋나면 서버가 오류 대신
/// "코드 없음"으로 조용히 처리하므로 둘을 항상 함께 단언한다.
@Suite(.serialized)
@MainActor
struct MemberServiceTests {
    @Test("코드가 있으면 appleAuthorizationCode 본문과 Content-Type을 함께 보낸다")
    func withdrawSendsAuthorizationCodeBodyWithJSONContentType() async throws {
        let recorder = MemberRequestRecorder()
        MemberURLProtocol.handler = { request in
            recorder.record(request)
            return try makeMemberResponse(for: request, data: voidSuccessEnvelope())
        }
        defer { MemberURLProtocol.handler = nil }

        try await MemberService(client: makeMemberClient())
            .withdraw(appleAuthorizationCode: "apple-authorization-code")

        let request = try #require(recorder.snapshot())
        let body = try #require(request.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(request.method == "DELETE")
        #expect(request.url?.path == "/api/v1/members/me")
        #expect(request.contentType == "application/json")
        #expect(json == ["appleAuthorizationCode": "apple-authorization-code"])
    }

    @Test("코드는 앞뒤 공백만 잘라내고 내부 문자는 그대로 보낸다")
    func withdrawTrimsOnlySurroundingWhitespace() async throws {
        let recorder = MemberRequestRecorder()
        MemberURLProtocol.handler = { request in
            recorder.record(request)
            return try makeMemberResponse(for: request, data: voidSuccessEnvelope())
        }
        defer { MemberURLProtocol.handler = nil }

        try await MemberService(client: makeMemberClient())
            .withdraw(appleAuthorizationCode: " \n apple auth\tcode \n")

        let request = try #require(recorder.snapshot())
        let body = try #require(request.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        // 공백 제거를 내부까지 확장하면(`filter { !$0.isWhitespace }`) 1회용 크리덴셜이 조용히
        // 변조된 채 전송되고 서버 revoke가 실패한다. 앞뒤만 잘린 값이어야 한다.
        #expect(json == ["appleAuthorizationCode": "apple auth\tcode"])
    }

    @Test("코드가 nil이면 본문도 Content-Type도 보내지 않는다")
    func withdrawOmitsBodyAndContentTypeWhenCodeIsNil() async throws {
        let recorder = MemberRequestRecorder()
        MemberURLProtocol.handler = { request in
            recorder.record(request)
            return try makeMemberResponse(for: request, data: voidSuccessEnvelope())
        }
        defer { MemberURLProtocol.handler = nil }

        try await MemberService(client: makeMemberClient()).withdraw(appleAuthorizationCode: nil)

        let request = try #require(recorder.snapshot())
        #expect(request.method == "DELETE")
        #expect(request.url?.path == "/api/v1/members/me")
        #expect(request.body == nil)
        #expect(request.contentType == nil)
    }

    @Test(
        "코드가 공백뿐이면 본문 없는 DELETE를 보낸다",
        arguments: ["", " ", "\n\t "]
    )
    func withdrawOmitsBodyWhenCodeIsBlank(code: String) async throws {
        let recorder = MemberRequestRecorder()
        MemberURLProtocol.handler = { request in
            recorder.record(request)
            return try makeMemberResponse(for: request, data: voidSuccessEnvelope())
        }
        defer { MemberURLProtocol.handler = nil }

        try await MemberService(client: makeMemberClient()).withdraw(appleAuthorizationCode: code)

        let request = try #require(recorder.snapshot())
        #expect(request.body == nil)
        #expect(request.contentType == nil)
    }

    @Test("본문 있는 탈퇴 요청은 타임아웃을 요청 자체에 싣는다")
    func withdrawSpecifiesTimeoutOnRequest() async throws {
        let recorder = MemberRequestRecorder()
        MemberURLProtocol.handler = { request in
            recorder.record(request)
            return try makeMemberResponse(for: request, data: voidSuccessEnvelope())
        }
        defer { MemberURLProtocol.handler = nil }

        try await MemberService(client: makeMemberClient()).withdraw(appleAuthorizationCode: "apple-code")

        let request = try #require(recorder.snapshot())
        // 요청에 박지 않으면 URLRequest 기본값 60초가 남는다. 계약 하한 20초는 그것으로도
        // 만족하지만 기본값 변경에 조용히 의존하게 되므로 명시값 자체를 고정한다.
        #expect(request.timeoutInterval == 30)
    }

    @Test("data가 null인 성공 봉투를 오류 없이 처리한다")
    func withdrawAcceptsNullDataSuccessEnvelope() async throws {
        MemberURLProtocol.handler = { request in
            try makeMemberResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": true,
                        "code": null,
                        "data": null,
                        "message": null,
                        "timestamp": "2026-08-04T09:00:00"
                    }
                    """.utf8
                )
            )
        }
        defer { MemberURLProtocol.handler = nil }

        try await MemberService(client: makeMemberClient())
            .withdraw(appleAuthorizationCode: "apple-code")
    }

    @Test("401이면 refresh 후 본문과 Content-Type을 유지한 채 한 번 재시도한다")
    func withdrawRefreshesAndRetriesOnceOnUnauthorized() async throws {
        let recorder = MemberRequestRecorder()
        MemberURLProtocol.handler = { request in
            recorder.record(request)
            return try makeMemberResponse(
                for: request,
                statusCode: recorder.count == 1 ? 401 : 200,
                data: recorder.count == 1 ? unauthorizedEnvelope() : voidSuccessEnvelope()
            )
        }
        defer { MemberURLProtocol.handler = nil }

        let authService = FakeAuthService(
            initialValue: "expired-token",
            refreshedValue: "refreshed-token"
        )
        try await authService.ensureIdentity()
        let client = makeMemberClient(authProvider: authService)

        try await MemberService(client: client).withdraw(appleAuthorizationCode: "apple-code")

        let requests = recorder.snapshots()
        #expect(authService.refreshCount == 1)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.method == "DELETE" })
        #expect(requests.allSatisfy { $0.contentType == "application/json" })
        #expect(requests.allSatisfy { $0.body == Data(#"{"appleAuthorizationCode":"apple-code"}"#.utf8) })
        #expect(requests.first?.authorization == "Bearer expired-token")
        #expect(requests.last?.authorization == "Bearer refreshed-token")
    }

    @Test("액세스 토큰을 Bearer Authorization 헤더로 싣는다")
    func withdrawSendsBearerAuthorizationHeader() async throws {
        let recorder = MemberRequestRecorder()
        MemberURLProtocol.handler = { request in
            recorder.record(request)
            return try makeMemberResponse(for: request, data: voidSuccessEnvelope())
        }
        defer { MemberURLProtocol.handler = nil }

        let authService = FakeAuthService(initialValue: "unit-test-token")
        try await authService.ensureIdentity()
        let client = makeMemberClient(authProvider: authService)

        try await MemberService(client: client).withdraw(appleAuthorizationCode: nil)

        #expect(try #require(recorder.snapshot()).authorization == "Bearer unit-test-token")
    }

    @Test("실패 봉투는 APIError.server로 호출부에 전파된다")
    func withdrawPropagatesFailureEnvelope() async throws {
        MemberURLProtocol.handler = { request in
            try makeMemberResponse(for: request, statusCode: 413, data: bodyTooLargeEnvelope())
        }
        defer { MemberURLProtocol.handler = nil }

        do {
            try await MemberService(client: makeMemberClient())
                .withdraw(appleAuthorizationCode: "apple-code")
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "REQUEST_BODY_TOO_LARGE")
            #expect(message == "요청 본문이 너무 큽니다. 나눠서 보내 주세요.")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }
}

private struct MemberRecordedRequest {
    let url: URL?
    let method: String?
    let contentType: String?
    let authorization: String?
    let timeoutInterval: TimeInterval
    let body: Data?
}

private final class MemberRequestRecorder {
    private let lock = NSLock()
    private var requests: [MemberRecordedRequest] = []

    func record(_ request: URLRequest) {
        let recordedRequest = MemberRecordedRequest(
            url: request.url,
            method: request.httpMethod,
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            timeoutInterval: request.timeoutInterval,
            body: memberRequestBodyData(from: request)
        )

        lock.lock()
        requests.append(recordedRequest)
        lock.unlock()
    }

    func snapshot() -> MemberRecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.last
    }

    func snapshots() -> [MemberRecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }
}

private final class MemberURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: MemberURLProtocolError.missingHandler)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum MemberURLProtocolError: Error {
    case missingHandler
    case invalidResponse
}

private func makeMemberClient(authProvider: (any AuthProviding)? = nil) -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MemberURLProtocol.self]
    return APIClient(session: URLSession(configuration: configuration), authProvider: authProvider)
}

private func makeMemberResponse(
    for request: URLRequest,
    statusCode: Int = 200,
    data: Data
) throws -> (HTTPURLResponse, Data) {
    guard
        let url = request.url,
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )
    else {
        throw MemberURLProtocolError.invalidResponse
    }
    return (response, data)
}

private func memberRequestBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while true {
        let bytesRead = stream.read(&buffer, maxLength: buffer.count)
        guard bytesRead > 0 else {
            break
        }
        data.append(contentsOf: buffer.prefix(bytesRead))
    }
    return data
}

private func voidSuccessEnvelope() -> Data {
    Data(#"{ "success": true, "data": null }"#.utf8)
}

private func unauthorizedEnvelope() -> Data {
    Data(#"{ "success": false, "code": "UNAUTHORIZED", "message": "로그인이 필요합니다.", "data": null }"#.utf8)
}

private func bodyTooLargeEnvelope() -> Data {
    Data(
        """
        {
            "success": false,
            "code": "REQUEST_BODY_TOO_LARGE",
            "message": "요청 본문이 너무 큽니다. 나눠서 보내 주세요.",
            "timestamp": "2026-08-04T09:00:00"
        }
        """.utf8
    )
}
