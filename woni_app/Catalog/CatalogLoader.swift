//
//  CatalogLoader.swift
//  woni_app
//

import Foundation

struct CatalogLoader {
    private let service: CatalogService
    private let seedData: SeedData
    private let onFallback: (CatalogLoaderFallbackReason) -> Void

    init(
        service: CatalogService = CatalogService(),
        seedLoader: SeedLoader = SeedLoader(),
        onFallback: @escaping (CatalogLoaderFallbackReason) -> Void = { reason in
            NSLog("CatalogLoader falling back to seed: \(reason.description)")
        }
    ) throws {
        try self.init(
            service: service,
            seedData: seedLoader.load(),
            onFallback: onFallback
        )
    }

    init(
        service: CatalogService,
        seedData: SeedData,
        onFallback: @escaping (CatalogLoaderFallbackReason) -> Void = { reason in
            NSLog("CatalogLoader falling back to seed: \(reason.description)")
        }
    ) {
        self.service = service
        self.seedData = seedData
        self.onFallback = onFallback
    }

    func load() async -> CatalogProvider {
        do {
            let expenseCategories = try await service.fetchCategories(
                transactionType: CatalogTransactionType.expense.rawValue
            )
            let incomeCategories = try await service.fetchCategories(
                transactionType: CatalogTransactionType.income.rawValue
            )
            let assets = try await service.fetchAssets()

            try validate(
                expenseCategories: expenseCategories,
                incomeCategories: incomeCategories,
                assets: assets
            )

            return CatalogProvider(
                expenseCategories: expenseCategories,
                incomeCategories: incomeCategories,
                assets: assets
            )
        } catch let error as CatalogLoaderValidationError {
            onFallback(.invalidServerCatalog(error.description))
            return CatalogProvider(seedData: seedData)
        } catch {
            onFallback(.requestFailed(String(describing: error)))
            return CatalogProvider(seedData: seedData)
        }
    }
}

enum CatalogLoaderFallbackReason: Equatable, CustomStringConvertible {
    case requestFailed(String)
    case invalidServerCatalog(String)

    var description: String {
        switch self {
        case let .requestFailed(message):
            "request failed: \(message)"
        case let .invalidServerCatalog(message):
            "invalid server catalog: \(message)"
        }
    }
}

private extension CatalogLoader {
    func validate(
        expenseCategories: [Category],
        incomeCategories: [Category],
        assets: [Asset]
    ) throws {
        try validateNonEmpty(expenseCategories, collection: "expense categories")
        try validateNonEmpty(incomeCategories, collection: "income categories")
        try validateNonEmpty(assets, collection: "assets")

        let categories = expenseCategories + incomeCategories
        try validateUnique(categories, keyPath: \.id, collection: "categories", field: "id")
        try validateUnique(categories, keyPath: \.code, collection: "categories", field: "code")
        try validateUnique(assets, keyPath: \.id, collection: "assets", field: "id")
        try validateUnique(assets, keyPath: \.code, collection: "assets", field: "code")

        try validateSeedInvariant(
            serverItems: expenseCategories,
            seedItems: seedData.expenseCategories,
            collection: "expense categories",
            code: \.code,
            id: \.id
        )
        try validateSeedInvariant(
            serverItems: incomeCategories,
            seedItems: seedData.incomeCategories,
            collection: "income categories",
            code: \.code,
            id: \.id
        )
        try validateSeedInvariant(
            serverItems: assets,
            seedItems: seedData.assets,
            collection: "assets",
            code: \.code,
            id: \.id
        )
    }

    func validateNonEmpty<Element>(_ items: [Element], collection: String) throws {
        guard !items.isEmpty else {
            throw CatalogLoaderValidationError.emptyCollection(collection)
        }
    }

    func validateUnique<Element, Value: Hashable>(
        _ items: [Element],
        keyPath: KeyPath<Element, Value>,
        collection: String,
        field: String
    ) throws {
        var seen = Set<Value>()
        for item in items where !seen.insert(item[keyPath: keyPath]).inserted {
            throw CatalogLoaderValidationError.duplicateValue(
                collection: collection,
                field: field
            )
        }
    }

    func validateSeedInvariant<Element>(
        serverItems: [Element],
        seedItems: [Element],
        collection: String,
        code: KeyPath<Element, String>,
        id: KeyPath<Element, Int>
    ) throws {
        let serverMap = codeIDMap(serverItems, code: code, id: id)
        let seedMap = codeIDMap(seedItems, code: code, id: id)

        guard serverMap == seedMap else {
            throw CatalogLoaderValidationError.seedInvariantMismatch(collection)
        }
    }

    func codeIDMap<Element>(
        _ items: [Element],
        code: KeyPath<Element, String>,
        id: KeyPath<Element, Int>
    ) -> [String: Int] {
        var result: [String: Int] = [:]
        for item in items {
            result[item[keyPath: code]] = item[keyPath: id]
        }
        return result
    }
}

private enum CatalogLoaderValidationError: Error, CustomStringConvertible {
    case emptyCollection(String)
    case duplicateValue(collection: String, field: String)
    case seedInvariantMismatch(String)

    var description: String {
        switch self {
        case let .emptyCollection(collection):
            "\(collection) is empty"
        case let .duplicateValue(collection, field):
            "\(collection) contains duplicate \(field)"
        case let .seedInvariantMismatch(collection):
            "\(collection) code-to-id map differs from seed"
        }
    }
}
