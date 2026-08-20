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

        #expect(try repository.nextLocalID() == -1)

        try await repository.upsert(CachedCustomCategory(id: 7, transactionType: .expense, name: "장보기"))
        #expect(try repository.nextLocalID() == -1)

        try await repository.upsert(
            CachedCustomCategory(id: -3, transactionType: .expense, name: "로컬", syncState: .pendingCreate)
        )
        #expect(try repository.nextLocalID() == -4)
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
