//
//  AppDatabase.swift
//  woni_app
//

import Foundation
import GRDB

struct AppDatabase {
    static let databaseFileName = "woni.sqlite"

    let dbWriter: any DatabaseWriter

    init(_ dbWriter: some DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.migrator.migrate(dbWriter)
    }

    init() throws {
        try self.init(path: Self.defaultDatabaseURL().path)
    }

    init(path: String) throws {
        try self.init(DatabasePool(path: path))
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = applicationSupportURL.appendingPathComponent("woni_app", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        return directoryURL.appendingPathComponent(databaseFileName, isDirectory: false)
    }

    func read<T>(_ value: (Database) throws -> T) throws -> T {
        try dbWriter.read(value)
    }

    func write<T>(_ updates: (Database) throws -> T) throws -> T {
        try dbWriter.write(updates)
    }

    /// Swift 동시성 컨텍스트에서는 blocking 동기 호출 대신 GRDB async 접근을 쓴다.
    /// 동기 write/read 를 async 함수 안에서 호출하면 협력 스레드 풀에서 GRDB
    /// 스레드 confinement 어서션이 간헐 크래시로 표면화된다.
    func read<T: Sendable>(_ value: @Sendable (Database) throws -> T) async throws -> T {
        try await dbWriter.read(value)
    }

    func write<T: Sendable>(_ updates: @Sendable (Database) throws -> T) async throws -> T {
        try await dbWriter.write(updates)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
            CREATE TABLE transaction_entry (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                client_entry_id TEXT UNIQUE NOT NULL,
                amount TEXT NOT NULL,
                currency_code TEXT NOT NULL,
                category_id INTEGER NOT NULL,
                asset_id INTEGER NOT NULL,
                transaction_type TEXT NOT NULL,
                transaction_date TEXT NOT NULL,
                memo TEXT NULL,
                pending INTEGER NOT NULL,
                applied_rate TEXT NULL,
                rate_base_date TEXT NULL,
                krw_amount TEXT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """)
            try db.execute(sql: """
            CREATE INDEX transaction_entry_on_transaction_date
            ON transaction_entry(transaction_date)
            """)
            try db.execute(sql: """
            CREATE INDEX transaction_entry_on_pending
            ON transaction_entry(pending)
            """)
            try db.execute(sql: """
            CREATE INDEX transaction_entry_on_transaction_date_id_desc
            ON transaction_entry(transaction_date DESC, id DESC)
            """)
        }

        migrator.registerMigration("v2") { db in
            try db.execute(sql: """
            ALTER TABLE transaction_entry
            ADD COLUMN sync_state TEXT NOT NULL DEFAULT 'pendingPush'
                CHECK (sync_state IN ('pendingPush', 'synced'))
            """)
            try db.execute(sql: """
            CREATE INDEX transaction_entry_on_sync_state
            ON transaction_entry(sync_state)
            """)
            try db.execute(sql: """
            CREATE TABLE sync_identity_state (
                member_id TEXT PRIMARY KEY,
                import_done INTEGER NOT NULL DEFAULT 0
            )
            """)
            try db.execute(sql: """
            CREATE TABLE sync_pull_cursor (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                cursor_updated_at TEXT NULL,
                cursor_id INTEGER NULL
            )
            """)
        }

        return migrator
    }
}
