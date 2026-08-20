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
    case categoryNotFound(id: Int)
}

protocol CustomCategoryCaching {
    func load(for transactionType: CatalogTransactionType) throws -> [CachedCustomCategory]
    func loadAll() throws -> [CachedCustomCategory]
    func replaceSynced(_ categories: [CachedCustomCategory]) async throws
    func upsert(_ category: CachedCustomCategory) async throws
    func renameLocally(id: Int, name: String) async throws
    func removeLocally(id: Int) async throws
    func updateSyncState(id: Int, to state: CustomCategorySyncState) async throws
    func deleteRow(id: Int) async throws
    func nextLocalID() throws -> Int
    func activeCount() throws -> Int
    func hasPendingSyncWork() throws -> Bool
    func remap(from oldID: Int, to newID: Int) async throws
    func remapForServerCreate(
        from oldID: Int,
        to newID: Int,
        originalState: CustomCategorySyncState
    ) async throws
    func finalizeServerDelete(id: Int) async throws
    func referencedCategoryIDs() throws -> Set<Int>
    func pendingPushCategoryIDs() throws -> Set<Int>
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

    /// 상태 판정·이름·스냅샷·상태 전이가 한 트랜잭션이어야 한다. 갈라지면 이름만 바뀌고
    /// sync_state가 synced로 남아, 다음 refresh가 서버 이름으로 덮으며 스냅샷과 어긋난다.
    func renameLocally(id: Int, name: String) async throws {
        try await database.write { @Sendable db in
            guard let state = try Self.editableSyncState(db, id: id) else {
                throw CustomCategoryCacheError.categoryNotFound(id: id)
            }
            try db.execute(
                sql: "UPDATE custom_category SET name = ? WHERE id = ?",
                arguments: [name, id]
            )
            try db.execute(
                sql: "UPDATE transaction_entry SET category_snapshot = ? WHERE category_id = ?",
                arguments: [name, id]
            )
            // pendingCreate는 서버에 없으므로 PUT 대상으로 올리지 않는다.
            if state == .synced {
                try db.execute(
                    sql: "UPDATE custom_category SET sync_state = ? WHERE id = ?",
                    arguments: [CustomCategorySyncState.pendingUpdate.rawValue, id]
                )
            }
        }
    }

    /// 참조 판정과 삭제가 갈라지면, 그 사이 저장된 내역이 사라진 카테고리를 참조해
    /// 음수 category_id인 채 영구 pendingPush로 고착된다.
    func removeLocally(id: Int) async throws {
        try await database.write { @Sendable db in
            guard let state = try Self.editableSyncState(db, id: id) else {
                throw CustomCategoryCacheError.categoryNotFound(id: id)
            }
            let isReferenced = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM transaction_entry WHERE category_id = ?)",
                arguments: [id]
            ) ?? false
            // 서버에 올라간 적 없고 참조도 없으면 보존할 이유가 없다.
            if state == .pendingCreate, !isReferenced {
                try db.execute(sql: "DELETE FROM custom_category WHERE id = ?", arguments: [id])
            } else {
                try db.execute(
                    sql: "UPDATE custom_category SET sync_state = ? WHERE id = ?",
                    arguments: [CustomCategorySyncState.pendingDelete.rawValue, id]
                )
            }
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

    func hasPendingSyncWork() throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM custom_category WHERE sync_state IN (?, ?, ?))",
                arguments: [
                    CustomCategorySyncState.pendingCreate.rawValue,
                    CustomCategorySyncState.pendingUpdate.rawValue,
                    CustomCategorySyncState.pendingDelete.rawValue
                ]
            ) ?? false
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

    func remapForServerCreate(
        from oldID: Int,
        to newID: Int,
        originalState: CustomCategorySyncState
    ) async throws {
        try await database.write { @Sendable db in
            let nextState = originalState == .pendingCreate ? .synced : originalState
            try db.execute(
                sql: "UPDATE custom_category SET id = ?, sync_state = ? WHERE id = ?",
                arguments: [newID, nextState.rawValue, oldID]
            )
            guard db.changesCount == 1 else {
                throw CustomCategoryCacheError.remapSourceMissing(id: oldID)
            }
            try db.execute(
                sql: "UPDATE transaction_entry SET category_id = ? WHERE category_id = ?",
                arguments: [newID, oldID]
            )
        }
    }

    func finalizeServerDelete(id: Int) async throws {
        try await database.write { @Sendable db in
            let isReferenced = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM transaction_entry WHERE category_id = ?)",
                arguments: [id]
            ) ?? false
            if isReferenced {
                try db.execute(
                    sql: "UPDATE custom_category SET sync_state = ? WHERE id = ?",
                    arguments: [CustomCategorySyncState.deleted.rawValue, id]
                )
            } else {
                try db.execute(sql: "DELETE FROM custom_category WHERE id = ?", arguments: [id])
            }
        }
    }

    func referencedCategoryIDs() throws -> Set<Int> {
        try database.read { db in
            try Set(Int.fetchAll(db, sql: "SELECT DISTINCT category_id FROM transaction_entry"))
        }
    }

    /// 아직 서버로 올라가지 않은 내역이 참조하는 카테고리. 이 카테고리를 먼저 서버에서 지우면
    /// 그 내역이 push될 때 서버가 사용 불가 카테고리로 보고 영영 거부한다(D3 ④의 순서 근거).
    func pendingPushCategoryIDs() throws -> Set<Int> {
        try database.read { db in
            try Set(
                Int.fetchAll(
                    db,
                    sql: "SELECT DISTINCT category_id FROM transaction_entry WHERE sync_state = ?",
                    arguments: [SyncState.pendingPush.rawValue]
                )
            )
        }
    }

    func clearAll() async throws {
        try await database.write { @Sendable db in
            try db.execute(sql: "DELETE FROM custom_category")
        }
    }
}

extension CustomCategoryCaching {
    func hasPendingSyncWork() throws -> Bool {
        try loadAll().contains {
            [.pendingCreate, .pendingUpdate, .pendingDelete].contains($0.syncState)
        }
    }

    func remapForServerCreate(
        from oldID: Int,
        to newID: Int,
        originalState: CustomCategorySyncState
    ) async throws {
        try await remap(from: oldID, to: newID)
        if originalState == .pendingCreate {
            try await updateSyncState(id: newID, to: .synced)
        }
    }

    func finalizeServerDelete(id: Int) async throws {
        if try referencedCategoryIDs().contains(id) {
            try await updateSyncState(id: id, to: .deleted)
        } else {
            try await deleteRow(id: id)
        }
    }
}

private extension CustomCategoryCacheRepository {
    /// 편집·삭제 대상이 되는 행의 상태만 돌려준다. 이미 지워진 행(pendingDelete·deleted)은
    /// 목록에 없으므로 대상이 아니며, nil은 호출부에서 명시적 실패로 바뀐다.
    static func editableSyncState(_ db: Database, id: Int) throws -> CustomCategorySyncState? {
        guard
            let raw = try String.fetchOne(
                db,
                sql: "SELECT sync_state FROM custom_category WHERE id = ?",
                arguments: [id]
            ),
            let state = CustomCategorySyncState(rawValue: raw),
            state != .pendingDelete, state != .deleted
        else {
            return nil
        }
        return state
    }

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
