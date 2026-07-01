//
//  AddExpenseTestSupport.swift
//  woni_appTests
//
//  AddExpenseViewModelTests 전용 URLProtocol 스텁·요청 레코더·페이로드 픽스처.
//

import Foundation
import Testing
@testable import woni_app

struct AddExpenseCatalogRecordedRequest {
    let path: String
    let transactionType: String?
    let method: String?
    let body: Data?
}

final class AddExpenseCatalogRequestRecorder {
    private let lock = NSLock()
    private var requests: [AddExpenseCatalogRecordedRequest] = []

    func record(_ request: URLRequest) {
        guard let url = request.url else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let transactionType = components?.queryItems?.first { $0.name == "transactionType" }?.value
        let recordedRequest = AddExpenseCatalogRecordedRequest(
            path: url.path,
            transactionType: transactionType,
            method: request.httpMethod,
            body: addExpenseRequestBodyData(from: request)
        )

        lock.lock()
        requests.append(recordedRequest)
        lock.unlock()
    }

    func count(path: String, transactionType: String? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count {
            $0.path == path && (transactionType == nil || $0.transactionType == transactionType)
        }
    }

    func firstRequest(path: String) -> AddExpenseCatalogRecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.first { $0.path == path }
    }
}

final class AddExpenseCatalogURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: AddExpenseCatalogURLProtocolError.missingHandler)
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

enum AddExpenseCatalogURLProtocolError: Error {
    case invalidResponse
    case missingHandler
    case unexpectedRequest
    case timeout
}

func makeAddExpenseCatalogClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AddExpenseCatalogURLProtocol.self]
    return APIClient(session: URLSession(configuration: configuration), token: { nil })
}

struct AddExpenseLedgerRequestBody: Decodable {
    let amount: Decimal
    let currencyCode: String
    let categoryId: Int
    let assetId: Int
    let transactionDate: String
    let memo: String?
}

func addExpenseCatalogResponse(
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
        throw AddExpenseCatalogURLProtocolError.invalidResponse
    }
    return (response, data)
}

func addExpenseRequestBodyData(from request: URLRequest) -> Data? {
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

func catalogPayload(for request: URLRequest) throws -> Data {
    guard let url = request.url else {
        throw AddExpenseCatalogURLProtocolError.unexpectedRequest
    }

    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

    switch url.path {
    case "/api/v1/categories":
        return try categoryPayload(
            transactionType: components?.queryItems?.first(where: { $0.name == "transactionType" })?.value
        )
    case "/api/v1/assets":
        return assetPayload()
    default:
        throw AddExpenseCatalogURLProtocolError.unexpectedRequest
    }
}

func categoryPayload(transactionType: String?) throws -> Data {
    switch transactionType {
    case "EXPENSE":
        return expenseCategoryPayload()
    case "INCOME":
        return incomeCategoryPayload()
    default:
        throw AddExpenseCatalogURLProtocolError.unexpectedRequest
    }
}

func expenseCategoryPayload() -> Data {
    Data(
        """
        {
            "success": true,
            "data": [
                { "id": 11, "code": "TRAVEL", "displayNameKo": "여행",
                  "displayNameEn": "Travel", "icon": "✈️", "sortOrder": 2 },
                { "id": 10, "code": "FOOD", "displayNameKo": "식비",
                  "displayNameEn": "Food", "icon": "🍽️", "sortOrder": 1 }
            ]
        }
        """.utf8
    )
}

func incomeCategoryPayload() -> Data {
    Data(
        """
        {
            "success": true,
            "data": [
                { "id": 31, "code": "SIDE_INCOME", "displayNameKo": "부수입",
                  "displayNameEn": "Side Income", "icon": "💻", "sortOrder": 2 },
                { "id": 30, "code": "SALARY", "displayNameKo": "급여",
                  "displayNameEn": "Salary", "icon": "💼", "sortOrder": 1 }
            ]
        }
        """.utf8
    )
}

func assetPayload() -> Data {
    Data(
        """
        {
            "success": true,
            "data": [
                { "id": 21, "code": "CARD", "displayNameKo": "카드",
                  "displayNameEn": "Card", "sortOrder": 2 },
                { "id": 20, "code": "CASH", "displayNameKo": "현금",
                  "displayNameEn": "Cash", "sortOrder": 1 }
            ]
        }
        """.utf8
    )
}

func failureEnvelopePayload() -> Data {
    Data(
        """
        {
            "success": false,
            "code": "INTERNAL_ERROR",
            "message": "boom"
        }
        """.utf8
    )
}

func ledgerSuccessPayload(transactionType: String = "EXPENSE") -> Data {
    Data(
        """
        {
            "success": true,
            "data": {
                "id": 501, "transactionType": "\(transactionType)", "currencyCode": "KRW",
                "originalAmount": 9000, "krwAmount": 9000, "appliedRate": 1,
                "rateBaseDate": null, "transactionDate": "2026-06-24", "memo": null,
                "category": {
                    "id": 10, "code": "FOOD", "displayNameKo": "식비",
                    "displayNameEn": "Food", "icon": "fork.knife", "sortOrder": 1
                },
                "asset": {
                    "id": 20, "code": "CASH", "displayNameKo": "현금",
                    "displayNameEn": "Cash", "sortOrder": 1
                }
            }
        }
        """.utf8
    )
}

func makeSeoulDate(year: Int, month: Int, day: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))

    let components = DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day
    )
    return try #require(calendar.date(from: components))
}

func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: () -> Bool
) async throws {
    let stepNanoseconds: UInt64 = 10_000_000
    var elapsed: UInt64 = 0

    while elapsed < timeoutNanoseconds {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: stepNanoseconds)
        elapsed += stepNanoseconds
    }

    throw AddExpenseCatalogURLProtocolError.timeout
}
