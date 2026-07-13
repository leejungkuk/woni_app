//
//  CatalogLoaderTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct CatalogLoaderTests {
    @Test("load returns server provider when all catalog responses are valid")
    func loadReturnsServerProviderWhenAllResponsesAreValid() async throws {
        let seedData = try SeedLoader().load()
        let suffix = " Server"
        let responses = try makeCatalogResponses(
            from: makeServerCatalog(seedData: seedData, suffix: suffix)
        )
        let fallbackRecorder = CatalogLoaderFallbackRecorder()
        CatalogLoaderURLProtocol.handler = { request in
            try makeCatalogLoaderResponse(
                for: request,
                data: responses.data(for: request)
            )
        }
        defer { CatalogLoaderURLProtocol.handler = nil }

        let loader = CatalogLoader(
            service: CatalogService(client: makeCatalogLoaderClient()),
            seedData: seedData,
            onFallback: fallbackRecorder.record
        )

        let provider = await loader.load()

        #expect(fallbackRecorder.snapshot().isEmpty)
        #expect(provider.categories(for: .expense).first?.displayNameEn.hasSuffix(suffix) == true)
        #expect(provider.categories(for: .income).first?.displayNameEn.hasSuffix(suffix) == true)
        #expect(provider.assets.first?.displayNameEn.hasSuffix(suffix) == true)
        #expect(provider.categories(for: .expense).map(\.id) == seedData.expenseCategories.map(\.id))
        #expect(provider.categories(for: .income).map(\.id) == seedData.incomeCategories.map(\.id))
        #expect(provider.assets.map(\.id) == seedData.assets.map(\.id))
    }

    @Test("all server error types fall back to seed catalog")
    func allServerErrorTypesFallBackToSeedCatalog() async throws {
        for scenario in CatalogLoaderFailureScenario.allCases {
            let seedData = try SeedLoader().load()
            let fallbackRecorder = CatalogLoaderFallbackRecorder()
            CatalogLoaderURLProtocol.handler = { request in
                try scenario.response(for: request)
            }

            let loader = CatalogLoader(
                service: CatalogService(client: makeCatalogLoaderClient()),
                seedData: seedData,
                onFallback: fallbackRecorder.record
            )

            let provider = await loader.load()

            assertProviderMatchesSeed(provider, seedData: seedData)
            #expect(fallbackRecorder.snapshot().count == 1)
        }

        CatalogLoaderURLProtocol.handler = nil
    }

    @Test("invalid server catalog responses fall back to seed catalog")
    func invalidServerCatalogResponsesFallBackToSeedCatalog() async throws {
        for scenario in InvalidCatalogScenario.allCases {
            let seedData = try SeedLoader().load()
            let responses = try makeCatalogResponses(
                from: makeInvalidServerCatalog(seedData: seedData, scenario: scenario)
            )
            let fallbackRecorder = CatalogLoaderFallbackRecorder()
            CatalogLoaderURLProtocol.handler = { request in
                try makeCatalogLoaderResponse(
                    for: request,
                    data: responses.data(for: request)
                )
            }

            let loader = CatalogLoader(
                service: CatalogService(client: makeCatalogLoaderClient()),
                seedData: seedData,
                onFallback: fallbackRecorder.record
            )

            let provider = await loader.load()

            assertProviderMatchesSeed(provider, seedData: seedData)
            #expect(fallbackRecorder.snapshot().count == 1)
        }

        CatalogLoaderURLProtocol.handler = nil
    }

    @Test("one failed catalog request falls back to full seed catalog")
    func oneFailedCatalogRequestFallsBackToFullSeedCatalog() async throws {
        let seedData = try SeedLoader().load()
        let responses = try makeCatalogResponses(
            from: makeServerCatalog(seedData: seedData, suffix: " Server")
        )
        let fallbackRecorder = CatalogLoaderFallbackRecorder()
        CatalogLoaderURLProtocol.handler = { request in
            let route = try CatalogLoaderRoute.route(for: request)
            if route == .assets {
                return try makeCatalogLoaderResponse(
                    for: request,
                    statusCode: 503,
                    data: Data(#"{ "success": true, "data": [] }"#.utf8)
                )
            }
            return try makeCatalogLoaderResponse(
                for: request,
                data: responses.data(for: route)
            )
        }
        defer { CatalogLoaderURLProtocol.handler = nil }

        let loader = CatalogLoader(
            service: CatalogService(client: makeCatalogLoaderClient()),
            seedData: seedData,
            onFallback: fallbackRecorder.record
        )

        let provider = await loader.load()

        assertProviderMatchesSeed(provider, seedData: seedData)
        #expect(fallbackRecorder.snapshot().count == 1)
    }
}

private enum CatalogLoaderRoute: Equatable {
    case expenseCategories
    case incomeCategories
    case assets

