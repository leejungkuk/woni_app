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

    func deleteSynced(clientEntryID: UUID) async throws {
        try await client.delete("/api/v1/ledgers/sync/\(clientEntryID.uuidString)")
    }

    func restore(
        cursorDate: String?,
        cursorId: Int64?,
        size: Int
    ) async throws -> LedgerRestoreResponse {
        try validateCursor(first: cursorDate, second: cursorId, kind: .restore)
        try validateCursorId(cursorId)
        try validatePageSize(size)

        var query = cursorQuery(firstName: "cursorDate", first: cursorDate, id: cursorId)
        query.append(URLQueryItem(name: "size", value: String(size)))
        return try await client.get("/api/v1/ledgers/restore", query: query)
    }

    func changes(
        cursorUpdatedAt: String?,
        cursorId: Int64?,
        size: Int
    ) async throws -> LedgerChangesResponse {
        try validateCursor(first: cursorUpdatedAt, second: cursorId, kind: .changes)
        try validateCursorId(cursorId)
        try validatePageSize(size)

        var query = cursorQuery(firstName: "cursorUpdatedAt", first: cursorUpdatedAt, id: cursorId)
        query.append(URLQueryItem(name: "size", value: String(size)))
        return try await client.get("/api/v1/ledgers/changes", query: query)
    }
}

private extension LedgerService {
    enum CursorKind {
        case restore
        case changes
    }

    func validateCursor(first: String?, second: Int64?, kind: CursorKind) throws {
        guard (first == nil) == (second == nil) else {
            switch kind {
            case .restore:
                throw LedgerServiceError.incompleteRestoreCursor
            case .changes:
                throw LedgerServiceError.incompleteChangesCursor
            }
        }
    }

    func validatePageSize(_ size: Int) throws {
        guard (1 ... 500).contains(size) else {
            throw LedgerServiceError.invalidPageSize(size)
        }
    }

    func validateCursorId(_ cursorId: Int64?) throws {
        guard let cursorId else {
            return
        }
        guard cursorId >= 1 else {
            throw LedgerServiceError.invalidCursorId(cursorId)
        }
    }

    func cursorQuery(firstName: String, first: String?, id: Int64?) -> [URLQueryItem] {
        guard let first, let id else {
            return []
        }
        return [
            URLQueryItem(name: firstName, value: first),
            URLQueryItem(name: "cursorId", value: String(id))
        ]
    }
}

enum LedgerServiceError: Error, Equatable {
    case incompleteRestoreCursor
    case incompleteChangesCursor
    case invalidPageSize(Int)
    case invalidCursorId(Int64)
}
