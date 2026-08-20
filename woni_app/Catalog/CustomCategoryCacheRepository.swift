//
//  CustomCategoryCacheRepository.swift
//  woni_app
//

import Foundation
import GRDB

enum CustomCategorySyncState: String, Equatable {
    case synced
    case pendingCreate
    case pendingUpdate
    case pendingDelete
    case deleted
}

struct CachedCustomCategory: Equatable {
    let id: Int
    let transactionType: CatalogTransactionType
    let name: String
    var syncState: CustomCategorySyncState = .synced
}

enum CustomCategoryCacheError: Error, Equatable {
    case invalidColumnValue(column: String, value: String)
    case remapSourceMissing(id: Int)
}

protocol CustomCategoryCaching {
    func load(for transactionType: CatalogTransactionType) throws -> [CachedCustomCategory]
    func loadAll() throws -> [CachedCustomCategory]
    func replaceSynced(_ categories: [CachedCustomCategory]) async throws
    func upsert(_ category: CachedCustomCategory) async throws
    func updateName(id: Int, name: String) async throws
    func updateSyncState(id: Int, to state: CustomCategorySyncState) async throws
    func deleteRow(id: Int) async throws
    func nextLocalID() throws -> Int
    func activeCount() throws -> Int
    func remap(from oldID: Int, to newID: Int) async throws
    func referencedCategoryIDs() throws -> Set<Int>
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
                SELECT id, transaction_type, name, sync_state
                FROM custom_category
                WHERE transaction_type = ? AND sync_state IN (?, ?, ?)
                ORDER BY id DESC
                """,
                arguments: StatementArguments([transactionType.rawValue] + Self.listVisibleStates)
            ).map(Self.cached(from:))
        }
    }

    func loadAll() throws -> [CachedCustomCategory] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, transaction_type, name, sync_state FROM custom_category ORDER BY id DESC"
            ).map(Self.cached(from:))
        }
    }

    func replaceSynced(_ categories: [CachedCustomCategory]) async throws {
        let stored = categories.map { StoredCustomCategory(cached: $0) }
        try await database.write { @Sendable db in
            // synced 행만 지운다 — pending*·deleted 행은 아직 서버에 반영되지 않은 로컬 작업이다.
            try db.execute(
                sql: "DELETE FROM custom_category WHERE sync_state = ?",
                arguments: [CustomCategorySyncState.synced.rawValue]
            )
            for category in stored {
                try db.execute(
                    sql: """
                    INSERT INTO custom_category (id, transaction_type, name, sync_state)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [category.id, category.transactionType, category.name, category.syncState]
                )
            }
        }
    }

    func upsert(_ category: CachedCustomCategory) async throws {
        let stored = StoredCustomCategory(cached: category)
        try await database.write { @Sendable db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO custom_category (id, transaction_type, name, sync_state)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [stored.id, stored.transactionType, stored.name, stored.syncState]
            )
        }
    }

    func updateName(id: Int, name: String) async throws {
        try await database.write { @Sendable db in
            try db.execute(
                sql: "UPDATE custom_category SET name = ? WHERE id = ?",
                arguments: [name, id]
            )
        }
    }

    func updateSyncState(id: Int, to state: CustomCategorySyncState) async throws {
        let rawState = state.rawValue
        try await database.write { @Sendable db in
            try db.execute(
                sql: "UPDATE custom_category SET sync_state = ? WHERE id = ?",
                arguments: [rawState, id]
            )
        }
    }

    func deleteRow(id: Int) async throws {
        try await database.write { @Sendable db in
            try db.execute(sql: "DELETE FROM custom_category WHERE id = ?", arguments: [id])
        }
    }

    /// 서버 id는 항상 양수이므로 음수 로컬 id는 충돌이 불가능하고 단조 감소한다.
    func nextLocalID() throws -> Int {
        try database.read { db in
            let minimumID = try Int.fetchOne(db, sql: "SELECT MIN(id) FROM custom_category") ?? 0
            return min(minimumID, 0) - 1
        }
    }

    /// 서버가 is_active=true만 세므로 pendingDelete·deleted를 세면 기기 간 동작 차이가 난다.
    func activeCount() throws -> Int {
        try database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM custom_category WHERE sync_state IN (?, ?, ?)",
                arguments: StatementArguments(Self.listVisibleStates)
            ) ?? 0
        }
    }

    /// 카테고리 행과 내역 참조가 같은 트랜잭션에서 바뀌어야 한다 — 한쪽만 바뀌면
    /// 내역이 존재하지 않는 카테고리를 참조한다.
    func remap(from oldID: Int, to newID: Int) async throws {
        try await database.write { @Sendable db in
            try db.execute(
                sql: "UPDATE custom_category SET id = ? WHERE id = ?",
                arguments: [newID, oldID]
            )
            // 원본이 없으면 내역만 새 id로 밀려 존재하지 않는(또는 남의) 카테고리를 가리킨다.
            // 조용히 넘기지 않고 write 전체를 롤백시킨다.
            guard db.changesCount == 1 else {
                throw CustomCategoryCacheError.remapSourceMissing(id: oldID)
            }
            try db.execute(
                sql: "UPDATE transaction_entry SET category_id = ? WHERE category_id = ?",
                arguments: [newID, oldID]
            )
        }
    }

    func referencedCategoryIDs() throws -> Set<Int> {
        try database.read { db in
            try Set(Int.fetchAll(db, sql: "SELECT DISTINCT category_id FROM transaction_entry"))
        }
    }

    func clearAll() async throws {
        try await database.write { @Sendable db in
            try db.execute(sql: "DELETE FROM custom_category")
        }
    }
}

private extension CustomCategoryCacheRepository {
    /// 목록 노출 대상 상태 — pendingDelete·deleted는 목록에서 빠지되 스냅샷 조회에는 잡힌다.
    static let listVisibleStates = [
        CustomCategorySyncState.synced.rawValue,
        CustomCategorySyncState.pendingCreate.rawValue,
        CustomCategorySyncState.pendingUpdate.rawValue
    ]

    static func cached(from row: Row) throws -> CachedCustomCategory {
        let rawType: String = row["transaction_type"]
        let rawState: String = row["sync_state"]
        guard let transactionType = CatalogTransactionType(rawValue: rawType) else {
            throw CustomCategoryCacheError.invalidColumnValue(column: "transaction_type", value: rawType)
        }
        guard let syncState = CustomCategorySyncState(rawValue: rawState) else {
            throw CustomCategoryCacheError.invalidColumnValue(column: "sync_state", value: rawState)
        }
        return CachedCustomCategory(
            id: row["id"],
            transactionType: transactionType,
            name: row["name"],
            syncState: syncState
        )
    }
}

private struct StoredCustomCategory {
    let id: Int
    let transactionType: String
    let name: String
    let syncState: String

    init(cached: CachedCustomCategory) {
        id = cached.id
        transactionType = cached.transactionType.rawValue
        name = cached.name
        syncState = cached.syncState.rawValue
    }
}
