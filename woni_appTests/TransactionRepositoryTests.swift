//
//  TransactionRepositoryTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct TransactionRepositoryTests {}

extension TransactionRepositoryTests {
    @Test("insert는 nil 환율 필드와 pending true를 보존한다")
    func insertPreservesNilRateFieldsAndPendingTrue() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let amount = try Self.decimal("12345678.99")

        try await repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: amount,
            currencyCode: "USD",
            categoryID: 10,
            assetID: 20,
            transactionType: .expense,
            transactionDate: "2026-07-02",
            memo: "coffee",
            pending: true
        ))

        let transactions = try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: TransactionPageCursor?.none,
            size: 10
        )
        let stored = try #require(transactions.first)

        #expect(transactions.count == 1)
        #expect(stored.id != nil)
        #expect(stored.clientEntryID == clientEntryID)
        #expect(stored.amount == amount)
        #expect(stored.currencyCode == "USD")
        #expect(stored.categoryID == 10)
        #expect(stored.assetID == 20)
        #expect(stored.transactionType == LocalTransaction.TransactionType.expense)
        #expect(stored.transactionDate == "2026-07-02")
        #expect(stored.memo == "coffee")
        #expect(stored.pending)
        #expect(stored.appliedRate == nil)
        #expect(stored.rateBaseDate == nil)
        #expect(stored.krwAmount == nil)
        #expect(stored.createdAt != nil)
        #expect(stored.updatedAt != nil)
        #expect(stored.syncState == .pendingPush)
        #expect(try await repository.count() == 1)
    }

    @Test("insert는 전달된 환율 필드와 pending false를 Decimal 정밀도로 보존한다")
    func insertPreservesProvidedRateFieldsAndPendingFalse() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let amount = try Self.decimal("98765.4321098765")
        let appliedRate = try Self.decimal("1325.123456789")
        let krwAmount = try Self.decimal("130876543.21098765")

        try await repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: amount,
            currencyCode: "USD",
            categoryID: 30,
            assetID: 40,
            transactionType: .income,
            transactionDate: "2026-07-03",
            memo: nil,
            pending: false,
            appliedRate: appliedRate,
            rateBaseDate: "2026-07-02",
            krwAmount: krwAmount
        ))

        let transactions = try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: TransactionPageCursor?.none,
            size: 10
        )
        let stored = try #require(transactions.first)

        #expect(transactions.count == 1)
        #expect(stored.id != nil)
        #expect(stored.clientEntryID == clientEntryID)
        #expect(stored.amount == amount)
        #expect(stored.currencyCode == "USD")
        #expect(stored.categoryID == 30)
        #expect(stored.assetID == 40)
        #expect(stored.transactionType == LocalTransaction.TransactionType.income)
        #expect(stored.transactionDate == "2026-07-03")
        #expect(stored.memo == nil)
        #expect(!stored.pending)
        #expect(stored.appliedRate == appliedRate)
        #expect(stored.rateBaseDate == "2026-07-02")
        #expect(stored.krwAmount == krwAmount)
        #expect(stored.createdAt != nil)
        #expect(stored.updatedAt != nil)
        #expect(stored.syncState == .pendingPush)
        #expect(try await repository.count() == 1)
    }

    @Test("sync_state는 pending과 독립적으로 왕복하고 신규 insert는 pendingPush로 강제된다")
    func syncStateRoundTripsIndependentlyFromPending() async throws {
        let repository = try Self.makeRepository()

        try await repository.insert(Self.makeTransaction(
            transactionDate: "2026-07-04",
            pending: false,
            syncState: .synced
        ))

        let stored = try #require(try await repository.pendingPushEntries().first)
        #expect(!stored.pending)
        #expect(stored.syncState == .pendingPush)
    }

    @Test("pendingPushEntries는 모든 미동기 행을 FIFO로 반환하고 markSynced는 지정 행만 전환한다")
    func pendingPushEntriesAndMarkSyncedTrackSpecifiedEntries() async throws {
        let repository = try Self.makeRepository()
        let firstID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let secondID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let thirdID = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))

        try await repository.insert(Self.makeTransaction(clientEntryID: firstID, transactionDate: "2026-07-01"))
        try await repository.insert(Self.makeTransaction(clientEntryID: secondID, transactionDate: "2026-07-02"))
        try await repository.insert(Self.makeTransaction(clientEntryID: thirdID, transactionDate: "2026-07-03"))

        try await repository.markSynced(clientEntryIDs: [thirdID])

        let pending = try await repository.pendingPushEntries()
        let stored = try await repository.all(month: LedgerMonth(year: 2026, month: 7))
        let statesByID = Dictionary(uniqueKeysWithValues: stored.map { ($0.clientEntryID, $0.syncState) })
        #expect(pending.map(\.clientEntryID) == [firstID, secondID])
        #expect(pending.allSatisfy { $0.syncState == .pendingPush })
        #expect(statesByID[firstID] == .pendingPush)
        #expect(statesByID[secondID] == .pendingPush)
        #expect(statesByID[thirdID] == .synced)

        try await repository.markSynced(clientEntryIDs: [])
        #expect(try await repository.pendingPushEntries().map(\.clientEntryID) == [firstID, secondID])
    }

    @Test("서버 확정값 적용은 Decimal과 nil을 보존하며 pending과 sync_state를 각각 확정한다")
    func applyServerConfirmedPreservesDecimalPrecisionAndOptionals() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "66666666-6666-6666-6666-666666666666"))
        let krwAmount = try Self.decimal("130876543.210987654321")

        try await repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            transactionDate: "2026-07-05",
            pending: true,
            appliedRate: Self.decimal("1325.123456789"),
            rateBaseDate: "2026-07-04",
            krwAmount: Self.decimal("1.1")
        ))

        let didApply = try await repository.applyServerConfirmed(
            clientEntryID: clientEntryID,
            krwAmount: krwAmount,
            appliedRate: nil,
            rateBaseDate: nil
        )

        let stored = try #require(try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: nil,
            size: 10
        ).first)
        #expect(!stored.pending)
        #expect(didApply)
        #expect(stored.syncState == .synced)
        #expect(stored.krwAmount == krwAmount)
        #expect(stored.appliedRate == nil)
        #expect(stored.rateBaseDate == nil)
    }

    @Test("서버 upsert는 client_entry_id 기준으로 교체하고 synced로 저장한다")
    func upsertFromServerUsesClientEntryIDAndMarksSynced() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "77777777-7777-7777-7777-777777777777"))
        let serverAmount = try Self.decimal("99999999.000000000001")

        try await repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("1.000000000000000001"),
            transactionDate: "2026-07-06",
            memo: "local",
            pending: true
        ))
        let initialID = try #require(try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: nil,
            size: 10
        ).first?.id)
        try await repository.upsertFromServer(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: serverAmount,
            transactionDate: "2026-07-07",
            memo: nil,
            pending: false,
            appliedRate: nil,
            rateBaseDate: nil,
            krwAmount: nil
        ))

        let stored = try #require(try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: nil,
            size: 10
        ).first)
        #expect(try await repository.count() == 1)
        #expect(stored.id == initialID)
        #expect(stored.clientEntryID == clientEntryID)
        #expect(stored.amount == serverAmount)
        #expect(stored.memo == nil)
        #expect(stored.appliedRate == nil)
        #expect(stored.krwAmount == nil)
        #expect(stored.syncState == .synced)
        #expect(try await repository.pendingPushEntries().isEmpty)
    }

    @Test("import-done 마커는 신원별로, pull 커서는 단일 튜플로 왕복한다")
    func syncBookkeepingAccessorsRoundTrip() async throws {
        let repository = try Self.makeRepository()
        let firstMemberID = try #require(UUID(uuidString: "88888888-8888-8888-8888-888888888888"))
        let secondMemberID = try #require(UUID(uuidString: "99999999-9999-9999-9999-999999999999"))
        let cursor = SyncPullCursor(updatedAt: "2026-07-20T03:04:05Z", id: 42)

        #expect(try await repository.isImportDone(memberID: firstMemberID) == false)
        try await repository.setImportDone(true, memberID: firstMemberID)
        #expect(try await repository.isImportDone(memberID: firstMemberID))
        #expect(try await repository.isImportDone(memberID: secondMemberID) == false)
        try await repository.setImportDone(false, memberID: firstMemberID)
        #expect(try await repository.isImportDone(memberID: firstMemberID) == false)

        #expect(try await repository.pullCursor() == nil)
        try await repository.setPullCursor(cursor)
        #expect(try await repository.pullCursor() == cursor)
        try await repository.setPullCursor(nil)
        #expect(try await repository.pullCursor() == nil)
    }

    @Test("로그아웃 clear는 거래·신원 마커·pull 커서를 한 트랜잭션에서 초기화한다")
    func clearForLogoutResetsLocalLedgerAndSyncBookkeeping() async throws {
        let repository = try Self.makeRepository()
        let memberID = try #require(UUID(uuidString: "abababab-abab-abab-abab-abababababab"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-20"))
        try await repository.setImportDone(true, memberID: memberID)
        try await repository.setPullCursor(SyncPullCursor(
            updatedAt: "2026-07-20T12:00:00Z",
            id: 88
        ))

        try await repository.clearForLogout(force: true)

        #expect(try await repository.count() == 0)
        #expect(try await repository.pendingPushEntries().isEmpty)
        #expect(try await repository.isImportDone(memberID: memberID) == false)
        #expect(try await repository.pullCursor() == nil)
    }

    @Test("비강행 logout clear는 트랜잭션 시점의 미동기 행을 보존하고 거부한다")
    func nonForcedClearAtomicallyRejectsUnsyncedEntry() async throws {
        let repository = try Self.makeRepository()
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-20"))

        do {
            try await repository.clearForLogout(force: false)
            Issue.record("미동기 행이 있으면 비강행 clear를 거부해야 합니다.")
        } catch let error as LogoutDataError {
            #expect(error == .unsyncedEntriesRemain)
        }

        #expect(try await repository.count() == 1)
    }

    @Test("keyset 페이지네이션은 여러 페이지에서 무중복 무누락으로 date desc, id desc 순서를 유지한다")
    func keysetPaginationReadsAllRowsWithoutDuplicatesOrGaps() async throws {
        let repository = try Self.makeRepository()

        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-10", memo: "third"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-12", memo: "second"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-12", memo: "first"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-01", memo: "fourth"))

        let firstPage = try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: TransactionPageCursor?.none,
            size: 2
        )
        let firstCursor = try Self.cursor(from: #require(firstPage.last))
        let secondPage = try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: firstCursor,
            size: 2
        )
        let secondCursor = try Self.cursor(from: #require(secondPage.last))
        let thirdPage = try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: secondCursor,
            size: 2
        )

        let all = firstPage + secondPage + thirdPage
        let ids = try all.map { try #require($0.id) }

        #expect(firstPage.count == 2)
        #expect(secondPage.count == 2)
        #expect(thirdPage.isEmpty)
        #expect(all.map { $0.memo } == ["first", "second", "third", "fourth"])
        let uniqueStoredIDCount = Set(ids).count
        #expect(uniqueStoredIDCount == ids.count)
        #expect(ids.count == 4)
    }

    @Test("같은 transaction_date 다수건은 id desc로 tie-break 된다")
    func sameDateRowsAreOrderedByDescendingID() async throws {
        let repository = try Self.makeRepository()

        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-15", memo: "oldest"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-15", memo: "middle"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-15", memo: "newest"))

        let page = try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: TransactionPageCursor?.none,
            size: 10
        )
        let ids = try page.map { try #require($0.id) }

        #expect(page.map { $0.memo } == ["newest", "middle", "oldest"])
        #expect(ids == ids.sorted(by: >))
    }

    @Test("월-스코프 필터는 해당 월 1일을 포함하고 다음 달 1일은 제외한다")
    func monthScopeIncludesStartAndExcludesNextMonthStart() async throws {
        let repository = try Self.makeRepository()

        try await repository.insert(Self.makeTransaction(transactionDate: "2026-06-30", memo: "previous"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-01", memo: "start"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-31", memo: "inside"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-08-01", memo: "next"))

        let july = try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: TransactionPageCursor?.none,
            size: 10
        )

        #expect(july.map { $0.memo } == ["inside", "start"])
    }

    @Test("월 전체 조회는 해당 월 거래를 date desc, id desc 순서로 모두 반환한다")
    func allMonthReadsAllRowsInHistoryOrder() async throws {
        let repository = try Self.makeRepository()

        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-12", memo: "old same day"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-08-01", memo: "next month"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-12", memo: "new same day"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-07-01", memo: "month start"))
        try await repository.insert(Self.makeTransaction(transactionDate: "2026-06-30", memo: "previous month"))

        let july = try await repository.all(month: LedgerMonth(year: 2026, month: 7))

        #expect(july.map { $0.memo } == ["new same day", "old same day", "month start"])
    }
}

