//
//  AppDatabaseTests.swift
//  woni_appTests
//

import Foundation
import GRDB
import Testing
@testable import woni_app

struct AppDatabaseTests {
    @Test("migration은 transaction_entry와 sync bookkeeping 스키마를 생성한다")
    func migrationsCreateTransactionAndSyncSchemas() throws {
        let database = try AppDatabase.inMemory()

        try database.read { db in
            try Self.expectTransactionEntryTable(db)
            try Self.expectTransactionEntryColumns(db)
            try Self.expectTransactionEntryIndexes(db)
            try Self.expectSyncBookkeepingTables(db)
        }
    }

    @Test("v1에서 v2로 마이그레이션하면 기존 행을 보존하고 sync_state 기본값을 적용한다")
    func migrationFromV1ToV2PreservesExistingRows() throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue, upTo: "v1")

        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO transaction_entry (
                    client_entry_id, amount, currency_code, category_id, asset_id,
                    transaction_type, transaction_date, memo, pending, applied_rate,
                    rate_base_date, krw_amount, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
                    "12345678.90123456789", "USD", 10, 20, "EXPENSE", "2026-07-20",
                    nil, 1, nil, nil, nil,
                    "2026-07-20T00:00:00Z", "2026-07-20T00:00:00Z"
                ]
            )
        }

        let database = try AppDatabase(dbQueue)
        let stored: MigratedTransaction = try database.read { db in
            let row = try #require(try Row.fetchOne(
                db,
                sql: "SELECT amount, sync_state FROM transaction_entry WHERE client_entry_id = ?",
                arguments: ["AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"]
            ))
            return try MigratedTransaction(
                count: TransactionEntry.fetchCount(db),
                amount: row["amount"],
                syncState: row["sync_state"]
            )
        }

        #expect(stored.count == 1)
        #expect(stored.amount == "12345678.90123456789")
        #expect(stored.syncState == "pendingPush")

        #expect(throws: (any Error).self) {
            try database.write { db in
                try db.execute(
                    sql: "UPDATE transaction_entry SET sync_state = 'invalid'"
                )
            }
        }
    }

    @Test("v3에서 v4로 마이그레이션하면 exclusion 테이블만 제거하고 고아행을 pending push로 복귀시킨다")
    @MainActor
    func migrationFromV3ToV4DropsExclusionAndRestoresOrphanToPendingPush() async throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue, upTo: "v3")
        let restoredEntryID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let orphanEntryID = try #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))

        try await dbQueue.write { db in
            for (clientEntryID, syncState) in [
                (restoredEntryID, "synced"),
                (orphanEntryID, "pendingPush")
            ] {
                try db.execute(
                    sql: """
                    INSERT INTO transaction_entry (
                        client_entry_id, amount, currency_code, category_id, asset_id,
                        transaction_type, transaction_date, memo, pending, applied_rate,
                        rate_base_date, krw_amount, created_at, updated_at, sync_state
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        clientEntryID.uuidString,
                        "100", "KRW", 1, 1, "EXPENSE", "2026-07-23",
                        nil, 0, nil, nil, nil,
                        "2026-07-23T00:00:00Z", "2026-07-23T00:00:00Z", syncState
                    ]
                )
            }
            try db.execute(
                sql: """
                INSERT INTO sync_push_exclusion (client_entry_id, batch_id)
                VALUES (?, ?)
                """,
                arguments: [orphanEntryID.uuidString, UUID().uuidString]
            )
        }

        let database = try AppDatabase(dbQueue)
        let repository = TransactionRepository(database: database)

        let tableExists = try await database.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                SELECT EXISTS(
                    SELECT 1 FROM sqlite_master
                    WHERE type = 'table' AND name = 'sync_push_exclusion'
                )
                """
            ) ?? false
        }
        let storedEntryIDs = try await database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT client_entry_id FROM transaction_entry ORDER BY id ASC"
            )
        }
        let pendingEntryIDs = try await repository.pendingPushEntries().map(\.clientEntryID)

        #expect(!tableExists)
        #expect(storedEntryIDs == [restoredEntryID.uuidString, orphanEntryID.uuidString])
        #expect(pendingEntryIDs == [orphanEntryID])
    }

    @Test("Decimal은 TEXT 변환 후 손실 없이 라운드트립된다")
    func decimalTextConversionRoundTripsWithoutLoss() throws {
        for text in ["12345678.99", "0.0001", "0"] {
            let decimal = try #require(DecimalTextConversion.decimal(from: text))
            let storedText = DecimalTextConversion.string(from: decimal)
            let roundTripped = try #require(DecimalTextConversion.decimal(from: storedText))

            #expect(storedText == text)
            #expect(roundTripped == decimal)
        }
    }

    @Test("금액/환율 Decimal은 TEXT 컬럼에 insert 후 select해도 손실 없이 복원된다")
    func decimalSurvivesTextColumnRoundTrip() throws {
        let database = try AppDatabase.inMemory()
        let amount = try #require(DecimalTextConversion.decimal(from: "12345678.99"))
        let appliedRate = try #require(DecimalTextConversion.decimal(from: "1234.5678"))

        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO transaction_entry (
                    client_entry_id, amount, currency_code, category_id, asset_id,
                    transaction_type, transaction_date, pending, applied_rate,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    "11111111-1111-1111-1111-111111111111",
                    DecimalTextConversion.string(from: amount),
                    "USD", 1, 1,
                    "EXPENSE", "2026-07-02", 1,
                    DecimalTextConversion.string(from: appliedRate),
                    "2026-07-02T00:00:00Z", "2026-07-02T00:00:00Z"
                ]
            )
        }

        let stored: (amount: String, rate: String) = try database.read { db in
            let row = try #require(
                try Row.fetchOne(db, sql: "SELECT amount, applied_rate FROM transaction_entry")
            )
            return (row["amount"], row["applied_rate"])
        }

        #expect(stored.amount == "12345678.99")
        #expect(DecimalTextConversion.decimal(from: stored.amount) == amount)
        #expect(stored.rate == "1234.5678")
        #expect(DecimalTextConversion.decimal(from: stored.rate) == appliedRate)
    }

    @Test("기본 DB 파일은 Application Support 아래에 생성된다")
    func defaultDatabaseURLUsesApplicationSupport() throws {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let databaseURL = try AppDatabase.defaultDatabaseURL()

        #expect(databaseURL.lastPathComponent == AppDatabase.databaseFileName)
        #expect(databaseURL.path.hasPrefix(applicationSupportURL.path))
    }
}

