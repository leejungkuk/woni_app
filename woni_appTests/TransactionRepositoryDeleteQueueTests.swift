//
//  TransactionRepositoryDeleteQueueTests.swift
//  woni_appTests
//

import Foundation
import GRDB
import Testing
@testable import woni_app

extension TransactionRepositoryTests {
    @Test("delete는 행 삭제와 큐 기록을 같은 트랜잭션으로 수행한다")
    func deleteRollsBackRowDeletionWhenQueueInsertFails() async throws {
        let context = try Self.makeRepositoryAndDatabase()
        let clientEntryID = try #require(UUID(uuidString: "10101010-1010-1010-1010-101010101010"))
        try await context.repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            transactionDate: "2026-07-10"
        ))
        try await context.database.write { db in
            try db.execute(sql: """
            CREATE TRIGGER reject_delete_queue_insert
            BEFORE INSERT ON sync_delete_queue
            BEGIN
                SELECT RAISE(ABORT, 'queue insert rejected');
            END
            """)
        }

        do {
            try await context.repository.delete(clientEntryID: clientEntryID)
            Issue.record("큐 기록이 실패하면 delete도 실패해야 합니다.")
        } catch {
            #expect(error.localizedDescription.contains("queue insert rejected"))
        }

        #expect(try await context.repository.transaction(clientEntryID: clientEntryID) != nil)
        #expect(try await context.repository.pendingDeleteClientEntryIDs().isEmpty)
    }

    @Test("delete는 중복 호출과 없는 행에도 멱등으로 큐를 한 번 기록한다")
    func deleteIsIdempotentAndQueuesMissingEntries() async throws {
        let repository = try Self.makeRepository()
        let existingID = try #require(UUID(uuidString: "20202020-2020-2020-2020-202020202020"))
        let missingID = try #require(UUID(uuidString: "21212121-2121-2121-2121-212121212121"))
        try await repository.insert(Self.makeTransaction(
            clientEntryID: existingID,
            transactionDate: "2026-07-20"
        ))

        try await repository.delete(clientEntryID: existingID)
        try await repository.delete(clientEntryID: existingID)
        try await repository.delete(clientEntryID: missingID)

        #expect(try await repository.transaction(clientEntryID: existingID) == nil)
        #expect(try await repository.pendingDeleteClientEntryIDs() == [existingID, missingID])
    }

    @Test("삭제 큐 조회는 UUID 문자열 오름차순이고 지정 ID 제거와 빈 배열 제거를 지원한다")
    func deleteQueueReadsInOrderAndRemovesSpecifiedIDs() async throws {
        let repository = try Self.makeRepository()
        let first = try #require(UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000"))
        let second = try #require(UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000"))
        let third = try #require(UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000000"))
        try await repository.delete(clientEntryID: third)
        try await repository.delete(clientEntryID: first)
        try await repository.delete(clientEntryID: second)

        #expect(try await repository.pendingDeleteClientEntryIDs() == [first, second, third])
        try await repository.removeFromDeleteQueue(clientEntryIDs: [])
        #expect(try await repository.pendingDeleteClientEntryIDs() == [first, second, third])
        try await repository.removeFromDeleteQueue(clientEntryIDs: [third, first])
        #expect(try await repository.pendingDeleteClientEntryIDs() == [second])
    }
}

extension TransactionRepositoryTests {
    @Test("confirmPush는 Decimal 값이 같은 payload에 확정값을 적용하고 Optional nil을 보존한다")
    func confirmPushAppliesMatchingPayloadWithDecimalValueEquality() async throws {
        let context = try Self.makeRepositoryAndDatabase()
        let clientEntryID = try #require(UUID(uuidString: "30303030-3030-3030-3030-303030303030"))
        try await context.repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("1"),
            currencyCode: "USD",
            categoryID: 3,
            assetID: 4,
            transactionDate: "2026-07-21",
            memo: nil,
            pending: true,
            appliedRate: Self.decimal("1400.1"),
            rateBaseDate: "2026-07-20",
            krwAmount: Self.decimal("1400.1")
        ))
        try await context.database.write { db in
            try db.execute(
                sql: "UPDATE transaction_entry SET amount = '1.0000' WHERE client_entry_id = ?",
                arguments: [clientEntryID.uuidString]
            )
        }

        let didConfirm = try await context.repository.confirmPush(
            clientEntryID: clientEntryID,
            pushed: Self.pushedPayload(
                amount: Self.decimal("1.00"),
                currencyCode: "USD",
                categoryID: 3,
                assetID: 4,
                transactionDate: "2026-07-21",
                memo: nil
            ),
            krwAmount: Self.decimal("123456789.123456789123"),
            appliedRate: nil,
            rateBaseDate: nil
        )

        let stored = try #require(try await context.repository.transaction(clientEntryID: clientEntryID))
        let expectedAmount = try Self.decimal("1")
        let expectedKRWAmount = try Self.decimal("123456789.123456789123")
        #expect(didConfirm && stored.syncState == .synced && !stored.pending)
        #expect(stored.amount == expectedAmount)
        #expect(stored.krwAmount == expectedKRWAmount)
        #expect(stored.appliedRate == nil && stored.rateBaseDate == nil)
    }

    @Test("confirmPush는 payload가 다르면 행을 변경하지 않고 pendingPush를 유지한다")
    func confirmPushRejectsChangedPayloadWithoutMutation() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "31313131-3131-3131-3131-313131313131"))
        try await repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("10"),
            transactionDate: "2026-07-22",
            memo: "new local edit",
            pending: true,
            appliedRate: Self.decimal("1300"),
            rateBaseDate: "2026-07-21",
            krwAmount: Self.decimal("13000")
        ))
        let before = try #require(try await repository.transaction(clientEntryID: clientEntryID))

        let didConfirm = try await repository.confirmPush(
            clientEntryID: clientEntryID,
            pushed: Self.pushedPayload(
                amount: Self.decimal("10"),
                transactionDate: "2026-07-22",
                memo: "old pushed edit"
            ),
            krwAmount: Self.decimal("99999"),
            appliedRate: Self.decimal("9999"),
            rateBaseDate: "2026-07-24"
        )

        #expect(!didConfirm)
        #expect(try await repository.transaction(clientEntryID: clientEntryID) == before)
        #expect(try await repository.pendingPushEntries().map(\.clientEntryID) == [clientEntryID])
    }

    @Test("confirmPush는 행이 없으면 false이고 행을 만들지 않는다")
    func confirmPushMissingEntryReturnsFalse() async throws {
        let repository = try Self.makeRepository()

        let didConfirm = try await repository.confirmPush(
            clientEntryID: UUID(),
            pushed: Self.pushedPayload(transactionDate: "2026-07-23"),
            krwAmount: nil,
            appliedRate: nil,
            rateBaseDate: nil
        )

        #expect(!didConfirm)
        #expect(try await repository.count() == 0)
    }
}

