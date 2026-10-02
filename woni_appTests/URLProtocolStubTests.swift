//
//  URLProtocolStubTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 공용 스텁(`URLProtocolStub`)이 세션마다 handler 와 기록을 따로 두는지 검증한다.
/// 스위트끼리 병렬로 돌 때 static handler 하나는 서로 덮어쓰므로, 두 세션을 동시에 돌려 본다.
@MainActor
struct URLProtocolStubTests {
    @Test("동시에 도는 두 세션은 각자 자기 응답만 받고 기록도 섞이지 않는다")
    func keepsHandlersApartAcrossConcurrentSessions() async throws {
        let (clientA, logA) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: #"{ "success": true, "data": { "id": "A" } }"#)
        }
        let (clientB, logB) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: #"{ "success": true, "data": { "id": "B" } }"#)
        }
        let rounds = 50

        let replies = try await withThrowingTaskGroup(of: (sent: String, received: String).self) { group in
            for index in 0 ..< rounds {
                group.addTask {
                    let received = try await fetchID(from: clientA, path: "/a/\(index)")
                    return ("A", received)
                }
                group.addTask {
                    let received = try await fetchID(from: clientB, path: "/b/\(index)")
                    return ("B", received)
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(replies.count == rounds * 2)
        #expect(replies.filter { $0.sent != $0.received }.isEmpty)
        let expectedA = Set((0 ..< rounds).map { "/a/\($0)" })
        let expectedB = Set((0 ..< rounds).map { "/b/\($0)" })
        #expect(logA.requests.count == rounds)
        #expect(logB.requests.count == rounds)
        #expect(Set(logA.requests.compactMap(\.url?.path)) == expectedA)
        #expect(Set(logB.requests.compactMap(\.url?.path)) == expectedB)
    }
}

private struct StubReply: Decodable {
    let id: String
}

private func fetchID(from client: APIClient, path: String) async throws -> String {
    let reply: StubReply = try await client.get(path)
    return reply.id
}
