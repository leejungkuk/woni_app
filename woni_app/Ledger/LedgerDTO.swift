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
