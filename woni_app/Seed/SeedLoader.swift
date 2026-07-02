//
//  SeedLoader.swift
//  woni_app
//

import Foundation

struct SeedData {
    let exchangeRates: [SeedExchangeRate]
    let expenseCategories: [Category]
    let incomeCategories: [Category]
    let assets: [Asset]
}

struct SeedLoader {
    private let bundles: [Bundle]
    private let decoder: JSONDecoder

    init(bundles: [Bundle]? = nil, decoder: JSONDecoder = JSONDecoder()) {
        self.bundles = bundles ?? Self.defaultBundles()
        self.decoder = decoder
    }

    func load() throws -> SeedData {
        let exchangeRateDTOs: [SeedExchangeRateDTO] = try decodeEnvelope(
            [SeedExchangeRateDTO].self,
            from: .exchangeRateSnapshot
        )
        let expenseCategoryDTOs: [CategoryDTO] = try decodeEnvelope(
            [CategoryDTO].self,
            from: .expenseCategories
        )
        let incomeCategoryDTOs: [CategoryDTO] = try decodeEnvelope(
            [CategoryDTO].self,
            from: .incomeCategories
        )
        let assetDTOs: [AssetDTO] = try decodeEnvelope(
            [AssetDTO].self,
            from: .assets
        )

        return SeedData(
            exchangeRates: exchangeRateDTOs.map { $0.toDomain() },
            expenseCategories: expenseCategoryDTOs.map { $0.toDomain() },
            incomeCategories: incomeCategoryDTOs.map { $0.toDomain() },
            assets: assetDTOs.map { $0.toDomain() }
        )
    }
}

private extension SeedLoader {
    enum Resource: String, CaseIterable {
        case exchangeRateSnapshot = "exchange-rate-snapshot"
        case expenseCategories = "categories-expense"
        case incomeCategories = "categories-income"
        case assets

        var filename: String {
            "\(rawValue).json"
        }
    }

    func decodeEnvelope<T: Decodable>(_: T.Type, from resource: Resource) throws -> T {
        let url = try url(for: resource)
        let data = try Data(contentsOf: url)
        let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)

        guard envelope.success else {
            throw SeedLoaderError.unsuccessfulEnvelope(
                resource: resource.filename,
                code: envelope.code,
                message: envelope.message
            )
        }

        guard let payload = envelope.data else {
            throw SeedLoaderError.missingData(resource: resource.filename)
        }

        return payload
    }

    func url(for resource: Resource) throws -> URL {
        for bundle in bundles {
            if let url = bundle.url(forResource: resource.rawValue, withExtension: "json") {
                return url
            }

            if let url = bundle.url(
                forResource: resource.rawValue,
                withExtension: "json",
                subdirectory: "Seed"
            ) {
                return url
            }
        }

        throw SeedLoaderError.resourceNotFound(resource.filename)
    }

    static func defaultBundles() -> [Bundle] {
        // 시드는 앱 타깃 번들에 동봉된다. SeedLoader 코드가 속한 번들(=앱 번들)을
        // 결정적으로 우선하고, 실행 컨텍스트 차이를 위해 Bundle.main만 폴백으로 둔다.
        // allBundles/allFrameworks 광역 스캔은 리소스 타깃 누락(false green)을 가릴 수 있어 배제한다.
        var seenPaths = Set<String>()
        return [Bundle(for: SeedBundleLocator.self), Bundle.main].filter { bundle in
            seenPaths.insert(bundle.bundleURL.path).inserted
        }
    }
}

private final class SeedBundleLocator: NSObject {}

enum SeedLoaderError: Error, LocalizedError, Equatable {
    case resourceNotFound(String)
    case unsuccessfulEnvelope(resource: String, code: String?, message: String?)
    case missingData(resource: String)

    var errorDescription: String? {
        switch self {
        case let .resourceNotFound(resource):
            "Seed resource not found: \(resource)"
        case let .unsuccessfulEnvelope(resource, code, message):
            "Seed envelope failed for \(resource): \(code ?? "unknown") \(message ?? "")"
        case let .missingData(resource):
            "Seed envelope has no data: \(resource)"
        }
    }
}
