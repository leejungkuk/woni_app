//
//  TransactionRepository.swift
//  woni_app
//

import Foundation
import GRDB

struct LedgerMonth: Equatable {
    let year: Int
    let month: Int
}

struct TransactionPageCursor: Equatable {
    let transactionDate: String
    let id: Int64
}

struct SyncPullCursor: Equatable {
    let updatedAt: String
    let id: Int64
}

enum LogoutDataError: Error, Equatable {
    case unsyncedEntriesRemain
}

struct TransactionRepository {
    nonisolated struct PushedPayload: Equatable {
        let amount: Decimal
        let currencyCode: String
        let categoryID: Int
        let assetID: Int
        let transactionDate: String
        let memo: String?
    }

    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }
}

extension TransactionRepository.PushedPayload {
    init(transaction: LocalTransaction) {
        self.init(
            amount: transaction.amount,
            currencyCode: transaction.currencyCode,
            categoryID: transaction.categoryID,
            assetID: transaction.assetID,
            transactionDate: transaction.transactionDate,
            memo: transaction.memo
        )
    }
}

extension TransactionRepository {
    func insert(_ transaction: LocalTransaction) async throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = TransactionEntry(
            clientEntryID: transaction.clientEntryID,
            amount: transaction.amount,
            currencyCode: transaction.currencyCode,
            categoryID: transaction.categoryID,
            assetID: transaction.assetID,
            transactionType: transaction.transactionType,
            transactionDate: transaction.transactionDate,
            memo: transaction.memo,
            pending: transaction.pending,
            appliedRate: transaction.appliedRate,
            rateBaseDate: transaction.rateBaseDate,
            krwAmount: transaction.krwAmount,
            createdAt: timestamp,
            updatedAt: timestamp,
            syncState: .pendingPush
        )

