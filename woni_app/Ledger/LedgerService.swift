//
//  LedgerService.swift
//  woni_app
//

import Foundation

/// 가계부 생성 API. 백엔드 `POST /api/v1/ledgers` 계약에 대응한다.
struct LedgerService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func create(_ request: CreateLedgerEntryRequest) async throws -> LedgerEntryResponse {
        try await client.post("/api/v1/ledgers", body: request)
    }
}
