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

    private static var migrator: DatabaseMigrator {
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

        return migrator
    }
}