extension TransactionRepositoryTests {
    @Test("clientEntryID 단건 조회는 일치 행을 반환하고 없는 ID는 nil이다")
    func transactionFetchesOneEntryOrNil() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "01010101-0101-0101-0101-010101010101"))
        try await repository.insert(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("123.4500"),
            transactionDate: "2026-07-11",
            memo: "single"
        ))

        let stored = try #require(try await repository.transaction(clientEntryID: clientEntryID))
        let expectedAmount = try Self.decimal("123.45")

        #expect(stored.clientEntryID == clientEntryID)
        #expect(stored.amount == expectedAmount)
        #expect(stored.memo == "single")
        #expect(try await repository.transaction(clientEntryID: UUID()) == nil)
    }

    @Test("update는 수정 가능 필드 전체와 잠정 환산값을 교체하고 식별·생성 필드는 보존한다")
    func updateReplacesEditableFieldsAndPreservesIdentity() async throws {
        let repository = try Self.makeRepository()
        let clientEntryID = try #require(UUID(uuidString: "02020202-0202-0202-0202-020202020202"))
        try await repository.upsertFromServer(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("1.25"),
            transactionDate: "2026-07-01",
            memo: "old",
            pending: false,
            createdAt: "2020-01-01T00:00:00Z",
            updatedAt: "2020-01-02T00:00:00Z",
            syncState: .synced
        ))
        let original = try #require(try await repository.transaction(clientEntryID: clientEntryID))

        let didUpdate = try await repository.update(Self.makeTransaction(
            clientEntryID: clientEntryID,
            amount: Self.decimal("99999999.123456789"),
            currencyCode: "USD",
            categoryID: 42,
            assetID: 84,
            transactionType: .income,
            transactionDate: "2026-07-24",
            memo: nil,
            pending: true,
            appliedRate: Self.decimal("1325.123456789"),
            rateBaseDate: "2026-07-23",
            krwAmount: Self.decimal("132512345678.987654321"),
            createdAt: "2099-01-01T00:00:00Z",
            updatedAt: "2099-01-02T00:00:00Z",
            syncState: .synced
        ))

        let stored = try #require(try await repository.transaction(clientEntryID: clientEntryID))
        let expectedAmount = try Self.decimal("99999999.123456789")
        let expectedRate = try Self.decimal("1325.123456789")
        let expectedKRWAmount = try Self.decimal("132512345678.987654321")
        #expect(didUpdate && stored.syncState == .pendingPush)
        #expect(stored.id == original.id && stored.clientEntryID == original.clientEntryID)
        #expect(stored.createdAt == original.createdAt && stored.updatedAt != original.updatedAt)
        #expect(stored.updatedAt != "2099-01-02T00:00:00Z")
        #expect(stored.amount == expectedAmount && stored.currencyCode == "USD")
        #expect(stored.categoryID == 42 && stored.assetID == 84)
        #expect(stored.transactionType == .income && stored.transactionDate == "2026-07-24")
        #expect(stored.memo == nil && stored.pending)
        #expect(stored.appliedRate == expectedRate && stored.rateBaseDate == "2026-07-23")
        #expect(stored.krwAmount == expectedKRWAmount)
    }

    @Test("update는 없는 ID에 false를 반환하고 다른 행을 변경하지 않는다")
    func updateMissingEntryReturnsFalseWithoutChanges() async throws {
        let repository = try Self.makeRepository()
        let existingID = try #require(UUID(uuidString: "03030303-0303-0303-0303-030303030303"))
        try await repository.insert(Self.makeTransaction(
            clientEntryID: existingID,
            transactionDate: "2026-07-03",
            memo: "untouched"
        ))
        let before = try #require(try await repository.transaction(clientEntryID: existingID))

        let didUpdate = try await repository.update(Self.makeTransaction(
            clientEntryID: UUID(),
            amount: Self.decimal("999"),
            transactionDate: "2026-07-24"
        ))

        #expect(!didUpdate)
        #expect(try await repository.transaction(clientEntryID: existingID) == before)
        #expect(try await repository.count() == 1)
    }
}