private struct MigratedTransaction {
    let count: Int
    let amount: String
    let syncState: String
}

private struct ColumnInfo: Equatable {
    let name: String
    let type: String
    let isRequired: Bool
    let primaryKeyPosition: Int

    init(row: Row) {
        name = row["name"]
        type = row["type"]
        let notNull: Int = row["notnull"]
        isRequired = notNull == 1
        primaryKeyPosition = row["pk"]
    }

    init(type: String, isRequired: Bool, primaryKeyPosition: Int) {
        name = ""
        self.type = type
        self.isRequired = isRequired
        self.primaryKeyPosition = primaryKeyPosition
    }

    static func == (lhs: ColumnInfo, rhs: ColumnInfo) -> Bool {
        lhs.type == rhs.type
            && lhs.isRequired == rhs.isRequired
            && lhs.primaryKeyPosition == rhs.primaryKeyPosition
    }
}

private struct IndexColumn: Equatable {
    let name: String
    let isDescending: Bool

    init(name: String, isDescending: Bool) {
        self.name = name
        self.isDescending = isDescending
    }

    init?(row: Row) {
        let isKeyColumn: Int = row["key"]
        guard isKeyColumn == 1 else { return nil }

        name = row["name"]
        let desc: Int = row["desc"]
        isDescending = desc == 1
    }
}

private extension AppDatabaseTests {
    static func expectTransactionEntryTable(_ db: Database) throws {
        let tableExists = try Bool.fetchOne(
            db,
            sql: """
            SELECT EXISTS(
                SELECT 1
                FROM sqlite_master
                WHERE type = 'table'
                  AND name = 'transaction_entry'
            )
            """
        ) ?? false
        #expect(tableExists)
    }

