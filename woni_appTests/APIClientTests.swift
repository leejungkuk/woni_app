//
//  APIClientTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// APIClient 요청 생성과 응답 봉투 해석 검증. URLProtocol 스텁으로 실제 네트워크 없이 확인한다.
@Suite(.serialized)
@MainActor
struct APIClientTests {
    @Test("POST는 JSON body와 Content-Type, Authorization 헤더를 전송한다")
    func postSendsJSONBodyAndAuthorizationHeader() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                data: Data(#"{ "success": true, "data": { "id": "created" } }"#.utf8)
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let amount = try #require(Decimal(string: "1234.56"))
        let body = TestPostBody(amount: amount, currencyCode: "USD")
        let authService = FakeAuthService(initialValue: "unit-test-token")
        try await authService.ensureIdentity()
        let client = makeClient(authProvider: authService)

        let response: TestResponse = try await client.post("/api/ledger-entries", body: body)

        let request = try #require(recorder.snapshot())
        let bodyData = try #require(request.body)
        let decodedBody = try JSONDecoder().decode(TestPostBody.self, from: bodyData)
        #expect(response.id == "created")
        #expect(request.method == "POST")
        #expect(request.contentType == "application/json")
        #expect(request.authorization == "Bearer unit-test-token")
        #expect(decodedBody == body)
        #expect(authService.refreshCount == 0)
    }

    @Test("GET은 빈 토큰이면 Authorization 헤더를 생략한다")
    func getOmitsAuthorizationHeaderWhenTokenIsEmpty() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                data: Data(#"{ "success": true, "data": { "id": "ok" } }"#.utf8)
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let authService = FakeAuthService()
        let client = makeClient(authProvider: authService)

        let response: TestResponse = try await client.get("/api/ledger-entries")

        let request = try #require(recorder.snapshot())
        #expect(response.id == "ok")
        #expect(request.method == "GET")
        #expect(request.authorization == nil)
        #expect(authService.anonymousSignInCount == 0)
        #expect(authService.refreshCount == 0)
    }

