//
//  LocalTransaction.swift
//  woni_app
//

import Foundation

/// 화면과 ViewModel에서 사용하는 로컬 거래 도메인 모델. GRDB record와 분리한다.
struct LocalTransaction: Equatable {
    enum TransactionType: String, Codable, Equatable {
        case expense = "EXPENSE"
        case income = "INCOME"
    }

    let id: Int64?
    let clientEntryID: UUID
    let amount: Decimal
    let currencyCode: String
    let categoryID: Int
    let assetID: Int
    let transactionType: TransactionType
    let transactionDate: String
    let memo: String?
    let pending: Bool
    let appliedRate: Decimal?
    let rateBaseDate: String?
    let krwAmount: Decimal?
    let createdAt: String?
    let updatedAt: String?

    init(
        id: Int64? = nil,
        clientEntryID: UUID,
        amount: Decimal,
        currencyCode: String,
        categoryID: Int,
        assetID: Int,
        transactionType: TransactionType,
        transactionDate: String,
        memo: String? = nil,
        pending: Bool = false,
        appliedRate: Decimal? = nil,
        rateBaseDate: String? = nil,
        krwAmount: Decimal? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
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
    }
}

extension TransactionEntry {
    /// GRDB record -> 도메인 모델 매핑(record가 View/ViewModel에 직접 침투하지 않게 분리).
    func toDomain() -> LocalTransaction {
        LocalTransaction(
            id: id,
            clientEntryID: clientEntryID,
            amount: amount,
            currencyCode: currencyCode,
            categoryID: categoryID,
            assetID: assetID,
            transactionType: transactionType,
            transactionDate: transactionDate,
            memo: memo,
            pending: pending,
            appliedRate: appliedRate,
            rateBaseDate: rateBaseDate,
            krwAmount: krwAmount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
