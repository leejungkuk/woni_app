//
//  LedgerServiceTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// Ledger 생성 DTO와 Service 요청/응답 계약을 URLProtocol 스텁으로 검증한다.
@Suite(.serialized)
@MainActor
struct LedgerServiceTests {
    @Test("create는 POST /api/v1/ledgers에 Decimal body를 전송하고 응답 전 필드를 디코딩한다")
    func createSendsPostBodyAndDecodesResponse() async throws {
        let recorder = LedgerRequestRecorder()
        LedgerURLProtocol.handler = { request in
            recorder.record(request)
            return try makeLedgerResponse(
                for: request,
                data: fullSuccessEnvelope()
            )
        }
        defer { LedgerURLProtocol.handler = nil }

        let amount = try #require(Decimal(string: "1234.56"))
        let service = LedgerService(client: makeLedgerClient())
        let request = CreateLedgerEntryRequest(
            amount: amount,
            currencyCode: SelectableCurrency.usd.rawValue,
            categoryId: 10,
            assetId: 20,
            transactionDate: "2026-06-24",
            memo: "라떼"
        )

        let response = try await service.create(request)

        let recordedRequest = try #require(recorder.snapshot())
        let url = try #require(recordedRequest.url)
        let bodyData = try #require(recordedRequest.body)
        let decodedBody = try JSONDecoder().decode(LedgerRequestBody.self, from: bodyData)

        #expect(recordedRequest.method == "POST")
        #expect(recordedRequest.contentType == "application/json")
        #expect(url.path == "/api/v1/ledgers")
        #expect(decodedBody.amount == amount)
        #expect(decodedBody.currencyCode == "USD")
        #expect(decodedBody.categoryId == 10)
        #expect(decodedBody.assetId == 20)
        #expect(decodedBody.transactionDate == "2026-06-24")
        #expect(decodedBody.memo == "라떼")

        #expect(response.id == 501)
        #expect(response.transactionType == "EXPENSE")
        #expect(response.currencyCode == "USD")
        #expect(response.originalAmount == Decimal(string: "1234.56"))
        #expect(response.krwAmount == Decimal(string: "1712962.32"))
        #expect(response.appliedRate == Decimal(string: "1387.50"))
        #expect(response.rateBaseDate == "2026-06-23")
        #expect(response.transactionDate == "2026-06-24")
        #expect(response.memo == "라떼")
        #expect(response.category.id == 10)
        #expect(response.category.code == "FOOD")
        #expect(response.category.displayNameKo == "식비")
        #expect(response.category.displayNameEn == "Food")
        #expect(response.category.icon == "fork.knife")
        #expect(response.category.sortOrder == 1)
        #expect(response.asset.id == 20)
        #expect(response.asset.code == "CASH")
        #expect(response.asset.displayNameKo == "현금")
        #expect(response.asset.displayNameEn == "Cash")
        #expect(response.asset.sortOrder == 1)
    }

    @Test("memo가 nil이면 요청 JSON에서 memo 키를 생략하고 Optional 응답 null을 디코딩한다")
    func createOmitsNilMemoAndDecodesOptionalNulls() async throws {
        let recorder = LedgerRequestRecorder()
        LedgerURLProtocol.handler = { request in
            recorder.record(request)
            return try makeLedgerResponse(
                for: request,
                data: successEnvelopeWithOptionalNulls()
            )
        }
        defer { LedgerURLProtocol.handler = nil }

        let amount = try #require(Decimal(string: "5000"))
        let service = LedgerService(client: makeLedgerClient())
        let request = CreateLedgerEntryRequest(
            amount: amount,
            currencyCode: SelectableCurrency.krw.rawValue,
            categoryId: 11,
            assetId: 21,
            transactionDate: "2026-06-24",
            memo: nil
        )

        let response = try await service.create(request)

        let recordedRequest = try #require(recorder.snapshot())
        let bodyData = try #require(recordedRequest.body)
        let object = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let decodedBody = try JSONDecoder().decode(LedgerRequestBody.self, from: bodyData)

        #expect(object.keys.contains("memo") == false)
        #expect(decodedBody.amount == amount)
        #expect(decodedBody.currencyCode == "KRW")
        #expect(decodedBody.transactionDate == "2026-06-24")
        #expect(decodedBody.memo == nil)
        #expect(response.rateBaseDate == nil)
        #expect(response.memo == nil)
    }