extension TransactionRepositoryTests {
    @Test("applyServerEntry는 삭제 큐 멤버를 부활시키지 않는다")
    func applyServerEntryRejectsDeleteQueueMember() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "40404040-4040-4040-4040-404040404040"))
        try await repository.delete(clientEntryID: clientEntryID)

        let didApply = try await repository.applyServerEntry(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("500"),
            transactionDate: "2026-07-24",
            syncState: .synced
        ), fullReplace: true)

        #expect(!didApply)
        #expect(try await repository.transaction(clientEntryID: clientEntryID) == nil)
    }

    @Test("applyServerEntry는 pendingPush 행을 덮지 않는다")
    func applyServerEntryProtectsPendingPushEntry() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "41414141-4141-4141-4141-414141414141"))
        try await repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("10"),
            transactionDate: "2026-07-24",
            memo: "local"
        ))
        let before = try #require(try await repository.transaction(clientEntryID: clientEntryID))

        let didApply = try await repository.applyServerEntry(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("999"),
            transactionDate: "2026-07-01",
            memo: "server",
            pending: false,
            appliedRate: Self.decimal("2"),
            krwAmount: Self.decimal("1998"),
            syncState: .synced
        ), fullReplace: true)

        #expect(!didApply)
        #expect(try await repository.transaction(clientEntryID: clientEntryID) == before)
    }

    @Test("pull 적용은 기존 synced 행의 확정 환율 필드만 갱신한다")
    func applyServerEntryPullUpdatesOnlyRateFieldsForExistingEntry() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "42424242-4242-4242-4242-424242424242"))
        try await repository.upsertFromServer(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("100"),
            currencyCode: "USD",
            categoryID: 1,
            assetID: 2,
            transactionType: .expense,
            transactionDate: "2026-07-10",
            memo: "keep",
            pending: true,
            appliedRate: Self.decimal("1300"),
            rateBaseDate: "2026-07-09",
            krwAmount: Self.decimal("130000"),
            createdAt: "2026-07-10T01:00:00Z",
            updatedAt: "2026-07-10T02:00:00Z",
            syncState: .synced
        ))
        let before = try #require(try await repository.transaction(clientEntryID: clientEntryID))

        let didApply = try await repository.applyServerEntry(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("999"),
            currencyCode: "JPY",
            categoryID: 99,
            assetID: 98,
            transactionType: .income,
            transactionDate: "2026-07-24",
            memo: "do not replace",
            pending: true,
            appliedRate: Self.decimal("9.123456789"),
            rateBaseDate: nil,
            krwAmount: Self.decimal("9111.111111111"),
            createdAt: "2099-01-01T00:00:00Z",
            updatedAt: "2099-01-02T00:00:00Z",
            syncState: .pendingPush
        ), fullReplace: false)

        let stored = try #require(try await repository.transaction(clientEntryID: clientEntryID))
        let expectedRate = try Self.decimal("9.123456789")
        let expectedKRWAmount = try Self.decimal("9111.111111111")
        #expect(didApply && stored.syncState == .synced && !stored.pending)
        #expect(stored.id == before.id && stored.amount == before.amount)
        #expect(stored.currencyCode == before.currencyCode && stored.categoryID == before.categoryID)
        #expect(stored.assetID == before.assetID && stored.transactionType == before.transactionType)
        #expect(stored.transactionDate == before.transactionDate && stored.memo == before.memo)
        #expect(stored.createdAt == before.createdAt && stored.updatedAt == before.updatedAt)
        #expect(stored.appliedRate == expectedRate && stored.rateBaseDate == nil)
        #expect(stored.krwAmount == expectedKRWAmount)
    }

    @Test("pull 적용은 없는 행을 전체 필드로 synced insert한다")
    func applyServerEntryPullInsertsMissingEntry() async throws {
        let repository = try Self.makeRepository()
        let transaction = try Self.makeTransaction(
            clientEntryID: UUID(),
            amount: Self.decimal("88.7654321"),
            currencyCode: "EUR",
            categoryID: 7,
            assetID: 8,
            transactionType: .income,
            transactionDate: "2026-07-12",
            memo: nil,
            pending: false,
            appliedRate: Self.decimal("1500.123"),
            rateBaseDate: nil,
            krwAmount: Self.decimal("133158.9132363"),
            createdAt: nil,
            updatedAt: "2026-07-24T10:00:00Z",
            syncState: .pendingPush
        )

        let didApply = try await repository.applyServerEntry(transaction, fullReplace: false)

        let stored = try #require(try await repository.transaction(clientEntryID: transaction.clientEntryID))
        #expect(didApply && stored.syncState == .synced)
        #expect(stored.amount == transaction.amount && stored.currencyCode == transaction.currencyCode)
        #expect(stored.categoryID == transaction.categoryID && stored.assetID == transaction.assetID)
        #expect(stored.transactionType == transaction.transactionType)
        #expect(stored.transactionDate == transaction.transactionDate && stored.memo == transaction.memo)
        #expect(stored.pending == transaction.pending && stored.appliedRate == transaction.appliedRate)
        #expect(stored.rateBaseDate == transaction.rateBaseDate && stored.krwAmount == transaction.krwAmount)
        #expect(stored.createdAt != nil && stored.updatedAt == transaction.updatedAt)
    }

    @Test("restore 적용은 전체 필드를 upsert하고 기존 id와 createdAt을 보존한다")
    func applyServerEntryRestoreFullyReplacesAndPreservesCreatedAt() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "43434343-4343-4343-4343-434343434343"))
        try await repository.upsertFromServer(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("1"),
            transactionDate: "2026-07-01",
            memo: "old",
            createdAt: "2020-01-01T00:00:00Z",
            updatedAt: "2020-01-02T00:00:00Z",
            syncState: .synced
        ))
        let before = try #require(try await repository.transaction(clientEntryID: clientEntryID))
        let restored = try Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("456.789"),
            currencyCode: "CNY",
            categoryID: 12,
            assetID: 13,
            transactionType: .income,
            transactionDate: "2026-07-23",
            memo: nil,
            pending: false,
            appliedRate: Self.decimal("190.1234"),
            rateBaseDate: "2026-07-22",
            krwAmount: Self.decimal("86896.9526626"),
            createdAt: nil,
            updatedAt: "2026-07-24T11:00:00Z",
            syncState: .pendingPush
        )

        let didApply = try await repository.applyServerEntry(restored, fullReplace: true)

        let stored = try #require(try await repository.transaction(clientEntryID: clientEntryID))
        #expect(didApply && stored.syncState == .synced)
        #expect(stored.id == before.id && stored.createdAt == before.createdAt)
        #expect(stored.amount == restored.amount && stored.currencyCode == restored.currencyCode)
        #expect(stored.categoryID == restored.categoryID && stored.assetID == restored.assetID)
        #expect(stored.transactionType == restored.transactionType)
        #expect(stored.transactionDate == restored.transactionDate && stored.memo == restored.memo)
        #expect(stored.pending == restored.pending && stored.appliedRate == restored.appliedRate)
        #expect(stored.rateBaseDate == restored.rateBaseDate && stored.krwAmount == restored.krwAmount)
        #expect(stored.updatedAt == restored.updatedAt)
    }
}

extension TransactionRepositoryTests {
    @Test("삭제 큐만 남아도 로그아웃 미동기로 집계하고 비강행 clear를 거부한다")
    func logoutGuardIncludesDeleteQueue() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "50505050-5050-5050-5050-505050505050"))
        try await repository.delete(clientEntryID: clientEntryID)

        #expect(try await repository.hasUnsyncedEntriesForLogout())
        do {
            try await repository.clearForLogout(force: false)
            Issue.record("삭제 큐가 남아 있으면 비강행 clear를 거부해야 합니다.")
        } catch let error as LogoutDataError {
            #expect(error == .unsyncedEntriesRemain)
        }
        #expect(try await repository.pendingDeleteClientEntryIDs() == [clientEntryID])
    }

    @Test("강행 logout clear는 삭제 큐도 정리한다")
    func forcedLogoutClearRemovesDeleteQueue() async throws {
        let repository = try Self.makeRepository()
        try await repository.delete(clientEntryID: UUID())

        try await repository.clearForLogout(force: true)

        #expect(try await repository.pendingDeleteClientEntryIDs().isEmpty)
        #expect(try await !repository.hasUnsyncedEntriesForLogout())
    }
}