extension TransactionRepositoryTests {
    static func makeRepository() throws -> TransactionRepository {
        try makeRepositoryAndDatabase().repository
    }

    static func makeRepositoryAndDatabase() throws -> (repository: TransactionRepository, database: AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (TransactionRepository(database: database), database)
    }

    static func makeTransaction(
        clientEntryID: UUID = UUID(),
        amount: Decimal = Decimal(100),
        currencyCode: String = "KRW",
        categoryID: Int = 1,
        assetID: Int = 1,
        transactionType: LocalTransaction.TransactionType = .expense,
        transactionDate: String,
        memo: String? = nil,
        pending: Bool = false,
        appliedRate: Decimal? = nil,
        rateBaseDate: String? = nil,
        krwAmount: Decimal? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        syncState: SyncState = .pendingPush
    ) -> LocalTransaction {
        LocalTransaction(
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
            updatedAt: updatedAt,
            syncState: syncState
        )
    }

    static func pushedPayload(
        amount: Decimal = Decimal(100),
        currencyCode: String = "KRW",
        categoryID: Int = 1,
        assetID: Int = 1,
        transactionDate: String,
        memo: String? = nil
    ) -> TransactionRepository.PushedPayload {
        TransactionRepository.PushedPayload(
            amount: amount,
            currencyCode: currencyCode,
            categoryID: categoryID,
            assetID: assetID,
            transactionDate: transactionDate,
            memo: memo
        )
    }

    static func decimal(_ text: String) throws -> Decimal {
        try #require(DecimalTextConversion.decimal(from: text))
    }

    static func cursor(from transaction: LocalTransaction) throws -> TransactionPageCursor {
        try TransactionPageCursor(transactionDate: transaction.transactionDate, id: #require(transaction.id))
    }
}
