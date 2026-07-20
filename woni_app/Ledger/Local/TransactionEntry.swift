//
//  TransactionEntry.swift
//  woni_app
//

import Foundation
import GRDB

struct TransactionEntry: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transaction_entry"

    var id: Int64?
    let clientEntryID: UUID
    let amount: Decimal
    let currencyCode: String
    let categoryID: Int
    let assetID: Int
    let transactionType: LocalTransaction.TransactionType
    let transactionDate: String
    let memo: String?
    let pending: Bool
    let appliedRate: Decimal?
    let rateBaseDate: String?
    let krwAmount: Decimal?
    let createdAt: String
    let updatedAt: String
    let syncState: SyncState

    init(
        id: Int64? = nil,
        clientEntryID: UUID,
        amount: Decimal,
        currencyCode: String,
        categoryID: Int,
        assetID: Int,
        transactionType: LocalTransaction.TransactionType,
        transactionDate: String,
        memo: String? = nil,
        pending: Bool,
        appliedRate: Decimal? = nil,
        rateBaseDate: String? = nil,
        krwAmount: Decimal? = nil,
        createdAt: String,
        updatedAt: String,
        syncState: SyncState
    ) {
        self.id = id
        self.clientEntryID = clientEntryID
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryID = categoryID
        self.assetID = assetID
        self.transactionType = transactionType
        self.transactionDate = transactionDate
        self.memo = memo
        self.pending = pending
        self.appliedRate = appliedRate
        self.rateBaseDate = rateBaseDate
        self.krwAmount = krwAmount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncState = syncState
    }

    init(row: Row) throws {
        id = row[Columns.id]
        clientEntryID = try Self.uuid(from: row[Columns.clientEntryID], column: Columns.clientEntryID.name)
        amount = try Self.decimal(from: row[Columns.amount], column: Columns.amount.name)
        currencyCode = row[Columns.currencyCode]
        categoryID = row[Columns.categoryID]
        assetID = row[Columns.assetID]
        transactionType = try Self.transactionType(
            from: row[Columns.transactionType],
            column: Columns.transactionType.name
        )
        transactionDate = row[Columns.transactionDate]
        memo = row[Columns.memo]
        pending = row[Columns.pending]
        appliedRate = try Self.optionalDecimal(from: row[Columns.appliedRate], column: Columns.appliedRate.name)
        rateBaseDate = row[Columns.rateBaseDate]
        krwAmount = try Self.optionalDecimal(from: row[Columns.krwAmount], column: Columns.krwAmount.name)
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
        syncState = try Self.syncState(from: row[Columns.syncState], column: Columns.syncState.name)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        clientEntryID = try Self.uuid(
            from: container.decode(String.self, forKey: .clientEntryID),
            column: CodingKeys.clientEntryID.rawValue
        )
        amount = try Self.decimal(
            from: container.decode(String.self, forKey: .amount),
            column: CodingKeys.amount.rawValue
        )
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        categoryID = try container.decode(Int.self, forKey: .categoryID)
        assetID = try container.decode(Int.self, forKey: .assetID)
        transactionType = try Self.transactionType(
            from: container.decode(String.self, forKey: .transactionType),
            column: CodingKeys.transactionType.rawValue
        )
        transactionDate = try container.decode(String.self, forKey: .transactionDate)
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
        pending = try container.decode(Bool.self, forKey: .pending)
        appliedRate = try Self.optionalDecimal(
            from: container.decodeIfPresent(String.self, forKey: .appliedRate),
            column: CodingKeys.appliedRate.rawValue
        )
        rateBaseDate = try container.decodeIfPresent(String.self, forKey: .rateBaseDate)
        krwAmount = try Self.optionalDecimal(
            from: container.decodeIfPresent(String.self, forKey: .krwAmount),
            column: CodingKeys.krwAmount.rawValue
        )
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        syncState = try Self.syncState(
            from: container.decode(String.self, forKey: .syncState),
            column: CodingKeys.syncState.rawValue
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(clientEntryID.uuidString, forKey: .clientEntryID)
        try container.encode(DecimalTextConversion.string(from: amount), forKey: .amount)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(assetID, forKey: .assetID)
        try container.encode(transactionType.rawValue, forKey: .transactionType)
        try container.encode(transactionDate, forKey: .transactionDate)
        try container.encodeIfPresent(memo, forKey: .memo)
        try container.encode(pending, forKey: .pending)
        if let appliedRate {
            try container.encode(DecimalTextConversion.string(from: appliedRate), forKey: .appliedRate)
        }
        try container.encodeIfPresent(rateBaseDate, forKey: .rateBaseDate)
        if let krwAmount {
            try container.encode(DecimalTextConversion.string(from: krwAmount), forKey: .krwAmount)
        }
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(syncState.rawValue, forKey: .syncState)
    }

    func encode(to container: inout PersistenceContainer) throws {
        if let id {
            container[Columns.id] = id
        }
        container[Columns.clientEntryID] = clientEntryID.uuidString
        container[Columns.amount] = DecimalTextConversion.string(from: amount)
        container[Columns.currencyCode] = currencyCode
        container[Columns.categoryID] = categoryID
        container[Columns.assetID] = assetID
        container[Columns.transactionType] = transactionType.rawValue
        container[Columns.transactionDate] = transactionDate
        container[Columns.memo] = memo
        container[Columns.pending] = pending
        container[Columns.appliedRate] = appliedRate.map { DecimalTextConversion.string(from: $0) }
        container[Columns.rateBaseDate] = rateBaseDate
        container[Columns.krwAmount] = krwAmount.map { DecimalTextConversion.string(from: $0) }
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
        container[Columns.syncState] = syncState.rawValue
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension TransactionEntry {
    enum Columns {
        static let id = Column("id")
        static let clientEntryID = Column("client_entry_id")
        static let amount = Column("amount")
        static let currencyCode = Column("currency_code")
        static let categoryID = Column("category_id")
        static let assetID = Column("asset_id")
        static let transactionType = Column("transaction_type")
        static let transactionDate = Column("transaction_date")
        static let memo = Column("memo")
        static let pending = Column("pending")
        static let appliedRate = Column("applied_rate")
        static let rateBaseDate = Column("rate_base_date")
        static let krwAmount = Column("krw_amount")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
        static let syncState = Column("sync_state")
    }
}

private extension TransactionEntry {
    enum CodingKeys: String, CodingKey {
        case id
        case clientEntryID = "client_entry_id"
        case amount
        case currencyCode = "currency_code"
        case categoryID = "category_id"
        case assetID = "asset_id"
        case transactionType = "transaction_type"
        case transactionDate = "transaction_date"
        case memo
        case pending
        case appliedRate = "applied_rate"
        case rateBaseDate = "rate_base_date"
        case krwAmount = "krw_amount"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncState = "sync_state"
    }

    static func uuid(from text: String, column: String) throws -> UUID {
        guard let uuid = UUID(uuidString: text) else {
            throw TransactionEntryError.invalidUUID(column: column, value: text)
        }
        return uuid
    }

    static func decimal(from text: String, column: String) throws -> Decimal {
        guard let decimal = DecimalTextConversion.decimal(from: text) else {
            throw TransactionEntryError.invalidDecimal(column: column, value: text)
        }
        return decimal
    }

    static func optionalDecimal(from text: String?, column: String) throws -> Decimal? {
        guard let text else {
            return nil
        }
        return try decimal(from: text, column: column)
    }

    static func transactionType(from text: String, column: String) throws -> LocalTransaction.TransactionType {
        guard let transactionType = LocalTransaction.TransactionType(rawValue: text) else {
            throw TransactionEntryError.invalidTransactionType(column: column, value: text)
        }
        return transactionType
    }

    static func syncState(from text: String, column: String) throws -> SyncState {
        guard let syncState = SyncState(rawValue: text) else {
            throw TransactionEntryError.invalidSyncState(column: column, value: text)
        }
        return syncState
    }
}

private enum TransactionEntryError: Error, LocalizedError {
    case invalidUUID(column: String, value: String)
    case invalidDecimal(column: String, value: String)
    case invalidTransactionType(column: String, value: String)
    case invalidSyncState(column: String, value: String)

    var errorDescription: String? {
        switch self {
        case let .invalidUUID(column, value):
            "Invalid UUID in \(column): \(value)"
        case let .invalidDecimal(column, value):
            "Invalid Decimal in \(column): \(value)"
        case let .invalidTransactionType(column, value):
            "Invalid transaction type in \(column): \(value)"
        case let .invalidSyncState(column, value):
            "Invalid sync state in \(column): \(value)"
        }
    }
}