    static func expectTransactionEntryColumns(_ db: Database) throws {
        let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(transaction_entry)")
            .reduce(into: [String: ColumnInfo]()) { result, row in
                let column = ColumnInfo(row: row)
                result[column.name] = column
            }

        #expect(columns["id"] == ColumnInfo(type: "INTEGER", isRequired: false, primaryKeyPosition: 1))
        #expect(columns["client_entry_id"] == ColumnInfo(type: "TEXT", isRequired: true, primaryKeyPosition: 0))
        #expect(columns["amount"] == ColumnInfo(type: "TEXT", isRequired: true, primaryKeyPosition: 0))
        #expect(columns["currency_code"] == ColumnInfo(type: "TEXT", isRequired: true, primaryKeyPosition: 0))
        #expect(columns["category_id"] == ColumnInfo(type: "INTEGER", isRequired: true, primaryKeyPosition: 0))
        #expect(columns["asset_id"] == ColumnInfo(type: "INTEGER", isRequired: true, primaryKeyPosition: 0))
        #expect(columns["transaction_type"] == ColumnInfo(type: "TEXT", isRequired: true, primaryKeyPosition: 0))
        #expect(columns["transaction_date"] == ColumnInfo(type: "TEXT", isRequired: true, primaryKeyPosition: 0))
        #expect(columns["memo"] == ColumnInfo(type: "TEXT", isRequired: false, primaryKeyPosition: 0))
        #expect(columns["pending"] == ColumnInfo(type: "INTEGER", isRequired: true, primaryKeyPosition: 0))
        #expect(columns["applied_rate"] == ColumnInfo(type: "TEXT", isRequired: false, primaryKeyPosition: 0))
        #expect(columns["rate_base_date"] == ColumnInfo(type: "TEXT", isRequired: false, primaryKeyPosition: 0))
        #expect(columns["krw_amount"] == ColumnInfo(type: "TEXT", isRequired: false, primaryKeyPosition: 0))
        #expect(columns["created_at"] == ColumnInfo(type: "TEXT", isRequired: true, primaryKeyPosition: 0))
        #expect(columns["updated_at"] == ColumnInfo(type: "TEXT", isRequired: true, primaryKeyPosition: 0))
        #expect(columns["sync_state"] == ColumnInfo(type: "TEXT", isRequired: true, primaryKeyPosition: 0))

        let expectedColumnNames: Set = [
            "id", "client_entry_id", "amount", "currency_code", "category_id",
            "asset_id", "transaction_type", "transaction_date", "memo", "pending",
            "applied_rate", "rate_base_date", "krw_amount", "created_at", "updated_at",
            "sync_state"
        ]
        #expect(Set(columns.keys) == expectedColumnNames)
    }

    static func expectTransactionEntryIndexes(_ db: Database) throws {
        let indexNames = try Set(String.fetchAll(
            db,
            sql: """
            SELECT name
            FROM sqlite_master
            WHERE type = 'index'
              AND tbl_name = 'transaction_entry'
            """
        ))
        #expect(indexNames.contains("transaction_entry_on_transaction_date"))
        #expect(indexNames.contains("transaction_entry_on_pending"))
        #expect(indexNames.contains("transaction_entry_on_transaction_date_id_desc"))
        #expect(indexNames.contains("transaction_entry_on_sync_state"))

        #expect(try indexKeyColumns("transaction_entry_on_transaction_date", db: db)
            == [IndexColumn(name: "transaction_date", isDescending: false)])
        #expect(try indexKeyColumns("transaction_entry_on_pending", db: db)
            == [IndexColumn(name: "pending", isDescending: false)])
        #expect(try indexKeyColumns("transaction_entry_on_transaction_date_id_desc", db: db)
            == [
                IndexColumn(name: "transaction_date", isDescending: true),
                IndexColumn(name: "id", isDescending: true)
            ])
        #expect(try indexKeyColumns("transaction_entry_on_sync_state", db: db)
            == [IndexColumn(name: "sync_state", isDescending: false)])

        let uniqueClientEntryIndexExists = try uniqueIndexExists(
            on: "client_entry_id",
            in: "transaction_entry",
            db: db
        )
        #expect(uniqueClientEntryIndexExists)
    }

    static func expectSyncBookkeepingTables(_ db: Database) throws {
        let identitySQL: String? = try String.fetchOne(
            db,
            sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'sync_identity_state'"
        )
        let cursorSQL: String? = try String.fetchOne(
            db,
            sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'sync_pull_cursor'"
        )

        #expect(identitySQL != nil)
        #expect(cursorSQL != nil)

        let removedExclusionSQL: String? = try String.fetchOne(
            db,
            sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'sync_push_exclusion'"
        )
        #expect(removedExclusionSQL == nil)

        let identityColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(sync_identity_state)")
        #expect(identityColumns.map { $0["name"] as String } == ["member_id", "import_done"])

        let cursorColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(sync_pull_cursor)")
        #expect(cursorColumns.map { $0["name"] as String }
            == ["id", "cursor_updated_at", "cursor_id"])

        #expect(throws: (any Error).self) {
            try db.execute(sql: "INSERT INTO sync_pull_cursor (id) VALUES (2)")
        }
    }

    static func indexKeyColumns(_ indexName: String, db: Database) throws -> [IndexColumn] {
        try Row.fetchAll(db, sql: "PRAGMA index_xinfo(\(indexName))")
            .compactMap(IndexColumn.init(row:))
    }

    static func uniqueIndexExists(on columnName: String, in tableName: String, db: Database) throws -> Bool {
        let indexes = try Row.fetchAll(db, sql: "PRAGMA index_list(\(tableName))")

        for index in indexes {
            let isUnique: Int = index["unique"]
            guard isUnique == 1 else { continue }

            let indexName: String = index["name"]
            let indexedColumns = try String.fetchAll(
                db,
                sql: "SELECT name FROM pragma_index_info(?)",
                arguments: [indexName]
            )
            if indexedColumns == [columnName] {
                return true
            }
        }

        return false
    }
}
