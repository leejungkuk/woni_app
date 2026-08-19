//
//  CustomCategoryServiceTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct CustomCategoryServiceTests {
    @Test("fetch는 인증과 transactionType query를 사용해 목록을 디코딩한다")
    func fetchUsesAuthenticatedQueryAndDecodesCategories() async throws {
        let recorder = CustomCategoryRequestRecorder()
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        CustomCategoryURLProtocol.handler = { request in
            recorder.record(request)
            return try makeCustomCategoryResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": true,
                        "data": [{
                            "id": 101,
                            "code": "CUSTOM",
                            "displayNameKo": "🏋️ 헬스장",
                            "displayNameEn": "🏋️ 헬스장",
                            "icon": null,
                            "sortOrder": 1000
                        }]
                    }
                    """.utf8
                )
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        let categories = try await makeCustomCategoryService(authProvider: auth)
            .fetchCustomCategories(transactionType: "EXPENSE")

        let request = try #require(recorder.snapshot())
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(request.method == "GET")
        #expect(request.authorization == "Bearer PLACEHOLDER_VALUE")
        #expect(url.path == "/api/v1/categories/custom")
        #expect(components.queryItems == [URLQueryItem(name: "transactionType", value: "EXPENSE")])
        #expect(categories.count == 1)
        #expect(categories.first?.id == 101)
        #expect(categories.first?.code == "CUSTOM")
        #expect(categories.first?.displayNameKo == "🏋️ 헬스장")
        #expect(categories.first?.displayNameEn == "🏋️ 헬스장")
        #expect(categories.first?.icon == nil)
        #expect(categories.first?.sortOrder == 1000)
    }

    @Test("create는 trim한 이름과 transactionType만 전송하고 CategoryDTO를 디코딩한다")
    func createTrimsNameOmitsIconAndDecodesCategory() async throws {
        let recorder = CustomCategoryRequestRecorder()
        CustomCategoryURLProtocol.handler = { request in
            recorder.record(request)
            return try makeCustomCategoryResponse(
                for: request,
                data: customCategorySuccessEnvelope(name: "🍜 야식")
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        let category = try await makeCustomCategoryService()
            .createCustomCategory(name: "  🍜 야식\n", transactionType: "EXPENSE")

        let request = try #require(recorder.snapshot())
        let body = try #require(request.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(request.method == "POST")
        #expect(request.url?.path == "/api/v1/categories/custom")
        #expect(request.contentType == "application/json")
        #expect(object["name"] as? String == "🍜 야식")
        #expect(object["transactionType"] as? String == "EXPENSE")
        #expect(object.keys.contains("icon") == false)
        #expect(category.id == 102)
        #expect(category.displayNameKo == "🍜 야식")
        #expect(category.icon == nil)
    }

    @Test("delete는 id 경로로 DELETE하고 성공 봉투를 완료 처리한다")
    func deleteUsesCategoryIDPath() async throws {
        let recorder = CustomCategoryRequestRecorder()
        CustomCategoryURLProtocol.handler = { request in
            recorder.record(request)
            return try makeCustomCategoryResponse(
                for: request,
                data: Data(#"{ "success": true, "data": null }"#.utf8)
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        try await makeCustomCategoryService().deleteCustomCategory(id: 102)

        let request = try #require(recorder.snapshot())
        #expect(request.method == "DELETE")
        #expect(request.url?.path == "/api/v1/categories/custom/102")
    }

    @Test("create 403은 CUSTOM_CATEGORY_LIMIT_EXCEEDED code를 보존한다")
    func createPreservesLimitExceededCode() async throws {
        CustomCategoryURLProtocol.handler = { request in
            try makeCustomCategoryResponse(
                for: request,
                statusCode: 403,
                data: Data(
                    #"{"success":false,"code":"CUSTOM_CATEGORY_LIMIT_EXCEEDED","message":"한도를 초과했습니다."}"#.utf8
                )
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        do {
            _ = try await makeCustomCategoryService()
                .createCustomCategory(name: "야식", transactionType: "EXPENSE")
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "CUSTOM_CATEGORY_LIMIT_EXCEEDED")
            #expect(message == "한도를 초과했습니다.")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("delete 404는 CATEGORY_NOT_FOUND code를 보존한다")
    func deletePreservesCategoryNotFoundCode() async throws {
        CustomCategoryURLProtocol.handler = { request in
            try makeCustomCategoryResponse(
                for: request,
                statusCode: 404,
                data: Data(
                    #"{"success":false,"code":"CATEGORY_NOT_FOUND","message":"카테고리를 찾을 수 없습니다."}"#.utf8
                )
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        do {
            try await makeCustomCategoryService().deleteCustomCategory(id: 999)
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "CATEGORY_NOT_FOUND")
            #expect(message == "카테고리를 찾을 수 없습니다.")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("HTTP 200 실패 봉투도 APIError.server로 전파한다")
    func fetchPropagatesFailureEnvelope() async throws {
        CustomCategoryURLProtocol.handler = { request in
            try makeCustomCategoryResponse(
                for: request,
                data: Data(
                    #"{"success":false,"code":"CUSTOM_CATEGORY_FAILURE","message":"불러오지 못했습니다."}"#.utf8
                )
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        do {
            _ = try await makeCustomCategoryService()
                .fetchCustomCategories(transactionType: "INCOME")
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "CUSTOM_CATEGORY_FAILURE")
            #expect(message == "불러오지 못했습니다.")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("빈 이름과 공백뿐인 이름은 요청 전에 거부한다", arguments: ["", "   \n\t"])
    func createRejectsEmptyTrimmedName(name: String) async {
        let recorder = CustomCategoryRequestRecorder()
        CustomCategoryURLProtocol.handler = { request in
            recorder.record(request)
            return try makeCustomCategoryResponse(
                for: request,
                data: customCategorySuccessEnvelope(name: "unexpected")
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        do {
            _ = try await makeCustomCategoryService()
                .createCustomCategory(name: name, transactionType: "EXPENSE")
            Issue.record("빈 이름은 거부되어야 합니다.")
        } catch CustomCategoryServiceError.invalidName {
            #expect(recorder.snapshot() == nil)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("UTF-16 code unit 51개 이름은 요청 전에 거부한다")
    func createRejectsFiftyOneUTF16CodeUnits() async {
        let name = String(repeating: "a", count: 51)
        #expect(name.utf16.count == 51)

        do {
            _ = try await makeCustomCategoryService()
                .createCustomCategory(name: name, transactionType: "EXPENSE")
            Issue.record("UTF-16 51개 이름은 거부되어야 합니다.")
        } catch CustomCategoryServiceError.invalidName {
            #expect(true)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("ZWJ 이모지를 포함해 UTF-16 50개인 이름은 trim 후 전송한다")
    func createAcceptsFiftyUTF16CodeUnitsWithZWJEmoji() async throws {
        let name = String(repeating: "👨‍👩‍👧‍👦", count: 4) + "abcdef"
        #expect(name.count == 10)
        #expect(name.utf16.count == 50)
        let recorder = CustomCategoryRequestRecorder()
        CustomCategoryURLProtocol.handler = { request in
            recorder.record(request)
            return try makeCustomCategoryResponse(
                for: request,
                data: customCategorySuccessEnvelope(name: name)
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        _ = try await makeCustomCategoryService()
            .createCustomCategory(name: " \(name) ", transactionType: "INCOME")

        let body = try #require(recorder.snapshot()?.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["name"] as? String == name)
    }

    @Test("ZWJ 이모지를 포함해 UTF-16 50개를 넘는 이름은 요청 전에 거부한다")
    func createRejectsOverFiftyUTF16CodeUnitsWithZWJEmoji() async {
        let name = String(repeating: "👨‍👩‍👧‍👦", count: 4) + "abcdefg"
        #expect(name.count == 11)
        #expect(name.utf16.count == 51)

        do {
            _ = try await makeCustomCategoryService()
                .createCustomCategory(name: name, transactionType: "INCOME")
            Issue.record("UTF-16 50개 초과 이름은 거부되어야 합니다.")
        } catch CustomCategoryServiceError.invalidName {
            #expect(true)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }
}

private struct CustomCategoryRecordedRequest {
    let url: URL?
    let method: String?
    let contentType: String?
    let authorization: String?
    let body: Data?
}

private final class CustomCategoryRequestRecorder {
    private let lock = NSLock()
    private var request: CustomCategoryRecordedRequest?

    func record(_ request: URLRequest) {
        let recordedRequest = CustomCategoryRecordedRequest(
            url: request.url,
            method: request.httpMethod,
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: customCategoryRequestBodyData(from: request)
        )

        lock.lock()
        self.request = recordedRequest
        lock.unlock()
    }

    func snapshot() -> CustomCategoryRecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private final class CustomCategoryURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: CustomCategoryURLProtocolError.missingHandler)
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

private enum CustomCategoryURLProtocolError: Error {
    case missingHandler
    case invalidResponse
}

private func makeCustomCategoryService(
    authProvider: (any AuthProviding)? = nil
) -> CustomCategoryService {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CustomCategoryURLProtocol.self]
    return CustomCategoryService(
        client: APIClient(
            session: URLSession(configuration: configuration),
            authProvider: authProvider
        )
    )
}

private func makeCustomCategoryResponse(
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
        throw CustomCategoryURLProtocolError.invalidResponse
    }
    return (response, data)
}

private func customCategoryRequestBodyData(from request: URLRequest) -> Data? {
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

private func customCategorySuccessEnvelope(name: String) -> Data {
    let escapedName = name
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return Data(
        """
        {
            "success": true,
            "data": {
                "id": 102,
                "code": "CUSTOM",
                "displayNameKo": "\(escapedName)",
                "displayNameEn": "\(escapedName)",
                "icon": null,
                "sortOrder": 1000
            }
        }
        """.utf8
    )
}