    static func route(for request: URLRequest) throws -> CatalogLoaderRoute {
        guard
            let url = request.url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw CatalogLoaderURLProtocolError.invalidResponse
        }

        if url.path == "/api/v1/assets" {
            return .assets
        }

        guard url.path == "/api/v1/categories" else {
            throw CatalogLoaderURLProtocolError.invalidResponse
        }

        let transactionType = components.queryItems?.first {
            $0.name == "transactionType"
        }?.value

        switch transactionType {
        case CatalogTransactionType.expense.rawValue:
            return .expenseCategories
        case CatalogTransactionType.income.rawValue:
            return .incomeCategories
        default:
            throw CatalogLoaderURLProtocolError.invalidResponse
        }
    }
}

private enum CatalogLoaderFailureScenario: CaseIterable {
    case transport
    case httpStatus
    case emptyResponse
    case decoding
    case server

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        switch self {
        case .transport:
            throw CatalogLoaderTransportFailure()
        case .httpStatus:
            return try makeCatalogLoaderResponse(
                for: request,
                statusCode: 500,
                data: Data(#"{ "success": true, "data": [] }"#.utf8)
            )
        case .emptyResponse:
            return try makeCatalogLoaderResponse(for: request, data: Data())
        case .decoding:
            return try makeCatalogLoaderResponse(for: request, data: Data("not-json".utf8))
        case .server:
            return try makeCatalogLoaderResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": false,
                        "code": "CATALOG_UNAVAILABLE",
                        "data": null,
                        "message": "catalog unavailable"
                    }
                    """.utf8
                )
            )
        }
    }
}

private enum InvalidCatalogScenario: CaseIterable {
    case emptyExpenseCategories
    case emptyIncomeCategories
    case emptyAssets
    case duplicateCategoryID
    case duplicateCategoryCode
    case duplicateAssetID
    case duplicateAssetCode
    case seedInvariantMismatch
    case incomeSeedInvariantMismatch
    case assetSeedInvariantMismatch
}

private struct CatalogServerCatalog {
    var expenseCategories: [woni_app.Category]
    var incomeCategories: [woni_app.Category]
    var assets: [Asset]
}

private struct CatalogResponseSet {
    let expenseCategories: Data
    let incomeCategories: Data
    let assets: Data

    func data(for request: URLRequest) throws -> Data {
        try data(for: CatalogLoaderRoute.route(for: request))
    }

    func data(for route: CatalogLoaderRoute) -> Data {
        switch route {
        case .expenseCategories:
            expenseCategories
        case .incomeCategories:
            incomeCategories
        case .assets:
            assets
        }
    }
}

private final class CatalogLoaderFallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var reasons: [CatalogLoaderFallbackReason] = []

    func record(_ reason: CatalogLoaderFallbackReason) {
        lock.lock()
        reasons.append(reason)
        lock.unlock()
    }

    func snapshot() -> [CatalogLoaderFallbackReason] {
        lock.lock()
        defer { lock.unlock() }
        return reasons
    }
}

private final class CatalogLoaderURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: CatalogLoaderURLProtocolError.missingHandler)
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

private enum CatalogLoaderURLProtocolError: Error {
    case missingHandler
    case invalidResponse
}

private struct CatalogLoaderTransportFailure: Error {}

private func makeCatalogLoaderClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CatalogLoaderURLProtocol.self]
    return APIClient(session: URLSession(configuration: configuration), token: { nil })
}

private func makeServerCatalog(seedData: SeedData, suffix: String) -> CatalogServerCatalog {
    CatalogServerCatalog(
        expenseCategories: seedData.expenseCategories.map { copyCategory($0, suffix: suffix) },
        incomeCategories: seedData.incomeCategories.map { copyCategory($0, suffix: suffix) },
        assets: seedData.assets.map { copyAsset($0, suffix: suffix) }
    )
}

private func makeInvalidServerCatalog(
    seedData: SeedData,
    scenario: InvalidCatalogScenario
) -> CatalogServerCatalog {
    var catalog = makeServerCatalog(seedData: seedData, suffix: " Server")

    switch scenario {
    case .emptyExpenseCategories:
        catalog.expenseCategories = []
    case .emptyIncomeCategories:
        catalog.incomeCategories = []
    case .emptyAssets:
        catalog.assets = []
    case .duplicateCategoryID:
        catalog.incomeCategories[0] = copyCategory(
            catalog.incomeCategories[0],
            id: catalog.expenseCategories[0].id
        )
    case .duplicateCategoryCode:
        catalog.incomeCategories[0] = copyCategory(
            catalog.incomeCategories[0],
            code: catalog.expenseCategories[0].code
        )
    case .duplicateAssetID:
        catalog.assets[1] = copyAsset(catalog.assets[1], id: catalog.assets[0].id)
    case .duplicateAssetCode:
        catalog.assets[1] = copyAsset(catalog.assets[1], code: catalog.assets[0].code)
    case .seedInvariantMismatch:
        catalog.expenseCategories[0] = copyCategory(
            catalog.expenseCategories[0],
            id: nextCategoryID(in: catalog)
        )
    case .incomeSeedInvariantMismatch:
        catalog.incomeCategories[0] = copyCategory(
            catalog.incomeCategories[0],
            id: nextCategoryID(in: catalog)
        )
    case .assetSeedInvariantMismatch:
        catalog.assets[0] = copyAsset(catalog.assets[0], id: nextAssetID(in: catalog))
    }

    return catalog
}

private func nextCategoryID(in catalog: CatalogServerCatalog) -> Int {
    (
        (catalog.expenseCategories + catalog.incomeCategories)
            .map(\.id)
            .max() ?? 0
    ) + 1
}

private func nextAssetID(in catalog: CatalogServerCatalog) -> Int {
    (catalog.assets.map(\.id).max() ?? 0) + 1
}

private func makeCatalogResponses(from catalog: CatalogServerCatalog) throws -> CatalogResponseSet {
    try CatalogResponseSet(
        expenseCategories: categoryEnvelopeData(catalog.expenseCategories),
        incomeCategories: categoryEnvelopeData(catalog.incomeCategories),
        assets: assetEnvelopeData(catalog.assets)
    )
}

private func categoryEnvelopeData(_ categories: [woni_app.Category]) throws -> Data {
    try envelopeData(
        categories.map { category in
            [
                "id": category.id,
                "code": category.code,
                "displayNameKo": category.displayNameKo,
                "displayNameEn": category.displayNameEn,
                "icon": category.icon.map { $0 as Any } ?? NSNull(),
                "sortOrder": category.sortOrder
            ] as [String: Any]
        }
    )
}

private func assetEnvelopeData(_ assets: [Asset]) throws -> Data {
    try envelopeData(
        assets.map { asset in
            [
                "id": asset.id,
                "code": asset.code,
                "displayNameKo": asset.displayNameKo,
                "displayNameEn": asset.displayNameEn,
                "sortOrder": asset.sortOrder
            ] as [String: Any]
        }
    )
}

private func envelopeData(_ data: Any) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "success": true,
            "code": NSNull(),
            "data": data,
            "message": NSNull(),
            "timestamp": "2026-07-02T13:11:44.000000"
        ],
        options: [.sortedKeys]
    )
}

private func makeCatalogLoaderResponse(
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
        throw CatalogLoaderURLProtocolError.invalidResponse
    }
    return (response, data)
}

private func assertProviderMatchesSeed(
    _ provider: CatalogProvider,
    seedData: SeedData
) {
    let seedProvider = CatalogProvider(seedData: seedData)

    #expect(
        categorySignatures(provider.categories(for: .expense)) ==
            categorySignatures(seedProvider.categories(for: .expense))
    )
    #expect(
        categorySignatures(provider.categories(for: .income)) ==
            categorySignatures(seedProvider.categories(for: .income))
    )
    #expect(assetSignatures(provider.assets) == assetSignatures(seedProvider.assets))
}

private struct CategorySignature: Equatable {
    let id: Int
    let code: String
    let displayNameKo: String
    let displayNameEn: String
    let icon: String?
    let sortOrder: Int
}

private struct AssetSignature: Equatable {
    let id: Int
    let code: String
    let displayNameKo: String
    let displayNameEn: String
    let sortOrder: Int
}

private func categorySignatures(_ categories: [woni_app.Category]) -> [CategorySignature] {
    categories.map { category in
        CategorySignature(
            id: category.id,
            code: category.code,
            displayNameKo: category.displayNameKo,
            displayNameEn: category.displayNameEn,
            icon: category.icon,
            sortOrder: category.sortOrder
        )
    }
}

private func assetSignatures(_ assets: [Asset]) -> [AssetSignature] {
    assets.map { asset in
        AssetSignature(
            id: asset.id,
            code: asset.code,
            displayNameKo: asset.displayNameKo,
            displayNameEn: asset.displayNameEn,
            sortOrder: asset.sortOrder
        )
    }
}

private func copyCategory(
    _ category: woni_app.Category,
    id: Int? = nil,
    code: String? = nil,
    suffix: String = ""
) -> woni_app.Category {
    woni_app.Category(
        id: id ?? category.id,
        code: code ?? category.code,
        displayNameKo: category.displayNameKo + suffix,
        displayNameEn: category.displayNameEn + suffix,
        icon: category.icon,
        sortOrder: category.sortOrder
    )
}

private func copyAsset(
    _ asset: Asset,
    id: Int? = nil,
    code: String? = nil,
    suffix: String = ""
) -> Asset {
    Asset(
        id: id ?? asset.id,
        code: code ?? asset.code,
        displayNameKo: asset.displayNameKo + suffix,
        displayNameEn: asset.displayNameEn + suffix,
        sortOrder: asset.sortOrder
    )
}
