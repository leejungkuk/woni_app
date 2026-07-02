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

struct Cursor: Equatable {
    let transactionDate: String
    let id: Int64
}

struct TransactionRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

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
            pending: true,
            appliedRate: nil,
            rateBaseDate: nil,
            krwAmount: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try await database.write { @Sendable db in
            var entry = entry
            try entry.insert(db)
        }
    }

    func page(month: LedgerMonth, after cursor: Cursor?, size: Int) async throws -> [LocalTransaction] {
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

    var errorDescription: String? {
        switch self {
        case let .invalidMonth(month):
            "Invalid ledger month: \(month)"
        }
    }
}
