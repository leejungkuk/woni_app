//
//  CustomCategoryCacheRepositoryTests.swift
//  woni_appTests
//

import Foundation
import GRDB
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct CustomCategoryCacheRepositoryTests {
    @Test("v9에서 v10으로 마이그레이션하면 기존 행 전부를 synced로 승격한다")
    func migrationFromV9ToV10PromotesExistingRowsToSynced() throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue, upTo: "v9")
        try dbQueue.write { db in
            for (id, type, name) in [(1, "EXPENSE", "장보기"), (2, "INCOME", "용돈")] {
                try db.execute(
                    sql: "INSERT INTO custom_category (id, transaction_type, name) VALUES (?, ?, ?)",
                    arguments: [id, type, name]
                )
            }
        }

        let database = try AppDatabase(dbQueue)

        let states = try database.read { db in
            try String.fetchAll(db, sql: "SELECT sync_state FROM custom_category ORDER BY id")
        }
        #expect(states == ["synced", "synced"])
    }

    @Test("CHECK 제약은 허용되지 않는 sync_state 문자열 삽입을 거부한다")
    func checkConstraintRejectsUnknownSyncState() throws {
        let database = try AppDatabase.inMemory()

        try database.write { db in
            #expect(throws: (any Error).self) {
                try db.execute(
                    sql: """
                    INSERT INTO custom_category (id, transaction_type, name, sync_state)
                    VALUES (1, 'EXPENSE', '장보기', 'invalid')
                    """
                )
            }
        }
    }

    @Test("nextLocalID는 빈 테이블·양수 id만 있을 때 -1, 최소 -3이 있으면 -4를 돌려준다")
    func nextLocalIDStartsAtMinusOneAndDecreases() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)

        #expect(try repository.nextLocalID(reserving: []) == -1)

        try await repository.upsert(CachedCustomCategory(id: 7, transactionType: .expense, name: "장보기"))
        #expect(try repository.nextLocalID(reserving: []) == -1)

        try await repository.upsert(
            CachedCustomCategory(id: -3, transactionType: .expense, name: "로컬", syncState: .pendingCreate)
        )
        #expect(try repository.nextLocalID(reserving: []) == -4)
    }

    @Test("load는 pendingDelete·deleted를 제외하고 loadAll은 전 상태를 포함한다")
    func loadHidesDeleteStatesWhileLoadAllKeepsThem() async throws {
        let repository = try await Self.seededRepository()

        let loaded = try repository.load(for: .expense)
        #expect(loaded.map(\.id) == [2, 1, -1])
        #expect(loaded.map(\.syncState) == [.pendingUpdate, .synced, .pendingCreate])
        #expect(try Set(repository.loadAll().map(\.id)) == [-1, 1, 2, 3, 4, 5])
    }

    @Test("activeCount는 synced·pendingCreate·pendingUpdate만 세고 pendingDelete·deleted는 제외한다")
    func activeCountExcludesDeleteStates() async throws {
        let repository = try await Self.seededRepository()

        #expect(try repository.activeCount() == 4)
    }

    @Test("replaceSynced는 synced 행만 교체하고 pending·deleted 행은 보존한다")
    func replaceSyncedKeepsPendingAndDeletedRows() async throws {
        let repository = try await Self.seededRepository()

        try await repository.replaceSynced([
            CachedCustomCategory(id: 10, transactionType: .expense, name: "서버 최신")
        ])

        #expect(try Set(repository.loadAll().map(\.id)) == [-1, 2, 3, 4, 10])
    }

    @Test("remap은 카테고리 행 id와 transaction_entry.category_id를 함께 바꾼다")
    func remapRewritesCategoryRowAndEntryReferencesTogether() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await repository.upsert(
            CachedCustomCategory(id: -2, transactionType: .expense, name: "로컬", syncState: .pendingCreate)
        )
        try await database.write { @Sendable db in
            try Self.insertEntry(db, clientEntryID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", categoryID: -2)
            try Self.insertEntry(db, clientEntryID: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", categoryID: 9)
        }

        try await repository.remap(from: -2, to: 501)

        #expect(try repository.loadAll().map(\.id) == [501])
        let categoryIDs = try await database.read { @Sendable db in
            try Int.fetchAll(db, sql: "SELECT category_id FROM transaction_entry ORDER BY id")
        }
        #expect(categoryIDs == [501, 9])
    }

    @Test("remap은 원본 카테고리가 없으면 던지고 내역 참조를 건드리지 않는다")
    func remapThrowsAndKeepsReferencesWhenSourceMissing() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await database.write { @Sendable db in
            try Self.insertEntry(db, clientEntryID: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", categoryID: -7)
        }

        await #expect(throws: CustomCategoryCacheError.remapSourceMissing(id: -7)) {
            try await repository.remap(from: -7, to: 601)
        }

        let categoryIDs = try await database.read { @Sendable db in
            try Int.fetchAll(db, sql: "SELECT category_id FROM transaction_entry")
        }
        #expect(categoryIDs == [-7])
    }

    @Test("removeLocally는 참조 없는 pendingCreate만 물리 삭제하고 나머지는 pendingDelete로 남긴다")
    func removeLocallyBranchesOnEntryReference() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await repository.upsert(
            CachedCustomCategory(id: -1, transactionType: .expense, name: "미참조", syncState: .pendingCreate)
        )
        try await repository.upsert(
            CachedCustomCategory(id: -2, transactionType: .expense, name: "참조됨", syncState: .pendingCreate)
        )
        try await repository.upsert(
            CachedCustomCategory(id: 5, transactionType: .expense, name: "서버", syncState: .synced)
        )
        try await database.write { @Sendable db in
            try Self.insertEntry(db, clientEntryID: "10000000-0000-0000-0000-000000000001", categoryID: -2)
        }

        try await repository.removeLocally(id: -1)
        try await repository.removeLocally(id: -2)
        try await repository.removeLocally(id: 5)

        let rows = try repository.loadAll()
        // 서버에 올라간 적 없고 참조도 없으면 보존할 이유가 없다.
        #expect(rows.contains { $0.id == -1 } == false)
        // 참조가 있으면 deleted가 아니라 pendingDelete여야 큐 ①이 서버에 만들고 ④가 지운다.
        #expect(rows.first { $0.id == -2 }?.syncState == .pendingDelete)
        #expect(rows.first { $0.id == 5 }?.syncState == .pendingDelete)
    }

    @Test("renameLocally는 synced만 pendingUpdate로 올리고 pendingCreate는 상태를 유지한다")
    func renameLocallyPromotesOnlySyncedRows() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await repository.upsert(
            CachedCustomCategory(id: -1, transactionType: .expense, name: "로컬", syncState: .pendingCreate)
        )
        try await repository.upsert(
            CachedCustomCategory(id: 5, transactionType: .expense, name: "서버", syncState: .synced)
        )
        try await database.write { @Sendable db in
            try Self.insertEntry(db, clientEntryID: "20000000-0000-0000-0000-000000000001", categoryID: -1)
            try Self.insertEntry(db, clientEntryID: "20000000-0000-0000-0000-000000000002", categoryID: 5)
        }

        try await repository.renameLocally(id: -1, name: "로컬 새 이름")
        try await repository.renameLocally(id: 5, name: "서버 새 이름")

        let rows = try repository.loadAll()
        // 서버에 없는 행을 pendingUpdate로 올리면 PUT 대상이 돼 404가 난다.
        #expect(rows.first { $0.id == -1 }?.syncState == .pendingCreate)
        #expect(rows.first { $0.id == 5 }?.syncState == .pendingUpdate)
        let snapshots = try await database.read { @Sendable db in
            try String.fetchAll(db, sql: "SELECT category_snapshot FROM transaction_entry ORDER BY category_id")
        }
        #expect(snapshots == ["로컬 새 이름", "서버 새 이름"])
    }

    @Test("referencedCategoryIDs는 내역이 참조하는 category_id를 중복 없이 돌려준다")
    func referencedCategoryIDsReturnsDistinctSet() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await database.write { @Sendable db in
            try Self.insertEntry(db, clientEntryID: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC", categoryID: 7)
            try Self.insertEntry(db, clientEntryID: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", categoryID: 7)
            try Self.insertEntry(db, clientEntryID: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE", categoryID: -1)
        }

        #expect(try repository.referencedCategoryIDs() == [7, -1])
    }

    @Test("pendingPushCategoryIDs는 아직 안 올라간 내역이 쓰는 카테고리만 돌려준다")
    func pendingPushCategoryIDsExcludesSyncedEntries() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await database.write { @Sendable db in
            try Self.insertEntry(db, clientEntryID: "30000000-0000-0000-0000-000000000001", categoryID: 5)
            try Self.insertEntry(db, clientEntryID: "30000000-0000-0000-0000-000000000002", categoryID: 6)
            // 이미 서버로 올라간 내역은 카테고리 삭제를 막을 이유가 없다.
            try db.execute(
                sql: "UPDATE transaction_entry SET sync_state = ? WHERE category_id = ?",
                arguments: [SyncState.synced.rawValue, 6]
            )
        }

        #expect(try repository.pendingPushCategoryIDs() == [5])
        #expect(try repository.referencedCategoryIDs() == [5, 6])
    }

    @Test("계정 전환은 살아있는 행과 참조된 삭제 행만 새 로컬 id로 원자 재배정한다")
    func accountSwitchResetRemapsOnlyRowsNeededByNewAccount() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        let seed = [
            CachedCustomCategory(id: 501, transactionType: .expense, name: "동기화", syncState: .synced),
            CachedCustomCategory(id: -1, transactionType: .income, name: "생성 대기", syncState: .pendingCreate),
            CachedCustomCategory(id: 502, transactionType: .expense, name: "수정 대기", syncState: .pendingUpdate),
            CachedCustomCategory(id: 503, transactionType: .expense, name: "참조 삭제", syncState: .pendingDelete),
            CachedCustomCategory(id: 504, transactionType: .expense, name: "참조 삭제됨", syncState: .deleted),
            CachedCustomCategory(id: 505, transactionType: .expense, name: "미참조 삭제", syncState: .pendingDelete),
            CachedCustomCategory(id: 506, transactionType: .expense, name: "미참조 삭제됨", syncState: .deleted)
        ]
        for category in seed {
            try await repository.upsert(category)
        }
        try await database.write { @Sendable db in
            try Self.insertEntry(db, clientEntryID: "60000000-0000-0000-0000-000000000001", categoryID: 501)
            try Self.insertEntry(db, clientEntryID: "60000000-0000-0000-0000-000000000002", categoryID: 503)
            try Self.insertEntry(db, clientEntryID: "60000000-0000-0000-0000-000000000003", categoryID: 504)
        }

        let remap = try await repository.resetForAccountSwitch(reserving: [-100])

        // 물리 삭제한 행도 remap에 남긴다 — 빠뜨리면 화면이 든 옛 양수 id가 그대로 해석돼
        // 새 계정의 같은 id 카테고리로 조용히 붙는다. 대상은 행이 없는 음수라 내역 저장이 막힌다.
        #expect(Set(remap.keys) == [501, -1, 502, 503, 504, 505, 506])
        #expect(Set(remap.values).count == 7)
        #expect(remap.values.allSatisfy { $0 < -100 })
        let rows = try repository.loadAll()
        #expect(rows.count == 5)
        #expect(rows.contains { $0.id == remap[505] } == false)
        #expect(rows.contains { $0.id == remap[506] } == false)
        #expect(rows.first { $0.name == "동기화" }?.syncState == .pendingCreate)
        #expect(rows.first { $0.name == "생성 대기" }?.syncState == .pendingCreate)
        #expect(rows.first { $0.name == "수정 대기" }?.syncState == .pendingCreate)
        #expect(rows.first { $0.name == "참조 삭제" }?.syncState == .pendingDelete)
        #expect(rows.first { $0.name == "참조 삭제됨" }?.syncState == .pendingDelete)
        #expect(rows.contains { $0.name == "미참조 삭제" } == false)
        #expect(rows.contains { $0.name == "미참조 삭제됨" } == false)
        #expect(try repository.referencedCategoryIDs() == Set([501, 503, 504].compactMap { remap[$0] }))
    }

    @Test("remapForServerCreate는 pendingCreate만 synced로 올리고 pendingDelete는 상태를 지킨다")
    func remapForServerCreateKeepsDeleteIntent() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await repository.upsert(
            CachedCustomCategory(id: -1, transactionType: .expense, name: "생성", syncState: .pendingCreate)
        )
        try await repository.upsert(
            CachedCustomCategory(id: -2, transactionType: .expense, name: "삭제 예정", syncState: .pendingDelete)
        )
        try await database.write { @Sendable db in
            try Self.insertEntry(db, clientEntryID: "40000000-0000-0000-0000-000000000001", categoryID: -2)
        }

        try await repository.remapForServerCreate(from: -1, to: 501, originalState: .pendingCreate)
        try await repository.remapForServerCreate(from: -2, to: 502, originalState: .pendingDelete)

        let rows = try repository.loadAll()
        #expect(rows.first { $0.id == 501 }?.syncState == .synced)
        // 상태를 synced로 올려버리면 큐 ④가 이 행을 다시 지우지 못한다.
        #expect(rows.first { $0.id == 502 }?.syncState == .pendingDelete)
        #expect(try repository.referencedCategoryIDs() == [502])
    }

    @Test("finalizeServerDelete는 내역이 참조하면 deleted로 남기고 아니면 행을 지운다")
    func finalizeServerDeleteBranchesOnReference() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await repository.upsert(
            CachedCustomCategory(id: 7, transactionType: .expense, name: "참조됨", syncState: .pendingDelete)
        )
        try await repository.upsert(
            CachedCustomCategory(id: 8, transactionType: .expense, name: "미참조", syncState: .pendingDelete)
        )
        try await database.write { @Sendable db in
            try Self.insertEntry(db, clientEntryID: "50000000-0000-0000-0000-000000000001", categoryID: 7)
        }

        try await repository.finalizeServerDelete(id: 7)
        try await repository.finalizeServerDelete(id: 8)

        let rows = try repository.loadAll()
        // 내역이 이름을 계속 보여줘야 하므로 행만 남긴다(E4).
        #expect(rows.first { $0.id == 7 }?.syncState == .deleted)
        #expect(rows.contains { $0.id == 8 } == false)
    }

    @Test("hasPendingSyncWork는 pending 상태가 하나라도 있을 때만 참이다")
    func hasPendingSyncWorkReflectsQueueState() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await repository.upsert(
            CachedCustomCategory(id: 1, transactionType: .expense, name: "동기화됨", syncState: .synced)
        )
        #expect(try repository.hasPendingSyncWork() == false)

        try await repository.upsert(
            CachedCustomCategory(id: 2, transactionType: .expense, name: "삭제 대기", syncState: .pendingDelete)
        )
        #expect(try repository.hasPendingSyncWork())
    }

    @Test("upsert는 같은 id를 교체하고 renameLocally·updateSyncState·deleteRow는 해당 행만 바꾼다")
    func singleRowMutatorsAffectOnlyTargetRow() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await repository.upsert(CachedCustomCategory(id: 1, transactionType: .expense, name: "장보기"))
        try await repository.upsert(CachedCustomCategory(id: 2, transactionType: .expense, name: "야식"))

        try await repository.upsert(CachedCustomCategory(id: 1, transactionType: .expense, name: "마트"))
        // renameLocally는 synced 행을 이름 변경과 같은 트랜잭션에서 pendingUpdate로 올린다.
        try await repository.renameLocally(id: 2, name: "간식")

        let rows = try repository.loadAll()
        #expect(rows.map(\.name).sorted() == ["간식", "마트"])
        #expect(rows.first { $0.id == 2 }?.syncState == .pendingUpdate)
        #expect(rows.first { $0.id == 1 }?.syncState == .synced)

        try await repository.deleteRow(id: 1)
        #expect(try repository.loadAll().map(\.id) == [2])
    }
}

