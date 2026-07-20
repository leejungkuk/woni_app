//
//  LedgerDTOTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@MainActor
struct LedgerDTOTests {
    @Test("import와 sync 요청은 OpenAPI 필드만 인코딩하고 서버 확정 환산값을 제외한다")
    func pushRequestsMatchOpenAPIFields() throws {
        let entryID = try #require(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let item = try ImportLedgerEntryItem(
            clientEntryId: entryID,
            amount: #require(Decimal(string: "1234.56")),
            currencyCode: "USD",
            categoryId: 10,
            assetId: 20,
            transactionDate: "2026-07-20",
            memo: nil
        )
        let sync = SyncLedgerEntryRequest(
            clientEntryId: item.clientEntryId,
            amount: item.amount,
            currencyCode: item.currencyCode,
            categoryId: item.categoryId,
            assetId: item.assetId,
            transactionDate: item.transactionDate,
            memo: item.memo
        )

        let importObject = try jsonObject(ImportLedgerEntriesRequest(entries: [item]))
        let entries = try #require(importObject["entries"] as? [[String: Any]])
        let importItem = try #require(entries.first)
        let syncObject = try jsonObject(sync)

        let expectedKeys: Set = [
            "clientEntryId",
            "amount",
            "currencyCode",
            "categoryId",
            "assetId",
            "transactionDate"
        ]
        #expect(Set(importItem.keys) == expectedKeys)
        #expect(Set(syncObject.keys) == expectedKeys)
        #expect(importItem["clientEntryId"] as? String == entryID.uuidString)
        #expect(syncObject["clientEntryId"] as? String == entryID.uuidString)
        #expect(importItem["krwAmount"] == nil)
        #expect(importItem["appliedRate"] == nil)
        #expect(syncObject["krwAmount"] == nil)
        #expect(syncObject["appliedRate"] == nil)
    }
}

private func jsonObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
