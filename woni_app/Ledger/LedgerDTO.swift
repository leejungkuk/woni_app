//
//  LedgerDTO.swift
//  woni_app
//

import Foundation

/// 백엔드 `CreateLedgerEntryRequest`에 1:1 대응하는 생성 요청 DTO.
/// 금액은 `Decimal`, 날짜는 서버 `LocalDate` 문자열("yyyy-MM-dd")을 그대로 전달한다.
struct CreateLedgerEntryRequest: Encodable {
    let amount: Decimal
    let currencyCode: String
    let categoryId: Int
    let assetId: Int
    let transactionDate: String
    let memo: String?
}

/// 백엔드 ImportLedgerEntriesRequest에 대응하는 최초 전량 import 요청.
struct ImportLedgerEntriesRequest: Encodable {
    let entries: [ImportLedgerEntryItem]
}

/// 백엔드 ImportLedgerEntryItem exact request DTO.
/// 서버가 환산을 재해석하므로 krwAmount와 appliedRate는 요청 계약에 포함하지 않는다.
struct ImportLedgerEntryItem: Encodable {
    let clientEntryId: UUID
    let amount: Decimal
    let currencyCode: String
    let categoryId: Int
    let assetId: Int
    let transactionDate: String
    let memo: String?
}

/// 백엔드 SyncLedgerEntryRequest exact request DTO.
/// clientEntryId를 멱등 키로 사용하고 서버 확정 환산값은 전송하지 않는다.
struct SyncLedgerEntryRequest: Encodable {
    let clientEntryId: UUID
    let amount: Decimal
    let currencyCode: String
    let categoryId: Int
    let assetId: Int
    let transactionDate: String
    let memo: String?
}

/// 백엔드 `LedgerEntryResponse`에 1:1 대응하는 서버 DTO.
/// 화면용 도메인 모델은 아직 만들지 않고, 저장 호출 응답 확인 경계에서만 사용한다.
struct LedgerEntryResponse: Decodable {
    let id: Int
    let transactionType: String
    let currencyCode: String
    let originalAmount: Decimal
    let krwAmount: Decimal
    let appliedRate: Decimal
    let rateBaseDate: String?
    let transactionDate: String
    let memo: String?
    let category: CategoryDTO
    let asset: AssetDTO
}

/// 백엔드 ImportLedgerEntriesResponse의 전량 처리 결과.
struct ImportLedgerEntriesResponse: Decodable {
    let entries: [ImportedLedgerEntry]
}

/// import 결과의 클라이언트 멱등 키와 서버 확정 거래 쌍.
struct ImportedLedgerEntry: Decodable {
    let clientEntryId: UUID
    let ledgerEntry: LedgerEntryResponse
}

/// 백엔드 SyncLedgerEntryResponse의 건별 처리 결과.
struct SyncLedgerEntryResponse: Decodable {
    let clientEntryId: UUID
    let ledgerEntry: LedgerEntryResponse
}

/// 백엔드 LedgerRestoreResponse exact response DTO.
struct LedgerRestoreResponse: Decodable {
    let entries: [RestoredLedgerEntry]
    let nextCursor: RestoreCursor?
    let hasNext: Bool
}

/// restore의 `(transaction_date desc, id desc)` keyset 커서.
struct RestoreCursor: Decodable, Equatable {
    let transactionDate: String
    let id: Int64
}

/// 백엔드 RestoredLedgerEntry exact response DTO.
struct RestoredLedgerEntry: Decodable {
    let id: Int64
    let clientEntryId: UUID?
    let transactionType: String
    let category: CategoryDTO
    let asset: AssetDTO
    let originalAmount: Decimal
    let currencyCode: String
    let appliedRate: Decimal
    let krwAmount: Decimal
    let rateBaseDate: String?
    let transactionDate: String
    let memo: String?
}

/// 백엔드 LedgerChangesResponse exact response DTO.
struct LedgerChangesResponse: Decodable {
    let entries: [ChangedLedgerEntry]
    let nextCursor: Cursor?
    let hasMore: Bool
}

/// changes의 `(updated_at asc, id asc)` keyset 커서.
struct Cursor: Decodable, Equatable {
    let updatedAt: String
    let id: Int64
}

/// 백엔드 ChangedLedgerEntry exact response DTO.
struct ChangedLedgerEntry: Decodable {
    let id: Int64
    let clientEntryId: UUID?
    let updatedAt: String
    let transactionType: String
    let category: CategoryDTO
    let asset: AssetDTO
    let originalAmount: Decimal
    let currencyCode: String
    let appliedRate: Decimal
    let krwAmount: Decimal
    let rateBaseDate: String?
    let transactionDate: String
    let memo: String?
}

extension RestoredLedgerEntry {
    func toDomain() throws -> LocalTransaction? {
        guard let clientEntryId else {
            return nil
        }
        return try LocalTransaction(
            clientEntryID: clientEntryId,
            amount: originalAmount,
            currencyCode: currencyCode,
            categoryID: category.id,
            assetID: asset.id,
            transactionType: ledgerTransactionType(transactionType),
            transactionDate: transactionDate,
            memo: memo,
            pending: false,
            appliedRate: appliedRate,
            rateBaseDate: rateBaseDate,
            krwAmount: krwAmount,
            syncState: .synced
        )
    }
}

extension ChangedLedgerEntry {
    func toDomain() throws -> LocalTransaction? {
        guard let clientEntryId else {
            return nil
        }
        return try LocalTransaction(
            clientEntryID: clientEntryId,
            amount: originalAmount,
            currencyCode: currencyCode,
            categoryID: category.id,
            assetID: asset.id,
            transactionType: ledgerTransactionType(transactionType),
            transactionDate: transactionDate,
            memo: memo,
            pending: false,
            appliedRate: appliedRate,
            rateBaseDate: rateBaseDate,
            krwAmount: krwAmount,
            updatedAt: updatedAt,
            syncState: .synced
        )
    }
}

private func ledgerTransactionType(_ rawValue: String) throws -> LocalTransaction.TransactionType {
    guard let transactionType = LocalTransaction.TransactionType(rawValue: rawValue) else {
        throw LedgerDTOError.invalidTransactionType(rawValue)
    }
    return transactionType
}

private enum LedgerDTOError: Error {
    case invalidTransactionType(String)
}
