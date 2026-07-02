//
//  TransactionRepositoryTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct TransactionRepositoryTests {
    @Test("insert는 pending 거래를 저장하고 Decimal과 nil 확정 필드를 보존한다")
    func insertStoresPendingTransactionAndRoundTripsDecimal() async throws {
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
            memo: "coffee"
        ))

        let transactions = try await repository.page(
            month: LedgerMonth(year: 2026, month: 7),
            after: Optional<Cursor>.none,
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
            after: Optional<Cursor>.none,
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
        #expect(Set(ids).count == ids.count)
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
            after: Optional<Cursor>.none,
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
            after: Optional<Cursor>.none,
            size: 10
        )

        #expect(july.map { $0.memo } == ["inside", "start"])
    }
}

private extension TransactionRepositoryTests {
    static func makeRepository() throws -> TransactionRepository {
        try TransactionRepository(database: AppDatabase.inMemory())
    }

    static func makeTransaction(
        clientEntryID: UUID = UUID(),
        amount: Decimal = Decimal(100),
        currencyCode: String = "KRW",
        categoryID: Int = 1,
        assetID: Int = 1,
        transactionType: LocalTransaction.TransactionType = .expense,
        transactionDate: String,
        memo: String? = nil
    ) -> LocalTransaction {
        LocalTransaction(
            clientEntryID: clientEntryID,
            amount: amount,
            currencyCode: currencyCode,
            categoryID: categoryID,
            assetID: assetID,
            transactionType: transactionType,
            transactionDate: transactionDate,
            memo: memo
        )
    }

    static func decimal(_ text: String) throws -> Decimal {
        try #require(DecimalTextConversion.decimal(from: text))
    }

    static func cursor(from transaction: LocalTransaction) throws -> Cursor {
        Cursor(
            transactionDate: transaction.transactionDate,
            id: try #require(transaction.id)
        )
    }
}
