//
//  URLProtocolStub.swift
//  woni_appTests
//

import Foundation
@testable import woni_app

/// 세션마다 handler 와 기록을 따로 두는 URLProtocol 스텁. 새 네트워크 테스트가 같이 쓴다.
/// Swift Testing 은 스위트끼리 병렬로 돌 수 있어 static handler 하나는 서로 덮어쓴다 — 그래서
/// 세션 설정의 추가 헤더에 무작위 식별자를 넣고, 받은 요청의 그 헤더로 자기 세션의 handler 를 찾는다.
final class URLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let sessionHeader = "X-URLProtocolStub-Session"
    private static let lock = NSLock()
    private static var sessions: [String: (handler: Handler, log: StubbedRequestLog)] = [:]

    /// handler 를 이 세션에만 묶은 `URLSession` 과 그 세션이 받은 요청 기록.
    static func makeSession(handler: @escaping Handler) -> (URLSession, StubbedRequestLog) {
        let id = UUID().uuidString
        let log = StubbedRequestLog()
        lock.lock()
        sessions[id] = (handler, log)
        lock.unlock()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        configuration.httpAdditionalHeaders = [sessionHeader: id]
        return (URLSession(configuration: configuration), log)
    }

    static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) throws -> (HTTPURLResponse, Data) {
        guard
            let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
        else {
            throw URLProtocolStubError.invalidResponse
        }
        return (response, Data(body.utf8))
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let session = Self.session(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLProtocolStubError.missingHandler)
            return
        }

        session.log.append(StubbedRequest(request, droppingHeader: Self.sessionHeader))
        do {
            let (response, data) = try session.handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func session(for request: URLRequest) -> (handler: Handler, log: StubbedRequestLog)? {
        guard let id = request.value(forHTTPHeaderField: sessionHeader) else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return sessions[id]
    }
}

/// 공용 스텁 세션을 쓰는 `APIClient` 와 그 세션의 요청 기록.
@MainActor
func makeStubbedClient(handler: @escaping URLProtocolStub.Handler) -> (APIClient, StubbedRequestLog) {
    let (session, log) = URLProtocolStub.makeSession(handler: handler)
    return (APIClient(session: session), log)
}

/// 스텁이 받은 요청 하나. 세션 식별 헤더는 빼고 남긴다 — 서버가 받을 헤더만 본다.
struct StubbedRequest {
    let method: String?
    let url: URL?
    let headers: [String: String]
    let cachePolicy: URLRequest.CachePolicy
    let body: Data?

    init(_ request: URLRequest, droppingHeader header: String) {
        method = request.httpMethod
        url = request.url
        var headers = request.allHTTPHeaderFields ?? [:]
        headers.removeValue(forKey: header)
        self.headers = headers
        cachePolicy = request.cachePolicy
        body = Self.bodyData(from: request)
    }

    /// URLSession 은 본문을 `httpBodyStream` 으로 옮겨 넘기므로 둘 다 읽는다.
    private static func bodyData(from request: URLRequest) -> Data? {
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
}

/// 한 세션이 받은 요청을 받은 순서대로 담는다. 스텁은 URLSession 의 스레드에서 기록한다.
final class StubbedRequestLog {
    private let lock = NSLock()
    private var recorded: [StubbedRequest] = []

    var requests: [StubbedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    fileprivate func append(_ request: StubbedRequest) {
        lock.lock()
        recorded.append(request)
        lock.unlock()
    }
}

enum URLProtocolStubError: Error {
    case missingHandler
    case invalidResponse
}
