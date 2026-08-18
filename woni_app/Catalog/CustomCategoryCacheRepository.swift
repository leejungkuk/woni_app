//
//  CustomCategoryCacheRepository.swift
//  woni_app
//

import Foundation
import GRDB

struct CachedCustomCategory: Equatable {
    let id: Int
    let transactionType: CatalogTransactionType
    let name: String
}

protocol CustomCategoryCaching {
    func load(for transactionType: CatalogTransactionType) throws -> [CachedCustomCategory]
    func replaceAll(_ categories: [CachedCustomCategory]) async throws
    func clearAll() async throws
}

struct CustomCategoryCacheRepository: CustomCategoryCaching {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func load(for transactionType: CatalogTransactionType) throws -> [CachedCustomCategory] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id, transaction_type, name
                FROM custom_category
                WHERE transaction_type = ?
                ORDER BY id ASC
                """,
                arguments: [transactionType.rawValue]
            ).map { row in
                CachedCustomCategory(
                    id: row["id"],
                    transactionType: transactionType,
                    name: row["name"]
                )
            }
        }
    }

    func replaceAll(_ categories: [CachedCustomCategory]) async throws {
        let stored = categories.map {
            StoredCustomCategory(
                id: $0.id,
                transactionType: $0.transactionType.rawValue,
                name: $0.name
            )
        }
        try await database.write { @Sendable db in
            try db.execute(sql: "DELETE FROM custom_category")
            for category in stored {
                try db.execute(
                    sql: """
                    INSERT INTO custom_category (id, transaction_type, name)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [category.id, category.transactionType, category.name]
                )
            }
        }
    }

    func clearAll() async throws {
        try await database.write { @Sendable db in
            try db.execute(sql: "DELETE FROM custom_category")
        }
    }
}

private struct StoredCustomCategory {
    let id: Int
    let transactionType: String
    let name: String
}
