//
//  CatalogDTOTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 카탈로그 DTO 디코딩과 Service 요청 경로를 서버 계약 기준으로 검증한다.
@Suite(.serialized)
@MainActor
struct CatalogDTOTests {
    @Test("CategoryDTO는 서버 JSON을 디코딩하고 도메인 모델로 매핑한다")
    func decodesCategoryJSONAndMapsToDomain() throws {
        let json = Data(
            """
            {
                "id": 10,
                "code": "FOOD",
                "displayNameKo": "식비",
                "displayNameEn": "Food",
                "icon": "fork.knife",
                "sortOrder": 1
            }
            """.utf8
        )

        let dto = try JSONDecoder().decode(CategoryDTO.self, from: json)
        let domain = dto.toDomain()

        #expect(domain.id == 10)
        #expect(domain.code == "FOOD")
        #expect(domain.displayNameKo == "식비")
        #expect(domain.displayNameEn == "Food")
        #expect(domain.icon == "fork.knife")
        #expect(domain.sortOrder == 1)
    }

    @Test("CategoryDTO는 icon이 null이면 nil로 디코딩한다")
    func decodesCategoryNullIcon() throws {
        let json = Data(
            """
            {
                "id": 11,
                "code": "SALARY",
                "displayNameKo": "급여",
                "displayNameEn": "Salary",
                "icon": null,
                "sortOrder": 2
            }
            """.utf8
        )

        let dto = try JSONDecoder().decode(CategoryDTO.self, from: json)
        let domain = dto.toDomain()

        #expect(domain.id == 11)
        #expect(domain.icon == nil)
    }

    @Test("AssetDTO는 icon 키 없이 디코딩하고 도메인 모델로 매핑한다")
    func decodesAssetJSONWithoutIconAndMapsToDomain() throws {
        let json = Data(
            """
            {
                "id": 20,
                "code": "CASH",
                "displayNameKo": "현금",
                "displayNameEn": "Cash",
                "sortOrder": 1
            }
            """.utf8
        )

        let dto = try JSONDecoder().decode(AssetDTO.self, from: json)
        let domain = dto.toDomain()

        #expect(domain.id == 20)
        #expect(domain.code == "CASH")
        #expect(domain.displayNameKo == "현금")
        #expect(domain.displayNameEn == "Cash")
        #expect(domain.sortOrder == 1)
    }

    @Test("fetchCategories는 transactionType query를 싣고 도메인 모델을 반환한다")
    func fetchCategoriesSendsTransactionTypeQuery() async throws {
        let recorder = CatalogRequestRecorder()
        CatalogURLProtocol.handler = { request in
            recorder.record(request)
            return try makeCatalogResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": true,
                        "data": [
                            {
                                "id": 10,
                                "code": "FOOD",
                                "displayNameKo": "식비",
                                "displayNameEn": "Food",
                                "icon": "fork.knife",
                                "sortOrder": 1
                            }
                        ]
                    }
                    """.utf8
                )
            )
        }
        defer { CatalogURLProtocol.handler = nil }

        let service = CatalogService(client: makeCatalogClient())

        let categories = try await service.fetchCategories(transactionType: "EXPENSE")

        let request = try #require(recorder.snapshot())
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)
        #expect(request.method == "GET")
        #expect(url.path == "/api/v1/categories")
        #expect(queryItems.contains { $0.name == "transactionType" && $0.value == "EXPENSE" })
        #expect(categories.map(\.id) == [10])
        #expect(categories.first?.code == "FOOD")
        #expect(categories.first?.icon == "fork.knife")
    }

    @Test("fetchAssets는 assets endpoint를 호출하고 icon 없는 응답을 매핑한다")
    func fetchAssetsMapsResponseWithoutIcon() async throws {
        let recorder = CatalogRequestRecorder()
        CatalogURLProtocol.handler = { request in
            recorder.record(request)
            return try makeCatalogResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": true,
                        "data": [
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
            )
        }
        defer { CatalogURLProtocol.handler = nil }

        let service = CatalogService(client: makeCatalogClient())

        let assets = try await service.fetchAssets()

        let request = try #require(recorder.snapshot())
        let url = try #require(request.url)
        #expect(request.method == "GET")
        #expect(url.path == "/api/v1/assets")
        #expect(assets.map(\.id) == [20])
        #expect(assets.first?.code == "CASH")
    }

    private func makeCatalogClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocol.self]
        return APIClient(session: URLSession(configuration: configuration))
    }
}

private struct CatalogRecordedRequest {
    let url: URL?
    let method: String?
}

private final class CatalogRequestRecorder {
    private let lock = NSLock()
    private var request: CatalogRecordedRequest?

    func record(_ request: URLRequest) {
        let recordedRequest = CatalogRecordedRequest(
            url: request.url,
            method: request.httpMethod
        )

        lock.lock()
        self.request = recordedRequest
        lock.unlock()
    }

    func snapshot() -> CatalogRecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private final class CatalogURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: CatalogURLProtocolError.missingHandler)
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

private enum CatalogURLProtocolError: Error {
    case missingHandler
    case invalidResponse
}

private func makeCatalogResponse(
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
        throw CatalogURLProtocolError.invalidResponse
    }
    return (response, data)
}