private extension CustomCategoryCacheRepositoryTests {
    /// 5개 상태 전부 + 타입 분리 케이스를 한 번에 시드한다.
    static func seededRepository() async throws -> CustomCategoryCacheRepository {
        let repository = try CustomCategoryCacheRepository(database: AppDatabase.inMemory())
        let seed = [
            CachedCustomCategory(id: 1, transactionType: .expense, name: "동기화", syncState: .synced),
            CachedCustomCategory(id: -1, transactionType: .expense, name: "생성 대기", syncState: .pendingCreate),
            CachedCustomCategory(id: 2, transactionType: .expense, name: "수정 대기", syncState: .pendingUpdate),
            CachedCustomCategory(id: 3, transactionType: .expense, name: "삭제 대기", syncState: .pendingDelete),
            CachedCustomCategory(id: 4, transactionType: .expense, name: "삭제됨", syncState: .deleted),
            CachedCustomCategory(id: 5, transactionType: .income, name: "수입", syncState: .synced)
        ]
        for category in seed {
            try await repository.upsert(category)
        }
        return repository
    }

    static func insertEntry(_ db: Database, clientEntryID: String, categoryID: Int) throws {
        try db.execute(
            sql: """
            INSERT INTO transaction_entry (
                client_entry_id, amount, currency_code, category_id, asset_id,
                transaction_type, transaction_date, pending, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                clientEntryID, "100", "KRW", categoryID, 1,
                "EXPENSE", "2026-08-20", 0,
                "2026-08-20T00:00:00Z", "2026-08-20T00:00:00Z"
            ]
        )
    }
}

extension CustomCategoryCacheRepositoryTests {
    /// 서버 재매핑을 마친 행은 옛 음수 id를 테이블에 남기지 않는다. 저장된 id만 보고 다음 id를
    /// 고르면 그 id가 재사용되고, 새로 만든 카테고리를 `resolvedID`가 옛 서버 id로 해석해
    /// 사용자가 탭한 것과 다른 카테고리가 선택·저장된다.
    @Test("서버 재매핑에 쓰인 옛 로컬 id는 새 카테고리에 다시 배정되지 않는다")
    func nextLocalIDSkipsIDsHeldByRemap() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        try await repository.upsert(CachedCustomCategory(
            id: -1,
            transactionType: .expense,
            name: "로컬",
            syncState: .pendingCreate
        ))
        try await repository.remapForServerCreate(from: -1, to: 700, originalState: .pendingCreate)

        let store = try CustomCategoryStore(
            service: CreatingCustomCategoryServiceStub(createdID: 900),
            cache: repository,
            authProvider: FakeAuthService()
        )
        store.recordRemap(from: -1, to: 700)

        let createdID = try await store.create(name: "새것", type: .expense)

        // 옛 로컬 id(-1)를 다시 쓰면 resolvedID가 새 카테고리를 옛 서버 id 700으로 해석한다.
        #expect(createdID != -1)
        #expect(store.resolvedID(for: createdID) == createdID)
    }

    /// tombstone은 행이 없어 `MIN(id)` 스캔에 걸리지 않는다. 예약에서 `idRemap`의 값을 빼면
    /// 그 id가 다음 카테고리에 그대로 배정되고, 화면이 들고 있던 옛 id가 새 카테고리로 해석된다.
    @Test("계정 전환이 만든 tombstone id는 다음에 만든 카테고리에 배정되지 않는다")
    func createAfterAccountSwitchSkipsTombstoneIDs() async throws {
        let database = try AppDatabase.inMemory()
        let repository = CustomCategoryCacheRepository(database: database)
        // 내역이 참조하지 않는 삭제 행 — 계정 전환에서 물리 삭제되고 tombstone만 남는다.
        try await repository.upsert(CachedCustomCategory(
            id: 501,
            transactionType: .expense,
            name: "미참조 삭제",
            syncState: .pendingDelete
        ))
        let store = try CustomCategoryStore(
            service: CreatingCustomCategoryServiceStub(createdID: 900),
            cache: repository,
            authProvider: FakeAuthService()
        )

        try await store.resetForAccountSwitch()
        let tombstone = store.resolvedID(for: 501)
        #expect(tombstone < 0)
        #expect(try repository.loadAll().isEmpty)

        let createdID = try await store.create(name: "새것", type: .expense)

        #expect(createdID != tombstone)
        // 로그인 직전 화면이 들고 있던 501이 방금 만든 카테고리로 해석되면 안 된다.
        #expect(store.resolvedID(for: 501) != createdID)
    }
}

// MARK: - 순서(sort_order)와 순서 전송 큐

extension CustomCategoryCacheRepositoryTests {
    @Test("v10에서 v11로 마이그레이션하면 기존 행에 sort_order 1000이 붙고 순서 큐 테이블이 생긴다")
    func migrationFromV10ToV11AddsUnorderedSortOrderAndQueueTable() throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue, upTo: "v10")
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO custom_category (id, transaction_type, name) VALUES (?, ?, ?)",
                arguments: [1, "EXPENSE", "장보기"]
            )
        }

        let database = try AppDatabase(dbQueue)

        try database.read { db in
            // 서버의 미정렬 값과 같아야 마이그레이션만으로 순서가 바뀌지 않는다.
            let sortOrders = try Int.fetchAll(db, sql: "SELECT sort_order FROM custom_category")
            #expect(sortOrders == [1000])
            let queueExists = try Bool.fetchOne(
                db,
                sql: """
                SELECT EXISTS(
                    SELECT 1 FROM sqlite_master
                    WHERE type = 'table' AND name = 'custom_category_order_queue'
                )
                """
            ) ?? false
            #expect(queueExists)
        }
    }

    @Test("applyOrder는 전달 순서대로 1001+index를 넣고 그 타입을 순서 큐에 등록한다")
    func applyOrderWritesSequentialSortOrdersAndQueuesType() async throws {
        let repository = try CustomCategoryCacheRepository(database: AppDatabase.inMemory())
        for id in [1, 2, 3] {
            try await repository.upsert(
                CachedCustomCategory(id: id, transactionType: .expense, name: "카테고리 \(id)")
            )
        }

        try await repository.applyOrder([3, 1, 2], type: .expense)

        let rows = try repository.load(for: .expense)
        #expect(rows.first { $0.id == 3 }?.sortOrder == 1001)
        #expect(rows.first { $0.id == 1 }?.sortOrder == 1002)
        #expect(rows.first { $0.id == 2 }?.sortOrder == 1003)
        #expect(try repository.pendingOrderTypes() == [.expense])
    }

    @Test("applySortOrders는 sort_order만 바꾸고 이름·sync_state를 보존하며 큐에서 그 타입을 뺀다")
    func applySortOrdersUpdatesOnlySortOrderAndClearsQueue() async throws {
        let repository = try CustomCategoryCacheRepository(database: AppDatabase.inMemory())
        try await repository.upsert(
            CachedCustomCategory(id: 1, transactionType: .expense, name: "로컬 이름", syncState: .pendingUpdate)
        )
        try await repository.upsert(CachedCustomCategory(id: 2, transactionType: .expense, name: "동기화"))
        try await repository.applyOrder([1, 2], type: .expense)

        try await repository.applySortOrders(
            [(id: 1, sortOrder: 1005), (id: 2, sortOrder: 1006)],
            type: .expense
        )

        let rows = try repository.load(for: .expense)
        #expect(rows.first { $0.id == 1 }?.sortOrder == 1005)
        #expect(rows.first { $0.id == 2 }?.sortOrder == 1006)
        // 서버 응답 전체를 저장하면 pendingUpdate 행의 로컬 이름·상태가 서버 값에 덮여
        // protectedIDs 불변식이 깨진다.
        #expect(rows.first { $0.id == 1 }?.name == "로컬 이름")
        #expect(rows.first { $0.id == 1 }?.syncState == .pendingUpdate)
        #expect(try repository.pendingOrderTypes().isEmpty)
    }

    @Test("applySortOrders는 로컬에 없는 id가 섞여도 던지지 않고 나머지를 적용한다")
    func applySortOrdersIgnoresUnknownIDs() async throws {
        let repository = try CustomCategoryCacheRepository(database: AppDatabase.inMemory())
        try await repository.upsert(CachedCustomCategory(id: 1, transactionType: .expense, name: "장보기"))

        // 다른 기기가 만든 행은 아직 로컬에 없다 — 그 수렴은 refresh()의 일이다.
        try await repository.applySortOrders(
            [(id: 999, sortOrder: 1001), (id: 1, sortOrder: 1002)],
            type: .expense
        )

        #expect(try repository.load(for: .expense).map(\.sortOrder) == [1002])
    }

    @Test("pendingOrderTypes는 타입별 등록·해제를 정확히 반영한다")
    func pendingOrderTypesTracksRegistrationPerType() async throws {
        let repository = try CustomCategoryCacheRepository(database: AppDatabase.inMemory())
        #expect(try repository.pendingOrderTypes().isEmpty)

        try await repository.applyOrder([], type: .expense)
        try await repository.applyOrder([], type: .income)
        #expect(try repository.pendingOrderTypes() == [.expense, .income])

        // 같은 타입을 다시 등록해도 PK 충돌로 실패하지 않는다.
        try await repository.applyOrder([], type: .expense)
        try await repository.applySortOrders([], type: .income)
        #expect(try repository.pendingOrderTypes() == [.expense])
    }

    @Test("순서 큐만 있고 sync_state pending이 없어도 hasPendingSyncWork는 참이다")
    func hasPendingSyncWorkCoversOrderQueueOnlyState() async throws {
        let repository = try CustomCategoryCacheRepository(database: AppDatabase.inMemory())
        try await repository.upsert(CachedCustomCategory(id: 1, transactionType: .expense, name: "동기화"))
        #expect(try repository.hasPendingSyncWork() == false)

        try await repository.applyOrder([1], type: .expense)

        // 놓치면 performPush가 조기 반환해 순서가 영영 올라가지 않는다.
        #expect(try repository.hasPendingSyncWork())
    }

    @Test("extension 기본 구현의 hasPendingSyncWork도 순서 큐만 있는 상태를 잡는다")
    func defaultHasPendingSyncWorkCoversOrderQueueOnlyState() async throws {
        let cache = CustomCategoryCacheStub(categories: [cachedCategory(id: 1, type: .expense, name: "동기화")])
        #expect(try cache.hasPendingSyncWork() == false)

        try await cache.applyOrder([1], type: .expense)

        #expect(try cache.hasPendingSyncWork())
    }

    @Test("replaceSynced는 큐에 있는 타입만 로컬 sort_order를 지키고 나머지는 서버 값을 채택한다")
    func replaceSyncedKeepsLocalOrderOnlyForQueuedTypes() async throws {
        let repository = try CustomCategoryCacheRepository(database: AppDatabase.inMemory())
        try await repository.upsert(CachedCustomCategory(id: 1, transactionType: .expense, name: "지출"))
        try await repository.upsert(CachedCustomCategory(id: 5, transactionType: .income, name: "수입"))
        try await repository.applyOrder([1], type: .expense)

        try await repository.replaceSynced([
            CachedCustomCategory(id: 1, transactionType: .expense, name: "지출", sortOrder: 1500),
            CachedCustomCategory(id: 5, transactionType: .income, name: "수입", sortOrder: 1600)
        ])

        // 방금 한 드래그가 refresh에 되돌려지면 안 된다(R4).
        #expect(try repository.load(for: .expense).map(\.sortOrder) == [1001])
        // 큐에 없는 타입은 다른 기기의 순서가 내려오는 경로다.
        #expect(try repository.load(for: .income).map(\.sortOrder) == [1600])
        #expect(try repository.loadAll().first { $0.id == 5 }?.sortOrder == 1600)
    }

    @Test("계정 전환은 sort_order를 유지하고 재생성 대상이 남은 타입을 순서 큐에 등록한다")
    func accountSwitchKeepsSortOrderAndQueuesRecreatedTypes() async throws {
        let repository = try CustomCategoryCacheRepository(database: AppDatabase.inMemory())
        try await repository.upsert(CachedCustomCategory(id: 1, transactionType: .expense, name: "지출"))
        try await repository.upsert(CachedCustomCategory(id: 2, transactionType: .expense, name: "지출2"))
        try await repository.applyOrder([2, 1], type: .expense)
        try await repository.applySortOrders(
            [(id: 2, sortOrder: 1001), (id: 1, sortOrder: 1002)],
            type: .expense
        )

        let remap = try await repository.resetForAccountSwitch(reserving: [])

        let rows = try repository.load(for: .expense)
        #expect(rows.first { $0.id == remap[2] }?.sortOrder == 1001)
        #expect(rows.first { $0.id == remap[1] }?.sortOrder == 1002)
        // 큐에 넣지 않으면 새 계정에 카테고리는 다시 만들어지되 순서만 서버 기본값(1000)으로
        // 남아 기기 간에 갈린다.
        #expect(try repository.pendingOrderTypes() == [.expense])
    }

    @Test("clearAll은 카테고리 행과 순서 큐를 함께 비운다")
    func clearAllEmptiesOrderQueue() async throws {
        let repository = try CustomCategoryCacheRepository(database: AppDatabase.inMemory())
        try await repository.upsert(CachedCustomCategory(id: 1, transactionType: .expense, name: "지출"))
        try await repository.applyOrder([1], type: .expense)

        try await repository.clearAll()

        #expect(try repository.loadAll().isEmpty)
        #expect(try repository.pendingOrderTypes().isEmpty)
    }
}
