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
    /// 서버 계약과 같은 값 공간이다 — 미정렬 1000, 재정렬 1001+index.
    var sortOrder: Int = 1000
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
    func nextLocalID(reserving reservedIDs: Set<Int>) throws -> Int
    func activeCount() throws -> Int
    func hasPendingSyncWork() throws -> Bool
    func applyOrder(_ orderedIDs: [Int], type: CatalogTransactionType) async throws
    func applySortOrders(_ pairs: [(id: Int, sortOrder: Int)], type: CatalogTransactionType) async throws
    func pendingOrderTypes() throws -> Set<CatalogTransactionType>
    func remap(from oldID: Int, to newID: Int) async throws
    func remapForServerCreate(
        from oldID: Int,
        to newID: Int,
        originalState: CustomCategorySyncState
    ) async throws
    func finalizeServerDelete(id: Int) async throws
    func referencedCategoryIDs() throws -> Set<Int>
    func pendingPushCategoryIDs() throws -> Set<Int>
    func resetForAccountSwitch(reserving reservedIDs: Set<Int>) async throws -> [Int: Int]
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
                SELECT id, transaction_type, name, sync_state, sort_order
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
                sql: "SELECT id, transaction_type, name, sync_state, sort_order FROM custom_category ORDER BY id DESC"
            ).map(Self.cached(from:))
        }
    }

    func replaceSynced(_ categories: [CachedCustomCategory]) async throws {
        let stored = categories.map { StoredCustomCategory(cached: $0) }
        try await database.write { @Sendable db in
            // 아직 서버로 못 올린 순서는 서버 값보다 우선한다 — 방금 한 드래그가 refresh에
            // 되돌려지면 안 된다. 트랜잭션 밖에서 읽어 넘기면 그 사이의 쓰기와 갈라진다.
            let queuedTypes = try Set(
                String.fetchAll(db, sql: "SELECT transaction_type FROM custom_category_order_queue")
            )
            let localSortOrders = try Row.fetchAll(db, sql: "SELECT id, sort_order FROM custom_category")
                .reduce(into: [Int: Int]()) { result, row in result[row["id"]] = row["sort_order"] }
            // synced 행만 지운다 — pending*·deleted 행은 아직 서버에 반영되지 않은 로컬 작업이다.
            try db.execute(
                sql: "DELETE FROM custom_category WHERE sync_state = ?",
                arguments: [CustomCategorySyncState.synced.rawValue]
            )
            for category in stored {
                let sortOrder = queuedTypes.contains(category.transactionType)
                    ? localSortOrders[category.id] ?? category.sortOrder
                    : category.sortOrder
                try db.execute(
                    sql: """
                    INSERT INTO custom_category (id, transaction_type, name, sync_state, sort_order)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        category.id, category.transactionType, category.name, category.syncState, sortOrder
                    ]
                )
            }
        }
    }

    func upsert(_ category: CachedCustomCategory) async throws {
        let stored = StoredCustomCategory(cached: category)
        try await database.write { @Sendable db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO custom_category (id, transaction_type, name, sync_state, sort_order)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    stored.id, stored.transactionType, stored.name, stored.syncState, stored.sortOrder
                ]
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
    /// 서버 재매핑을 마친 행은 옛 음수 id를 테이블에 남기지 않는다. 저장된 id만 보고 다음 id를
    /// 고르면 그 옛 id가 재사용되고, 화면이 들고 있던 `idRemap`이 새 카테고리를 옛 서버 id로
    /// 해석해 다른 카테고리에 조용히 붙는다. 재매핑에 쓰인 id도 함께 피한다.
    func nextLocalID(reserving reservedIDs: Set<Int>) throws -> Int {
        try database.read { db in
            let minimumID = try Int.fetchOne(db, sql: "SELECT MIN(id) FROM custom_category") ?? 0
            return min(minimumID, reservedIDs.min() ?? 0, 0) - 1
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

    /// 순서 큐만 있고 sync_state pending이 없는 상태를 놓치면 push가 조기 반환해
    /// 순서가 영영 올라가지 않는다.
    func hasPendingSyncWork() throws -> Bool {
        try database.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                SELECT EXISTS(SELECT 1 FROM custom_category WHERE sync_state IN (?, ?, ?))
                    OR EXISTS(SELECT 1 FROM custom_category_order_queue)
                """,
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

    /// 새 계정에는 이전 서버 id를 재사용할 수 없으므로 필요한 행을 모두 새 음수 id로 옮긴다.
    /// 행·내역 참조·삭제 필터가 갈라지면 일부 내역만 옛 계정 category_id를 가리킬 수 있어
    /// 반드시 하나의 write 트랜잭션에서 끝낸다.
    func resetForAccountSwitch(reserving reservedIDs: Set<Int>) async throws -> [Int: Int] {
        try await database.write { @Sendable db in
            let referencedIDs = try Set(
                Int.fetchAll(db, sql: "SELECT DISTINCT category_id FROM transaction_entry")
            )
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, transaction_type, name, sync_state, sort_order
                FROM custom_category ORDER BY id DESC
                """
            ).map(Self.cached(from:))
            let minimumStoredID = rows.map(\.id).min() ?? 0
            let minimumReservedID = reservedIDs.min() ?? 0
            var nextID = min(minimumStoredID, minimumReservedID, 0) - 1
            var remap: [Int: Int] = [:]
            var recreatedTypes: Set<String> = []

            for row in rows {
                let isDeleted = [.pendingDelete, .deleted].contains(row.syncState)
                guard !isDeleted || referencedIDs.contains(row.id) else {
                    try db.execute(sql: "DELETE FROM custom_category WHERE id = ?", arguments: [row.id])
                    // 행만 지우고 remap을 비워 두면 화면이 들고 있던 옛 양수 id가 그대로 해석되고,
                    // 새 계정에 같은 id의 다른 카테고리가 있으면 조용히 그쪽에 붙는다. 살아 있지 않은
                    // 음수 id로 묶어 두면 내역 저장 검증이 "음수는 살아 있는 행 필수"로 명시적으로 막는다.
                    remap[row.id] = nextID
                    nextID -= 1
                    continue
                }

                let newID = nextID
                nextID -= 1
                let newState: CustomCategorySyncState = isDeleted ? .pendingDelete : .pendingCreate
                try db.execute(
                    sql: "UPDATE custom_category SET id = ?, sync_state = ? WHERE id = ?",
                    arguments: [newID, newState.rawValue, row.id]
                )
                guard db.changesCount == 1 else {
                    throw CustomCategoryCacheError.remapSourceMissing(id: row.id)
                }
                try db.execute(
                    sql: "UPDATE transaction_entry SET category_id = ? WHERE category_id = ?",
                    arguments: [newID, row.id]
                )
                remap[row.id] = newID
                // 큐에 넣지 않으면 새 계정에 카테고리는 다시 만들어지되 순서만 서버
                // 기본값으로 남아 기기 간에 갈린다.
                if !isDeleted {
                    recreatedTypes.insert(row.transactionType.rawValue)
                }
            }
            for rawType in recreatedTypes {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO custom_category_order_queue (transaction_type) VALUES (?)",
                    arguments: [rawType]
                )
            }
            return remap
        }
    }

    func clearAll() async throws {
        try await database.write { @Sendable db in
            try db.execute(sql: "DELETE FROM custom_category")
            try db.execute(sql: "DELETE FROM custom_category_order_queue")
        }
    }
}

// MARK: - 순서 재배치

extension CustomCategoryCacheRepository {
    /// 순서 적용과 전송 표시가 갈라지면 순서만 바뀌고 전송 표시가 없거나 그 반대가 된다.
    func applyOrder(_ orderedIDs: [Int], type: CatalogTransactionType) async throws {
        let rawType = type.rawValue
        try await database.write { @Sendable db in
            for (index, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE custom_category SET sort_order = ? WHERE id = ?",
                    arguments: [Self.reorderedSortOrderBase + index, id]
                )
            }
            try db.execute(
                sql: "INSERT OR REPLACE INTO custom_category_order_queue (transaction_type) VALUES (?)",
                arguments: [rawType]
            )
        }
    }

    /// 서버 응답 전체가 아니라 순서만 받는다 — 행을 통째로 저장하면 pendingUpdate 행의
    /// 로컬 이름·상태가 서버 값에 덮인다. 로컬에 없는 id는 무시한다(수렴은 refresh의 일이다).
    func applySortOrders(_ pairs: [(id: Int, sortOrder: Int)], type: CatalogTransactionType) async throws {
        let rawType = type.rawValue
        try await database.write { @Sendable db in
            for pair in pairs {
                try db.execute(
                    sql: "UPDATE custom_category SET sort_order = ? WHERE id = ?",
                    arguments: [pair.sortOrder, pair.id]
                )
            }
            try db.execute(
                sql: "DELETE FROM custom_category_order_queue WHERE transaction_type = ?",
                arguments: [rawType]
            )
        }
    }

    func pendingOrderTypes() throws -> Set<CatalogTransactionType> {
        try database.read { db in
            try Set(
                String.fetchAll(db, sql: "SELECT transaction_type FROM custom_category_order_queue")
                    .map { raw in
                        guard let type = CatalogTransactionType(rawValue: raw) else {
                            throw CustomCategoryCacheError.invalidColumnValue(
                                column: "transaction_type",
                                value: raw
                            )
                        }
                        return type
                    }
            )
        }
    }
}

extension CustomCategoryCaching {
    /// 큐가 별도 테이블이라 loadAll()만으로는 존재를 알 방법이 없다 — pendingOrderTypes()가 그 통로다.
    func hasPendingSyncWork() throws -> Bool {
        let hasPendingState = try loadAll().contains {
            [.pendingCreate, .pendingUpdate, .pendingDelete].contains($0.syncState)
        }
        return try hasPendingState || pendingOrderTypes().isEmpty == false
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

    /// 서버가 재정렬 대상에 주는 값과 같다(`CatalogService`: 1001 + index).
    static let reorderedSortOrderBase = 1001

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
            syncState: syncState,
            sortOrder: row["sort_order"]
        )
    }
}

private struct StoredCustomCategory {
    let id: Int
    let transactionType: String
    let name: String
    let syncState: String
    let sortOrder: Int

    init(cached: CachedCustomCategory) {
        id = cached.id
        transactionType = cached.transactionType.rawValue
        name = cached.name
        syncState = cached.syncState.rawValue
        sortOrder = cached.sortOrder
    }
}
