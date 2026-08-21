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
}

extension CustomCategoryServiceTests {
    @Test("update는 id 경로로 trim한 name만 PUT하고 CategoryDTO를 디코딩한다")
    func updateTrimsNameOmitsIconAndDecodesCategory() async throws {
        let recorder = CustomCategoryRequestRecorder()
        CustomCategoryURLProtocol.handler = { request in
            recorder.record(request)
            return try makeCustomCategoryResponse(
                for: request,
                data: customCategorySuccessEnvelope(name: "🍜 새 이름")
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        let category = try await makeCustomCategoryService()
            .updateCustomCategory(id: 102, name: "  🍜 새 이름\n")

        let request = try #require(recorder.snapshot())
        let body = try #require(request.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(request.method == "PUT")
        #expect(request.url?.path == "/api/v1/categories/custom/102")
        #expect(request.contentType == "application/json")
        #expect(object["name"] as? String == "🍜 새 이름")
        #expect(Set(object.keys) == Set(["name"]))
        #expect(category.id == 102)
        #expect(category.displayNameKo == "🍜 새 이름")
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

    @Test("update 404는 CATEGORY_NOT_FOUND code를 보존한다")
    func updatePreservesCategoryNotFoundCode() async throws {
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
            _ = try await makeCustomCategoryService()
                .updateCustomCategory(id: 999, name: "수정")
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "CATEGORY_NOT_FOUND")
            #expect(message == "카테고리를 찾을 수 없습니다.")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("update의 HTTP 200 실패 봉투도 APIError.server로 전파한다")
    func updatePropagatesFailureEnvelope() async throws {
        CustomCategoryURLProtocol.handler = { request in
            try makeCustomCategoryResponse(
                for: request,
                data: Data(
                    #"{"success":false,"code":"CUSTOM_CATEGORY_FAILURE","message":"수정하지 못했습니다."}"#.utf8
                )
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        do {
            _ = try await makeCustomCategoryService()
                .updateCustomCategory(id: 102, name: "수정")
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "CUSTOM_CATEGORY_FAILURE")
            #expect(message == "수정하지 못했습니다.")
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

    @Test("update는 빈 이름과 공백뿐인 이름을 요청 전에 거부한다", arguments: ["", "   \n\t"])
    func updateRejectsEmptyTrimmedName(name: String) async {
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
            _ = try await makeCustomCategoryService().updateCustomCategory(id: 102, name: name)
            Issue.record("빈 이름은 거부되어야 합니다.")
        } catch CustomCategoryServiceError.invalidName {
            #expect(recorder.snapshot() == nil)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("update는 UTF-16 code unit 51개 이름을 요청 전에 거부한다")
    func updateRejectsFiftyOneUTF16CodeUnits() async {
        let name = String(repeating: "a", count: 51)
        #expect(name.utf16.count == 51)

        await #expect(throws: CustomCategoryServiceError.invalidName) {
            _ = try await makeCustomCategoryService().updateCustomCategory(id: 102, name: name)
        }
    }

    @Test("update는 ZWJ 이모지를 포함한 UTF-16 50 경계를 정확히 검증한다")
    func updateValidatesZWJEmojiAtFiftyUTF16CodeUnits() async throws {
        let accepted = String(repeating: "👨‍👩‍👧‍👦", count: 4) + "abcdef"
        let rejected = accepted + "g"
        #expect(accepted.count == 10)
        #expect(accepted.utf16.count == 50)
        #expect(rejected.count == 11)
        #expect(rejected.utf16.count == 51)
        let recorder = CustomCategoryRequestRecorder()
        CustomCategoryURLProtocol.handler = { request in
            recorder.record(request)
            return try makeCustomCategoryResponse(
                for: request,
                data: customCategorySuccessEnvelope(name: accepted)
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        _ = try await makeCustomCategoryService().updateCustomCategory(id: 102, name: " \(accepted) ")

        let body = try #require(recorder.snapshot()?.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["name"] as? String == accepted)
        await #expect(throws: CustomCategoryServiceError.invalidName) {
            _ = try await makeCustomCategoryService().updateCustomCategory(id: 102, name: rejected)
        }
    }

    @Test("reorder는 전달 순서 그대로 orderedIds를 PUT하고 정렬된 목록을 디코딩한다")
    func reorderPutsOrderedIDsAndDecodesSortedCategories() async throws {
        let recorder = CustomCategoryRequestRecorder()
        CustomCategoryURLProtocol.handler = { request in
            recorder.record(request)
            return try makeCustomCategoryResponse(
                for: request,
                data: customCategoryListEnvelope([(103, 1001), (101, 1002), (102, 1003)])
            )
        }
        defer { CustomCategoryURLProtocol.handler = nil }

        let categories = try await makeCustomCategoryService()
            .reorderCustomCategories(orderedIDs: [103, 101, 102], transactionType: "EXPENSE")

        let request = try #require(recorder.snapshot())
        let body = try #require(request.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(request.method == "PUT")
        #expect(request.url?.path == "/api/v1/categories/custom/order")
        #expect(request.contentType == "application/json")
        #expect(object["orderedIds"] as? [Int] == [103, 101, 102])
        #expect(object["transactionType"] as? String == "EXPENSE")
        #expect(Set(object.keys) == Set(["orderedIds", "transactionType"]))
        #expect(categories.map(\.id) == [103, 101, 102])
        #expect(categories.map(\.sortOrder) == [1001, 1002, 1003])
    }

    @Test("reorder 404는 CATEGORY_NOT_FOUND code를 보존한다")
    func reorderPreservesCategoryNotFoundCode() async throws {
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
            _ = try await makeCustomCategoryService()
                .reorderCustomCategories(orderedIDs: [999], transactionType: "EXPENSE")
            Issue.record("APIError.server가 throw되어야 합니다.")
        } catch let APIError.server(code, message) {
            #expect(code == "CATEGORY_NOT_FOUND")
            #expect(message == "카테고리를 찾을 수 없습니다.")
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

/// 재정렬 응답처럼 그 타입의 전체 목록이 내려오는 봉투. id·sortOrder는 호출부가 명시한다.
private func customCategoryListEnvelope(_ categories: [(id: Int, sortOrder: Int)]) -> Data {
    let items = categories.map { category in
        """
        {
            "id": \(category.id),
            "code": "CUSTOM",
            "displayNameKo": "카테고리\(category.id)",
            "displayNameEn": "Category\(category.id)",
            "icon": null,
            "sortOrder": \(category.sortOrder)
        }
        """
    }
    return Data(
        """
        { "success": true, "data": [\(items.joined(separator: ","))] }
        """.utf8
    )
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
