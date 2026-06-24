//
//  AddExpenseViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct AddExpenseViewModelTests {
    @Test("load는 현재 탭 카테고리와 자산을 로드하고 sortOrder 첫 항목을 기본 선택한다")
    func loadFetchesCatalogAndSelectsFirstItems() async {
        let recorder = AddExpenseCatalogRequestRecorder()
        AddExpenseCatalogURLProtocol.handler = { request in
            recorder.record(request)
            return try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let viewModel = AddExpenseViewModel(catalogService: CatalogService(client: makeAddExpenseCatalogClient()))

        await viewModel.load()

        #expect(viewModel.catalogError == nil)
        #expect(viewModel.isLoadingCatalog == false)
        #expect(viewModel.expenseCategories.map(\.id) == [10, 11])
        #expect(viewModel.assets.map(\.id) == [20, 21])
        #expect(viewModel.selectedCategoryId == 10)
        #expect(viewModel.selectedAssetId == 20)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "EXPENSE") == 1)
        #expect(recorder.count(path: "/api/v1/assets") == 1)
    }

    @Test("탭 전환은 income 카테고리를 로드하고 캐시된 expense 카테고리는 재요청하지 않는다")
    func tabSwitchLoadsIncomeAndReusesCachedExpenseCategories() async throws {
        let recorder = AddExpenseCatalogRequestRecorder()
        AddExpenseCatalogURLProtocol.handler = { request in
            recorder.record(request)
            return try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let viewModel = AddExpenseViewModel(catalogService: CatalogService(client: makeAddExpenseCatalogClient()))

        await viewModel.load()
        viewModel.selectedTab = .income
        try await waitUntil {
            viewModel.incomeCategories.map(\.id) == [30, 31]
                && viewModel.selectedCategoryId == 30
                && viewModel.isLoadingCatalog == false
        }

        #expect(viewModel.visibleCategories.map(\.id) == [30, 31])
        #expect(viewModel.selectedAssetId == 20)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "EXPENSE") == 1)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "INCOME") == 1)
        #expect(recorder.count(path: "/api/v1/assets") == 1)

        viewModel.selectedTab = .expense
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.visibleCategories.map(\.id) == [10, 11])
        #expect(viewModel.selectedCategoryId == 10)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "EXPENSE") == 1)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "INCOME") == 1)
        #expect(recorder.count(path: "/api/v1/assets") == 1)
    }

    @Test("이미 캐시된 탭으로 전환하면 이전 탭 로딩이 끝나지 않아도 로딩 상태에 갇히지 않는다")
    func switchingToCachedTabClearsStaleLoadingState() async throws {
        AddExpenseCatalogURLProtocol.handler = { request in
            try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let viewModel = AddExpenseViewModel(catalogService: CatalogService(client: makeAddExpenseCatalogClient()))

        // 양 탭 + 자산을 모두 캐시한다.
        await viewModel.load()
        viewModel.selectedTab = .income
        try await waitUntil {
            viewModel.incomeCategories.map(\.id) == [30, 31] && viewModel.isLoadingCatalog == false
        }

        // 이전 탭의 in-flight load가 selectedTab != loadingTab 분기로 끝난 직후 상태를 모사:
        // isLoadingCatalog가 true로 남아 있고 캐시된 탭으로 전환된다.
        viewModel.isLoadingCatalog = true
        viewModel.catalogError = "stale"
        viewModel.selectedTab = .expense

        #expect(viewModel.isLoadingCatalog == false)
        #expect(viewModel.catalogError == nil)
        #expect(viewModel.visibleCategories.map(\.id) == [10, 11])
        #expect(viewModel.selectedCategoryId == 10)
        #expect(viewModel.canSave == true)
    }

    @Test("카탈로그 로드 실패는 catalogError를 노출하고 저장을 막는다")
    func loadSurfacesErrorOnFailureEnvelope() async {
        AddExpenseCatalogURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/categories" {
                return try addExpenseCatalogResponse(for: request, data: failureEnvelopePayload())
            }
            return try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let viewModel = AddExpenseViewModel(catalogService: CatalogService(client: makeAddExpenseCatalogClient()))

        await viewModel.load()

        #expect(viewModel.catalogError != nil)
        #expect(viewModel.isLoadingCatalog == false)
        #expect(viewModel.canSave == false)
        #expect(viewModel.expenseCategories.isEmpty)
        #expect(viewModel.selectedCategoryId == nil)
    }
}

private struct AddExpenseCatalogRecordedRequest {
    let path: String
    let transactionType: String?
}

private final class AddExpenseCatalogRequestRecorder {
    private let lock = NSLock()
    private var requests: [AddExpenseCatalogRecordedRequest] = []

    func record(_ request: URLRequest) {
        guard let url = request.url else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let transactionType = components?.queryItems?.first { $0.name == "transactionType" }?.value
        let recordedRequest = AddExpenseCatalogRecordedRequest(path: url.path, transactionType: transactionType)

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
}

private final class AddExpenseCatalogURLProtocol: URLProtocol {
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

private enum AddExpenseCatalogURLProtocolError: Error {
    case invalidResponse
    case missingHandler
    case unexpectedRequest
    case timeout
}

private func makeAddExpenseCatalogClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AddExpenseCatalogURLProtocol.self]
    return APIClient(session: URLSession(configuration: configuration), token: { nil })
}

private func addExpenseCatalogResponse(
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

private func catalogPayload(for request: URLRequest) throws -> Data {
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

private func categoryPayload(transactionType: String?) throws -> Data {
    switch transactionType {
    case "EXPENSE":
        return expenseCategoryPayload()
    case "INCOME":
        return incomeCategoryPayload()
    default:
        throw AddExpenseCatalogURLProtocolError.unexpectedRequest
    }
}

private func expenseCategoryPayload() -> Data {
    Data(
        """
        {
            "success": true,
            "data": [
                {
                    "id": 11,
                    "code": "TRAVEL",
                    "displayNameKo": "여행",
                    "displayNameEn": "Travel",
                    "icon": "✈️",
                    "sortOrder": 2
                },
                {
                    "id": 10,
                    "code": "FOOD",
                    "displayNameKo": "식비",
                    "displayNameEn": "Food",
                    "icon": "🍽️",
                    "sortOrder": 1
                }
            ]
        }
        """.utf8
    )
}

private func incomeCategoryPayload() -> Data {
    Data(
        """
        {
            "success": true,
            "data": [
                {
                    "id": 31,
                    "code": "SIDE_INCOME",
                    "displayNameKo": "부수입",
                    "displayNameEn": "Side Income",
                    "icon": "💻",
                    "sortOrder": 2
                },
                {
                    "id": 30,
                    "code": "SALARY",
                    "displayNameKo": "급여",
                    "displayNameEn": "Salary",
                    "icon": "💼",
                    "sortOrder": 1
                }
            ]
        }
        """.utf8
    )
}

private func assetPayload() -> Data {
    Data(
        """
        {
            "success": true,
            "data": [
                {
                    "id": 21,
                    "code": "CARD",
                    "displayNameKo": "카드",
                    "displayNameEn": "Card",
                    "sortOrder": 2
                },
                {
                    "id": 20,
                    "code": "CASH",
                    "displayNameKo": "현금",
                    "displayNameEn": "Cash",
                    "sortOrder": 1
                }
            ]
        }
        """.utf8
    )
}

private func failureEnvelopePayload() -> Data {
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

private func waitUntil(
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