    @Test("HTTP 401은 토큰 refresh 후 동일 요청을 한 번 재시도한다")
    func unauthorizedHTTPStatusRefreshesAndRetriesOnce() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            if recorder.count == 1 {
                return try makeResponse(for: request, statusCode: 401, data: Data())
            }
            return try makeResponse(
                for: request,
                data: Data(#"{ "success": true, "data": { "id": "retried" } }"#.utf8)
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let authService = FakeAuthService(
            initialValue: "expired-token",
            refreshedValue: "refreshed-token"
        )
        try await authService.ensureIdentity()
        let client = makeClient(authProvider: authService)

        let response: TestResponse = try await client.get("/api/ledger-entries")

        let requests = recorder.snapshots()
        #expect(response.id == "retried")
        #expect(authService.refreshCount == 1)
        #expect(requests.count == 2)
        #expect(requests.first?.authorization == "Bearer expired-token")
        #expect(requests.last?.authorization == "Bearer refreshed-token")
        #expect(requests.first?.method == requests.last?.method)
        #expect(requests.first?.url == requests.last?.url)
    }

    @Test("재시도도 UNAUTHORIZED이면 refresh와 재시도를 더 수행하지 않고 오류를 전파한다")
    func repeatedUnauthorizedRetriesOnlyOnce() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": false,
                        "code": "UNAUTHORIZED",
                        "message": "로그인이 필요합니다."
                    }
                    """.utf8
                )
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let authService = FakeAuthService(
            initialValue: "expired-token",
            refreshedValue: "refreshed-token"
        )
        try await authService.ensureIdentity()
        let client = makeClient(authProvider: authService)

        do {
            let _: TestResponse = try await client.get("/api/ledger-entries")
            Issue.record("재시도의 APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "UNAUTHORIZED")
            #expect(message == "로그인이 필요합니다.")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }

        let requests = recorder.snapshots()
        #expect(authService.refreshCount == 1)
        #expect(requests.count == 2)
        #expect(requests.first?.authorization == "Bearer expired-token")
        #expect(requests.last?.authorization == "Bearer refreshed-token")
    }

    @Test("POST 401 재시도는 동일한 body와 Content-Type을 보존한다")
    func unauthorizedPOSTRetryPreservesBodyAndContentType() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            if recorder.count == 1 {
                return try makeResponse(for: request, statusCode: 401, data: Data())
            }
            return try makeResponse(
                for: request,
                data: Data(#"{ "success": true, "data": { "id": "retried" } }"#.utf8)
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let amount = try #require(Decimal(string: "1234.56"))
        let body = TestPostBody(amount: amount, currencyCode: "USD")
        let authService = FakeAuthService(
            initialValue: "expired-token",
            refreshedValue: "refreshed-token"
        )
        try await authService.ensureIdentity()
        let client = makeClient(authProvider: authService)

        let response: TestResponse = try await client.post("/api/ledger-entries", body: body)

        let requests = recorder.snapshots()
        #expect(response.id == "retried")
        #expect(requests.count == 2)
        let firstBody = try #require(requests.first?.body)
        let retriedBody = try #require(requests.last?.body)
        #expect(try JSONDecoder().decode(TestPostBody.self, from: firstBody) == body)
        #expect(try JSONDecoder().decode(TestPostBody.self, from: retriedBody) == body)
        #expect(requests.first?.contentType == "application/json")
        #expect(requests.last?.contentType == "application/json")
        #expect(requests.first?.method == "POST")
        #expect(requests.last?.method == "POST")
        #expect(requests.first?.authorization == "Bearer expired-token")
        #expect(requests.last?.authorization == "Bearer refreshed-token")
    }

    @Test("GET은 path와 query를 보존한다")
    func getPreservesPathAndQuery() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                data: Data(#"{ "success": true, "data": { "id": "ok" } }"#.utf8)
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let client = makeClient()
        let query = [URLQueryItem(name: "transactionType", value: "EXPENSE")]

        let response: TestResponse = try await client.get("/api/v1/categories", query: query)

        let request = try #require(recorder.snapshot())
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)
        #expect(response.id == "ok")
        #expect(url.path == "/api/v1/categories")
        #expect(queryItems.contains { $0.name == "transactionType" && $0.value == "EXPENSE" })
    }

    @Test("실패 봉투의 code는 APIError.server로 보존되고, refresh 훅이 없으면 재시도하지 않는다")
    func errorEnvelopeThrowsServerErrorCode() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                statusCode: 401,
                data: Data(
                    """
                    {
                        "success": false,
                        "code": "UNAUTHORIZED",
                        "message": "로그인이 필요합니다."
                    }
                    """.utf8
                )
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let client = makeClient()

        do {
            let _: TestResponse = try await client.post(
                "/api/ledger-entries",
                body: TestPostBody(amount: 1, currencyCode: "USD")
            )
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "UNAUTHORIZED")
            #expect(message == "로그인이 필요합니다.")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }

        // authProvider가 없으면 refresh 토큰을 얻지 못하므로 재시도 없이 1회 요청만 발생한다.
        #expect(recorder.count == 1)
    }

    @Test("POST 인코딩 실패와 네트워크 실패는 APIError로 매핑된다")
    func postMapsEncodingAndTransportErrors() async throws {
        let encodingClient = makeClient()

        do {
            let _: TestResponse = try await encodingClient.post(
                "/api/ledger-entries",
                body: ThrowingEncodableBody()
            )
            Issue.record("APIError.encoding이 throw되어야 합니다.")
        } catch APIError.encoding(_) {
            #expect(true)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }

        APIClientURLProtocol.handler = { _ in
            throw TransportFailure()
        }
        defer { APIClientURLProtocol.handler = nil }
        let transportClient = makeClient()

        do {
            let _: TestResponse = try await transportClient.get("/api/ledger-entries")
            Issue.record("APIError.transport가 throw되어야 합니다.")
        } catch APIError.transport(_) {
            #expect(true)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("POST 502 빈 body는 HTTP 상태 오류를 던진다")
    func postEmptyHTTPErrorBodyThrowsStatusError() async throws {
        APIClientURLProtocol.handler = { request in
            try makeResponse(for: request, statusCode: 502, data: Data())
        }
        defer { APIClientURLProtocol.handler = nil }

        let client = makeClient()

        do {
            let _: TestResponse = try await client.post(
                "/api/ledger-entries",
                body: TestPostBody(amount: 1, currencyCode: "USD")
            )
            Issue.record("APIError.httpStatus가 throw되어야 합니다.")
        } catch let APIError.httpStatus(code, _) {
            #expect(code == 502)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("POST 502 비JSON body는 디코딩 오류 대신 HTTP 상태 오류를 던진다")
    func postNonJSONHTTPErrorBodyThrowsStatusError() async throws {
        APIClientURLProtocol.handler = { request in
            try makeResponse(for: request, statusCode: 502, data: Data("Bad Gateway".utf8))
        }
        defer { APIClientURLProtocol.handler = nil }

        let client = makeClient()

        do {
            let _: TestResponse = try await client.post(
                "/api/ledger-entries",
                body: TestPostBody(amount: 1, currencyCode: "USD")
            )
            Issue.record("APIError.httpStatus가 throw되어야 합니다.")
        } catch let APIError.httpStatus(code, _) {
            #expect(code == 502)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    private func makeClient(authProvider: (any AuthProviding)? = nil) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIClientURLProtocol.self]
        return APIClient(
            session: URLSession(configuration: configuration),
            authProvider: authProvider
        )
    }
}

extension APIClientTests {
    @Test("DELETE는 data=null 성공 봉투를 오류 없이 처리한다")
    func deleteAcceptsNullDataSuccessEnvelope() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(for: request, data: voidSuccessEnvelope())
        }
        defer { APIClientURLProtocol.handler = nil }

        try await makeClient().delete(deleteTestPath)

        #expect(try #require(recorder.snapshot()).method == "DELETE")
    }

    @Test("DELETE 실패 봉투의 code는 APIError.server로 보존된다")
    func deleteFailureEnvelopeThrowsServerErrorCode() async throws {
        APIClientURLProtocol.handler = { request in
            try makeResponse(for: request, statusCode: 409, data: deleteRejectedEnvelope())
        }
        defer { APIClientURLProtocol.handler = nil }

        do {
            try await makeClient().delete(deleteTestPath)
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "DELETE_REJECTED")
            #expect(message == "삭제할 수 없습니다.")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("DELETE 비2xx 빈 body는 HTTP 상태 오류를 던진다")
    func deleteEmptyHTTPErrorBodyThrowsStatusError() async throws {
        APIClientURLProtocol.handler = { request in
            try makeResponse(for: request, statusCode: 503, data: Data())
        }
        defer { APIClientURLProtocol.handler = nil }

        do {
            try await makeClient().delete(deleteTestPath)
            Issue.record("APIError.httpStatus가 throw되어야 합니다.")
        } catch let APIError.httpStatus(code, _) {
            #expect(code == 503)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("DELETE 401 실패 봉투는 refresh 후 갱신 토큰으로 한 번 재시도한다")
    func unauthorizedDELETERefreshesAndRetriesOnce() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                statusCode: recorder.count == 1 ? 401 : 200,
                data: recorder.count == 1 ? unauthorizedEnvelope() : voidSuccessEnvelope()
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let authService = FakeAuthService(initialValue: "expired-token", refreshedValue: "refreshed-token")
        try await authService.ensureIdentity()
        try await makeClient(authProvider: authService).delete(deleteTestPath)

        let requests = recorder.snapshots()
        #expect(authService.refreshCount == 1)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.method == "DELETE" })
        #expect(requests.first?.authorization == "Bearer expired-token")
        #expect(requests.last?.authorization == "Bearer refreshed-token")
    }

    @Test("DELETE 재시도도 UNAUTHORIZED이면 총 한 번만 재시도하고 오류를 전파한다")
    func repeatedUnauthorizedDELETERetriesOnlyOnce() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(for: request, statusCode: 401, data: unauthorizedEnvelope())
        }
        defer { APIClientURLProtocol.handler = nil }

        let authService = FakeAuthService(initialValue: "expired-token", refreshedValue: "refreshed-token")
        try await authService.ensureIdentity()
        do {
            try await makeClient(authProvider: authService).delete(deleteTestPath)
            Issue.record("재시도의 APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "UNAUTHORIZED")
            #expect(message == "로그인이 필요합니다.")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }

        let requests = recorder.snapshots()
        #expect(authService.refreshCount == 1)
        #expect(requests.count == 2)
        #expect(requests.first?.authorization == "Bearer expired-token")
        #expect(requests.last?.authorization == "Bearer refreshed-token")
    }
}

extension APIClientTests {
    @Test("query PUT은 query와 JSON body, Content-Type을 함께 전송한다")
    func putWithQuerySendsQueryBodyAndContentType() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                data: Data(#"{ "success": true, "data": { "id": "saved" } }"#.utf8)
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let amount = try #require(Decimal(string: "1234.56"))
        let body = TestPostBody(amount: amount, currencyCode: "KRW")
        let response: TestResponse = try await makeClient().put(
            budgetTestPath,
            query: budgetMonthQuery,
            body: body
        )

        let request = try #require(recorder.snapshot())
        let url = try #require(request.url)
        let bodyData = try #require(request.body)
        #expect(response.id == "saved")
        #expect(request.method == "PUT")
        #expect(url.path == budgetTestPath)
        #expect(url.query == "year=2026&month=5")
        #expect(request.contentType == "application/json")
        #expect(try JSONDecoder().decode(TestPostBody.self, from: bodyData) == body)
    }

    @Test("query PUT 실패 봉투의 code는 APIError.server로 보존된다")
    func putWithQueryFailureEnvelopeThrowsServerCode() async throws {
        APIClientURLProtocol.handler = { request in
            try makeResponse(
                for: request,
                statusCode: 400,
                data: Data(
                    """
                    { "success": false, "code": "BUDGET_INVALID_AMOUNT", "message": "금액 오류", "data": null }
                    """.utf8
                )
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        do {
            let _: TestResponse = try await makeClient().put(
                budgetTestPath,
                query: budgetMonthQuery,
                body: TestPostBody(amount: 1, currencyCode: "KRW")
            )
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, _) {
            #expect(code == "BUDGET_INVALID_AMOUNT")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("query DELETE는 본문 없이 보내고 성공 봉투의 data를 돌려준다")
    func deleteWithQueryDecodesResponseData() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                data: Data(#"{ "success": true, "data": { "id": "deleted" } }"#.utf8)
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let response: TestResponse = try await makeClient().delete(budgetTestPath, query: budgetMonthQuery)

        let request = try #require(recorder.snapshot())
        let url = try #require(request.url)
        #expect(response.id == "deleted")
        #expect(request.method == "DELETE")
        #expect(url.path == budgetTestPath)
        #expect(url.query == "year=2026&month=5")
        #expect(request.body == nil)
        #expect(request.contentType == nil)
    }

    @Test("query DELETE 실패 봉투의 code는 APIError.server로 보존된다")
    func deleteWithQueryFailureEnvelopeThrowsServerCode() async throws {
        APIClientURLProtocol.handler = { request in
            try makeResponse(
                for: request,
                statusCode: 400,
                data: Data(
                    """
                    { "success": false, "code": "BUDGET_MONTH_OUT_OF_RANGE", "message": "범위 밖", "data": null }
                    """.utf8
                )
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        do {
            let _: TestResponse = try await makeClient().delete(budgetTestPath, query: budgetMonthQuery)
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, _) {
            #expect(code == "BUDGET_MONTH_OUT_OF_RANGE")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("서버 시각 조회는 기기 캐시를 거치지 않는 GET이다")
    func serverTimestampBypassesDeviceCache() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(for: request, data: assetsEnvelope(timestamp: serverTimestampValue))
        }
        defer { APIClientURLProtocol.handler = nil }

        _ = try await makeClient().serverTimestamp(assetsTestPath)

        let request = try #require(recorder.snapshot())
        #expect(request.method == "GET")
        #expect(request.url?.path == assetsTestPath)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.cacheControl == "no-cache")
    }

    @Test("서버 시각 조회는 data 모양과 상관없이 봉투의 timestamp를 그대로 돌려준다")
    func serverTimestampReturnsEnvelopeTimestamp() async throws {
        APIClientURLProtocol.handler = { request in
            try makeResponse(for: request, data: assetsEnvelope(timestamp: serverTimestampValue))
        }
        defer { APIClientURLProtocol.handler = nil }

        let timestamp = try await makeClient().serverTimestamp(assetsTestPath)

        #expect(timestamp == serverTimestampValue)
    }

    @Test("봉투에 timestamp가 없으면 서버 시각 조회는 nil을 돌려준다")
    func serverTimestampReturnsNilWhenEnvelopeHasNoTimestamp() async throws {
        APIClientURLProtocol.handler = { request in
            try makeResponse(for: request, data: assetsEnvelope(timestamp: nil))
        }
        defer { APIClientURLProtocol.handler = nil }

        let timestamp = try await makeClient().serverTimestamp(assetsTestPath)

        #expect(timestamp == nil)
    }

    @Test("서버 시각 조회의 실패 봉투는 APIError.server로 던진다")
    func serverTimestampFailureEnvelopeThrowsServerCode() async throws {
        APIClientURLProtocol.handler = { request in
            try makeResponse(
                for: request,
                statusCode: 500,
                data: Data(
                    """
                    {
                        "success": false,
                        "code": "INTERNAL_ERROR",
                        "message": "서버 오류",
                        "timestamp": "\(serverTimestampValue)"
                    }
                    """.utf8
                )
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        do {
            _ = try await makeClient().serverTimestamp(assetsTestPath)
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, _) {
            #expect(code == "INTERNAL_ERROR")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }
}

extension APIClientTests {
    @Test("query PUT은 HTTP 401이면 refresh 후 같은 query와 body로 한 번 재시도한다")
    func putWithQueryRetriesOnceAfterRefreshOn401() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                statusCode: recorder.count == 1 ? 401 : 200,
                data: recorder.count == 1 ? Data() : Data(#"{ "success": true, "data": { "id": "saved" } }"#.utf8)
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let amount = try #require(Decimal(string: "1234.56"))
        let body = TestPostBody(amount: amount, currencyCode: "KRW")
        let authService = FakeAuthService(initialValue: "expired-token", refreshedValue: "refreshed-token")
        try await authService.ensureIdentity()
        let response: TestResponse = try await makeClient(authProvider: authService).put(
            budgetTestPath,
            query: budgetMonthQuery,
            body: body
        )

        let requests = recorder.snapshots()
        #expect(response.id == "saved")
        #expect(authService.refreshCount == 1)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.method == "PUT" })
        #expect(requests.allSatisfy { $0.url?.query == "year=2026&month=5" })
        let firstBody = try #require(requests.first?.body)
        let retriedBody = try #require(requests.last?.body)
        #expect(try JSONDecoder().decode(TestPostBody.self, from: firstBody) == body)
        #expect(try JSONDecoder().decode(TestPostBody.self, from: retriedBody) == body)
        #expect(requests.first?.authorization == "Bearer expired-token")
        #expect(requests.last?.authorization == "Bearer refreshed-token")
    }

    @Test("query DELETE는 HTTP 401이면 refresh 후 같은 query로 본문 없이 한 번 재시도한다")
    func deleteWithQueryRetriesOnceAfterRefreshOn401() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                statusCode: recorder.count == 1 ? 401 : 200,
                data: recorder.count == 1 ? Data() : Data(#"{ "success": true, "data": { "id": "deleted" } }"#.utf8)
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let authService = FakeAuthService(initialValue: "expired-token", refreshedValue: "refreshed-token")
        try await authService.ensureIdentity()
        let response: TestResponse = try await makeClient(authProvider: authService).delete(
            budgetTestPath,
            query: budgetMonthQuery
        )

        let requests = recorder.snapshots()
        #expect(response.id == "deleted")
        #expect(authService.refreshCount == 1)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.method == "DELETE" })
        #expect(requests.allSatisfy { $0.url?.query == "year=2026&month=5" })
        #expect(requests.allSatisfy { $0.body == nil })
        #expect(requests.first?.authorization == "Bearer expired-token")
        #expect(requests.last?.authorization == "Bearer refreshed-token")
    }

    @Test("서버 시각 조회는 HTTP 401이면 refresh 후 캐시 우회를 유지한 채 한 번 재시도한다")
    func serverTimestampRetriesOnceAfterRefreshOn401() async throws {
        let recorder = RequestRecorder()
        APIClientURLProtocol.handler = { request in
            recorder.record(request)
            return try makeResponse(
                for: request,
                statusCode: recorder.count == 1 ? 401 : 200,
                data: recorder.count == 1 ? Data() : assetsEnvelope(timestamp: serverTimestampValue)
            )
        }
        defer { APIClientURLProtocol.handler = nil }

        let authService = FakeAuthService(initialValue: "expired-token", refreshedValue: "refreshed-token")
        try await authService.ensureIdentity()
        let timestamp = try await makeClient(authProvider: authService).serverTimestamp(assetsTestPath)

        let requests = recorder.snapshots()
        #expect(timestamp == serverTimestampValue)
        #expect(authService.refreshCount == 1)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.method == "GET" })
        #expect(requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        #expect(requests.allSatisfy { $0.cacheControl == "no-cache" })
        #expect(requests.first?.authorization == "Bearer expired-token")
        #expect(requests.last?.authorization == "Bearer refreshed-token")
    }
}

private struct TestPostBody: Codable, Equatable {
    let amount: Decimal
    let currencyCode: String
}

private struct TestResponse: Decodable {
    let id: String
}

private struct ThrowingEncodableBody: Encodable {
    func encode(to _: Encoder) throws {
        throw EncodingFailure()
    }

    private struct EncodingFailure: Error {}
}

private struct TransportFailure: Error {}

private struct RecordedRequest {
    let url: URL?
    let method: String?
    let contentType: String?
    let authorization: String?
    let body: Data?
    let cachePolicy: URLRequest.CachePolicy
    let cacheControl: String?
}

private final class RequestRecorder {
    private let lock = NSLock()
    private var requests: [RecordedRequest] = []

    func record(_ request: URLRequest) {
        let recordedRequest = RecordedRequest(
            url: request.url,
            method: request.httpMethod,
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: requestBodyData(from: request),
            cachePolicy: request.cachePolicy,
            cacheControl: request.value(forHTTPHeaderField: "Cache-Control")
        )

        lock.lock()
        requests.append(recordedRequest)
        lock.unlock()
    }

    func snapshot() -> RecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.last
    }

    func snapshots() -> [RecordedRequest] {
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

private final class APIClientURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: APIClientURLProtocolError.missingHandler)
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

private enum APIClientURLProtocolError: Error {
    case missingHandler
    case invalidResponse
}

private func makeResponse(
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
        throw APIClientURLProtocolError.invalidResponse
    }
    return (response, data)
}

private func requestBodyData(from request: URLRequest) -> Data? {
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

private let deleteTestPath = "/api/v1/ledgers/sync/test-id"

private func voidSuccessEnvelope() -> Data {
    Data(#"{ "success": true, "data": null }"#.utf8)
}

private func deleteRejectedEnvelope() -> Data {
    Data(#"{ "success": false, "code": "DELETE_REJECTED", "message": "삭제할 수 없습니다.", "data": null }"#.utf8)
}

private func unauthorizedEnvelope() -> Data {
    Data(#"{ "success": false, "code": "UNAUTHORIZED", "message": "로그인이 필요합니다.", "data": null }"#.utf8)
}

private let budgetTestPath = "/api/v1/budgets"
private let budgetMonthQuery = [URLQueryItem(name: "year", value: "2026"), URLQueryItem(name: "month", value: "5")]
private let assetsTestPath = "/api/v1/assets"
private let serverTimestampValue = "2026-09-30T21:45:00.123456"

/// 자산 목록 모양(배열 data) 성공 봉투. `timestamp` 가 nil 이면 키를 뺀다.
private func assetsEnvelope(timestamp: String?) -> Data {
    let timestampField = timestamp.map { #", "timestamp": "\#($0)""# } ?? ""
    return Data(#"{ "success": true, "data": [{ "id": 1, "name": "카드" }]\#(timestampField) }"#.utf8)
}
