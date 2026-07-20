//
//  LedgerService.swift
//  woni_app
//

import Foundation

/// 가계부 생성·push API. APIClient를 통해 공통 응답 봉투를 해석한다.
struct LedgerService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func create(_ request: CreateLedgerEntryRequest) async throws -> LedgerEntryResponse {
        try await client.post("/api/v1/ledgers", body: request)
    }

    func importAll(_ items: [ImportLedgerEntryItem]) async throws -> ImportLedgerEntriesResponse {
        try await client.post(
            "/api/v1/ledgers/import",
            body: ImportLedgerEntriesRequest(entries: items)
        )
    }

    func sync(_ item: SyncLedgerEntryRequest) async throws -> SyncLedgerEntryResponse {
        try await client.post("/api/v1/ledgers/sync", body: item)
    }
}