        try await database.write { @Sendable db in
            var entry = entry
            try entry.insert(db)
        }
    }

    func transaction(clientEntryID: UUID) async throws -> LocalTransaction? {
        try await database.read { @Sendable db in
            let request = TransactionEntry
                .filter(TransactionEntry.Columns.clientEntryID == clientEntryID.uuidString)
            return try request.fetchOne(db)?.toDomain()
        }
    }

    func update(_ transaction: LocalTransaction) async throws -> Bool {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let amountText = DecimalTextConversion.string(from: transaction.amount)
        let appliedRateText = transaction.appliedRate.map(DecimalTextConversion.string(from:))
        let krwAmountText = transaction.krwAmount.map(DecimalTextConversion.string(from:))

        return try await database.write { @Sendable db in
            try db.execute(
                sql: """
                UPDATE transaction_entry
                SET amount = ?,
                    currency_code = ?,
                    category_id = ?,
                    asset_id = ?,
                    transaction_type = ?,
                    transaction_date = ?,
                    memo = ?,
                    pending = ?,
                    applied_rate = ?,
                    rate_base_date = ?,
                    krw_amount = ?,
                    updated_at = ?,
                    sync_state = ?
                WHERE client_entry_id = ?
                """,
                arguments: [
                    amountText,
                    transaction.currencyCode,
                    transaction.categoryID,
                    transaction.assetID,
                    transaction.transactionType.rawValue,
                    transaction.transactionDate,
                    transaction.memo,
                    transaction.pending,
                    appliedRateText,
                    transaction.rateBaseDate,
                    krwAmountText,
                    timestamp,
                    SyncState.pendingPush.rawValue,
                    transaction.clientEntryID.uuidString
                ]
            )
            return db.changesCount > 0
        }
    }

    func delete(clientEntryID: UUID) async throws {
        try await database.write { @Sendable db in
            try db.execute(
                sql: "DELETE FROM transaction_entry WHERE client_entry_id = ?",
                arguments: [clientEntryID.uuidString]
            )
            try db.execute(
                sql: "INSERT OR IGNORE INTO sync_delete_queue (client_entry_id) VALUES (?)",
                arguments: [clientEntryID.uuidString]
            )
        }
    }

    func pendingDeleteClientEntryIDs() async throws -> [UUID] {
        try await database.read { @Sendable db in
            let identifiers = try String.fetchAll(
                db,
                sql: "SELECT client_entry_id FROM sync_delete_queue ORDER BY client_entry_id ASC"
            )
            return try identifiers.map { identifier in
                guard let clientEntryID = UUID(uuidString: identifier) else {
                    throw TransactionRepositoryError.invalidDeleteQueueClientEntryID(identifier)
                }
                return clientEntryID
            }
        }
    }

    func removeFromDeleteQueue(clientEntryIDs: [UUID]) async throws {
        guard !clientEntryIDs.isEmpty else { return }

        try await database.write { @Sendable db in
            for clientEntryID in clientEntryIDs {
                try db.execute(
                    sql: "DELETE FROM sync_delete_queue WHERE client_entry_id = ?",
                    arguments: [clientEntryID.uuidString]
                )
            }
        }
    }

    func confirmPush(
        clientEntryID: UUID,
        pushed: PushedPayload,
        krwAmount: Decimal?,
        appliedRate: Decimal?,
        rateBaseDate: String?
    ) async throws -> Bool {
        let krwAmountText = krwAmount.map(DecimalTextConversion.string(from:))
        let appliedRateText = appliedRate.map(DecimalTextConversion.string(from:))

        return try await database.write { @Sendable db in
            guard let entry = try TransactionEntry
                .filter(TransactionEntry.Columns.clientEntryID == clientEntryID.uuidString)
                .fetchOne(db)
            else {
                return false
            }
            let current = PushedPayload(
                amount: entry.amount,
                currencyCode: entry.currencyCode,
                categoryID: entry.categoryID,
                assetID: entry.assetID,
                transactionDate: entry.transactionDate,
                memo: entry.memo
            )
            guard current == pushed else { return false }

            try db.execute(
                sql: """
                UPDATE transaction_entry
                SET krw_amount = ?,
                    applied_rate = ?,
                    rate_base_date = ?,
                    pending = 0,
                    sync_state = ?
                WHERE client_entry_id = ?
                """,
                arguments: [
                    krwAmountText,
                    appliedRateText,
                    rateBaseDate,
                    SyncState.synced.rawValue,
                    clientEntryID.uuidString
                ]
            )
            return db.changesCount > 0
        }
    }

    func applyServerEntry(_ transaction: LocalTransaction, fullReplace: Bool) async throws -> Bool {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let krwAmountText = transaction.krwAmount.map(DecimalTextConversion.string(from:))
        let appliedRateText = transaction.appliedRate.map(DecimalTextConversion.string(from:))

        return try await database.write { @Sendable db in
            let queueSQL = "SELECT EXISTS(SELECT 1 FROM sync_delete_queue WHERE client_entry_id = ?)"
            let isQueuedForDelete = try Bool.fetchOne(
                db, sql: queueSQL, arguments: [transaction.clientEntryID.uuidString]
            ) ?? false
            guard !isQueuedForDelete else { return false }

            let existing = try TransactionEntry
                .filter(TransactionEntry.Columns.clientEntryID == transaction.clientEntryID.uuidString)
                .fetchOne(db)
            guard existing?.syncState != .pendingPush else { return false }

            if fullReplace || existing == nil {
                var entry = TransactionEntry(
                    id: existing?.id,
                    clientEntryID: transaction.clientEntryID,
                    amount: transaction.amount,
                    currencyCode: transaction.currencyCode,
                    categoryID: transaction.categoryID,
                    assetID: transaction.assetID,
                    transactionType: transaction.transactionType,
                    transactionDate: transaction.transactionDate,
                    memo: transaction.memo,
                    pending: transaction.pending,
                    appliedRate: transaction.appliedRate,
                    rateBaseDate: transaction.rateBaseDate,
                    krwAmount: transaction.krwAmount,
                    createdAt: transaction.createdAt ?? existing?.createdAt ?? timestamp,
                    updatedAt: transaction.updatedAt ?? timestamp,
                    syncState: .synced
                )
                try entry.save(db)
                return true
            }

            try db.execute(
                sql: """
                UPDATE transaction_entry
                SET krw_amount = ?,
                    applied_rate = ?,
                    rate_base_date = ?,
                    pending = 0,
                    sync_state = ?
                WHERE client_entry_id = ?
                """,
                arguments: [
                    krwAmountText,
                    appliedRateText,
                    transaction.rateBaseDate,
                    SyncState.synced.rawValue,
                    transaction.clientEntryID.uuidString
                ]
            )
            return db.changesCount > 0
        }
    }
}

