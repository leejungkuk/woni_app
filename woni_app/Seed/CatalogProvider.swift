//
//  CatalogProvider.swift
//  woni_app
//

import Foundation

enum CatalogTransactionType: String, Codable, CaseIterable {
    case expense = "EXPENSE"
    case income = "INCOME"
}

struct CatalogProvider {
    private let expenseCategories: [Category]
    private let incomeCategories: [Category]
    let assets: [Asset]

    init(seedData: SeedData) {
        self.init(
            expenseCategories: seedData.expenseCategories,
            incomeCategories: seedData.incomeCategories,
            assets: seedData.assets
        )
    }

    init(expenseCategories: [Category], incomeCategories: [Category], assets: [Asset]) {
        self.expenseCategories = expenseCategories.sortedByCatalogOrder()
        self.incomeCategories = incomeCategories.sortedByCatalogOrder()
        self.assets = assets.sortedByCatalogOrder()
    }

    init(loader: SeedLoader = SeedLoader()) throws {
        try self.init(seedData: loader.load())
    }

    func categories(for transactionType: CatalogTransactionType) -> [Category] {
        switch transactionType {
        case .expense:
            expenseCategories
        case .income:
            incomeCategories
        }
    }
}

private extension Array where Element == Category {
    func sortedByCatalogOrder() -> [Category] {
        sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.id < $1.id
            }
            return $0.sortOrder < $1.sortOrder
        }
    }
}

private extension Array where Element == Asset {
    func sortedByCatalogOrder() -> [Asset] {
        sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.id < $1.id
            }
            return $0.sortOrder < $1.sortOrder
        }
    }
}