    @Test("실패 봉투의 CATEGORY_NOT_FOUND code는 APIError.server로 보존된다")
    func createThrowsServerErrorCodeFromFailureEnvelope() async throws {
        LedgerURLProtocol.handler = { request in
            try makeLedgerResponse(
                for: request,
                statusCode: 404,
                data: Data(
                    """
                    {
                        "success": false,
                        "code": "CATEGORY_NOT_FOUND",
                        "message": "카테고리를 찾을 수 없습니다.",
                        "data": null
                    }
                    """.utf8
                )
            )
        }
        defer { LedgerURLProtocol.handler = nil }

        let service = LedgerService(client: makeLedgerClient())

        do {
            _ = try await service.create(makeRequest())
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "CATEGORY_NOT_FOUND")
            #expect(message == "카테고리를 찾을 수 없습니다.")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("성공 봉투 data=null은 emptyResponse로 방어한다")
    func createThrowsEmptyResponseWhenSuccessDataIsNull() async throws {
        LedgerURLProtocol.handler = { request in
            try makeLedgerResponse(
                for: request,
                data: Data(#"{ "success": true, "data": null }"#.utf8)
            )
        }
        defer { LedgerURLProtocol.handler = nil }

        let service = LedgerService(client: makeLedgerClient())

        do {
            _ = try await service.create(makeRequest())
            Issue.record("APIError.emptyResponse가 throw되어야 합니다.")
        } catch APIError.emptyResponse {
            #expect(true)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("빈 body는 emptyResponse로 방어한다")
    func createThrowsEmptyResponseWhenBodyIsEmpty() async throws {
        LedgerURLProtocol.handler = { request in
            try makeLedgerResponse(for: request, data: Data())
        }
        defer { LedgerURLProtocol.handler = nil }

        let service = LedgerService(client: makeLedgerClient())

        do {
            _ = try await service.create(makeRequest())
            Issue.record("APIError.emptyResponse가 throw되어야 합니다.")
        } catch APIError.emptyResponse {
            #expect(true)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    private func makeRequest() throws -> CreateLedgerEntryRequest {
        CreateLedgerEntryRequest(
            amount: try #require(Decimal(string: "1000")),
            currencyCode: SelectableCurrency.krw.rawValue,
            categoryId: 10,
            assetId: 20,
            transactionDate: "2026-06-24",
            memo: nil
        )
    }
}

private struct LedgerRequestBody: Decodable {
    let amount: Decimal
    let currencyCode: String
    let categoryId: Int
    let assetId: Int
    let transactionDate: String
    let memo: String?
}

private struct LedgerRecordedRequest {
    let url: URL?
    let method: String?
    let contentType: String?
    let body: Data?
}

private final class LedgerRequestRecorder {
    private let lock = NSLock()
    private var request: LedgerRecordedRequest?

    func record(_ request: URLRequest) {
        let recordedRequest = LedgerRecordedRequest(
            url: request.url,
            method: request.httpMethod,
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            body: ledgerRequestBodyData(from: request)
        )

        lock.lock()
        self.request = recordedRequest
        lock.unlock()
    }

    func snapshot() -> LedgerRecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private final class LedgerURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: LedgerURLProtocolError.missingHandler)
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

private enum LedgerURLProtocolError: Error {
    case missingHandler
    case invalidResponse
}

private func makeLedgerClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LedgerURLProtocol.self]
    return APIClient(session: URLSession(configuration: configuration), token: { nil })
}

private func makeLedgerResponse(
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
        throw LedgerURLProtocolError.invalidResponse
    }
    return (response, data)
}

private func ledgerRequestBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while true {
        let bytesRead = stream.read(&buffer, maxLength: buffer.count)
        guard bytesRead > 0 else {
            break
        }
        data.append(contentsOf: buffer.prefix(bytesRead))
    }
    return data
}

private func fullSuccessEnvelope() -> Data {
    Data(
        """
        {
            "success": true,
            "data": {
                "id": 501,
                "transactionType": "EXPENSE",
                "currencyCode": "USD",
                "originalAmount": 1234.56,
                "krwAmount": 1712962.32,
                "appliedRate": 1387.50,
                "rateBaseDate": "2026-06-23",
                "transactionDate": "2026-06-24",
                "memo": "라떼",
                "category": {
                    "id": 10,
                    "code": "FOOD",
                    "displayNameKo": "식비",
                    "displayNameEn": "Food",
                    "icon": "fork.knife",
                    "sortOrder": 1
                },
                "asset": {
                    "id": 20,
                    "code": "CASH",
                    "displayNameKo": "현금",
                    "displayNameEn": "Cash",
                    "sortOrder": 1
                }
            }
        }
        """.utf8
    )
}

private func successEnvelopeWithOptionalNulls() -> Data {
    Data(
        """
        {
            "success": true,
            "data": {
                "id": 502,
                "transactionType": "EXPENSE",
                "currencyCode": "KRW",
                "originalAmount": 5000,
                "krwAmount": 5000,
                "appliedRate": 1,
                "rateBaseDate": null,
                "transactionDate": "2026-06-24",
                "memo": null,
                "category": {
                    "id": 11,
                    "code": "TRANSPORT",
                    "displayNameKo": "교통",
                    "displayNameEn": "Transport",
                    "icon": null,
                    "sortOrder": 2
                },
                "asset": {
                    "id": 21,
                    "code": "BANK",
                    "displayNameKo": "은행",
                    "displayNameEn": "Bank",
                    "sortOrder": 2
                }
            }
        }
        """.utf8
    )
}