extension TransactionRepository {
    func pendingPushEntries() async throws -> [LocalTransaction] {
        try await database.read { @Sendable db in
            try TransactionEntry
                .filter(TransactionEntry.Columns.syncState == SyncState.pendingPush.rawValue)
                .order(TransactionEntry.Columns.id.asc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// 로그아웃 데이터 손실 가드용. pendingPush 행과 삭제 큐를 미동기 상태로 집계한다.
    func hasUnsyncedEntriesForLogout() async throws -> Bool {
        try await database.read { @Sendable db in
            try Bool.fetchOne(
                db,
                sql: """
                SELECT EXISTS(
                    SELECT 1 FROM transaction_entry WHERE sync_state = ?
                ) OR EXISTS(
                    SELECT 1 FROM sync_delete_queue
                )
                """,
                arguments: [SyncState.pendingPush.rawValue]
            ) ?? false
        }
    }

    func markSynced(clientEntryIDs: [UUID]) async throws {
        guard !clientEntryIDs.isEmpty else {
            return
        }
        let identifiers = clientEntryIDs.map(\.uuidString)

        _ = try await database.write { @Sendable db in
            try TransactionEntry
                .filter(identifiers.contains(TransactionEntry.Columns.clientEntryID))
                .updateAll(
                    db,
                    TransactionEntry.Columns.syncState.set(to: SyncState.synced.rawValue)
                )
        }
    }

    func isImportDone(memberID: UUID) async throws -> Bool {
        try await database.read { @Sendable db in
            try Bool.fetchOne(
                db,
                sql: "SELECT import_done FROM sync_identity_state WHERE member_id = ?",
                arguments: [memberID.uuidString]
            ) ?? false
        }
    }

    func setImportDone(_ importDone: Bool, memberID: UUID) async throws {
        try await database.write { @Sendable db in
            try db.execute(
                sql: """
                INSERT INTO sync_identity_state (member_id, import_done)
                VALUES (?, ?)
                ON CONFLICT(member_id) DO UPDATE SET import_done = excluded.import_done
                """,
                arguments: [memberID.uuidString, importDone]
            )
        }
    }

    func pullCursor() async throws -> SyncPullCursor? {
        try await database.read { @Sendable db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT cursor_updated_at, cursor_id FROM sync_pull_cursor WHERE id = 1"
            ) else {
                return nil
            }

            let updatedAt: String? = row["cursor_updated_at"]
            let id: Int64? = row["cursor_id"]
            switch (updatedAt, id) {
            case let (.some(updatedAt), .some(id)):
                return SyncPullCursor(updatedAt: updatedAt, id: id)
            case (.none, .none):
                return nil
            default:
                throw TransactionRepositoryError.incompletePullCursor
            }
        }
    }

    func setPullCursor(_ cursor: SyncPullCursor?) async throws {
        try await database.write { @Sendable db in
            guard let cursor else {
                try db.execute(sql: "DELETE FROM sync_pull_cursor WHERE id = 1")
                return
            }

            try db.execute(
                sql: """
                INSERT INTO sync_pull_cursor (id, cursor_updated_at, cursor_id)
                VALUES (1, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    cursor_updated_at = excluded.cursor_updated_at,
                    cursor_id = excluded.cursor_id
                """,
                arguments: [cursor.updatedAt, cursor.id]
            )
        }
    }

    /// 로그아웃 뒤 다른 신원의 데이터가 섞이지 않도록 ledger와 신원별 sync bookkeeping을
    /// 하나의 DB 트랜잭션에서 비운다. 서버에 올라간 멤버 데이터는 건드리지 않는다.
    func clearForLogout(force: Bool) async throws {
        try await database.write { @Sendable db in
            if !force {
                let unsyncedCount = try TransactionEntry
                    .filter(TransactionEntry.Columns.syncState == SyncState.pendingPush.rawValue)
                    .fetchCount(db)
                let pendingDeleteCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_delete_queue") ?? 0
                guard unsyncedCount == 0, pendingDeleteCount == 0 else {
                    throw LogoutDataError.unsyncedEntriesRemain
                }
            }
            try db.execute(sql: "DELETE FROM transaction_entry")
            try db.execute(sql: "DELETE FROM sync_delete_queue")
            try db.execute(sql: "DELETE FROM sync_identity_state")
            try db.execute(sql: "DELETE FROM sync_pull_cursor")
        }
    }

    func page(
        month: LedgerMonth,
        after cursor: TransactionPageCursor?,
        size: Int
    ) async throws -> [LocalTransaction] {
        guard size > 0 else {
            return []
        }

        let bounds = try month.dateBounds()

        return try await database.read { @Sendable db in
            var request = TransactionEntry
                .all()
                .filter(TransactionEntry.Columns.transactionDate >= bounds.start)
                .filter(TransactionEntry.Columns.transactionDate < bounds.end)

            if let cursor {
                request = request.filter(
                    TransactionEntry.Columns.transactionDate < cursor.transactionDate
                        || (
                            TransactionEntry.Columns.transactionDate == cursor.transactionDate
                                && TransactionEntry.Columns.id < cursor.id
                        )
                )
            }

            let entries = try request
                .order(TransactionEntry.Columns.transactionDate.desc, TransactionEntry.Columns.id.desc)
                .limit(size)
                .fetchAll(db)

            return entries.map { $0.toDomain() }
        }
    }

    func all(month: LedgerMonth) async throws -> [LocalTransaction] {
        let bounds = try month.dateBounds()

        return try await database.read { @Sendable db in
            let entries = try TransactionEntry
                .all()
                .filter(TransactionEntry.Columns.transactionDate >= bounds.start)
                .filter(TransactionEntry.Columns.transactionDate < bounds.end)
                .order(TransactionEntry.Columns.transactionDate.desc, TransactionEntry.Columns.id.desc)
                .fetchAll(db)

            return entries.map { $0.toDomain() }
        }
    }

    func count() async throws -> Int {
        try await database.read { @Sendable db in
            try TransactionEntry.fetchCount(db)
        }
    }
}

private extension LedgerMonth {
    func dateBounds() throws -> (start: String, end: String) {
        guard (1 ... 12).contains(month) else {
            throw TransactionRepositoryError.invalidMonth(month)
        }

        let nextYear = month == 12 ? year + 1 : year
        let nextMonth = month == 12 ? 1 : month + 1

        return (
            start: Self.dateString(year: year, month: month),
            end: Self.dateString(year: nextYear, month: nextMonth)
        )
    }

    static func dateString(year: Int, month: Int) -> String {
        String(format: "%04d-%02d-01", year, month)
    }
}

private enum TransactionRepositoryError: Error, LocalizedError {
    case invalidMonth(Int)
    case incompletePullCursor
    case invalidDeleteQueueClientEntryID(String)

    var errorDescription: String? {
        switch self {
        case let .invalidMonth(month):
            "Invalid ledger month: \(month)"
        case .incompletePullCursor:
            "Pull cursor must contain both updatedAt and id"
        case let .invalidDeleteQueueClientEntryID(identifier):
            "Invalid client entry ID in delete queue: \(identifier)"
        }
    }
}
