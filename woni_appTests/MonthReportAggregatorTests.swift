//
//  MonthReportAggregatorTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@MainActor
struct MonthReportAggregatorTests {
    @Test("퍼센트는 합 100을 강제하지 않고 1% 미만의 양수를 1로 표시한다")
    func percentagesAreRoundedIndependently() {
        let transactions = [
            makeTransaction(amount: 999, categoryID: 10),
            makeTransaction(amount: 1, categoryID: 20)
        ]

        let items = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .expense,
            baseAmount: { $0.amount }
        )

        #expect(items.map(\.percent) == [100, 1])
        #expect(items.map(\.percent).reduce(0, +) == 101)
    }

    @Test("지출과 수입 거래는 요청한 kind별로 분리해 집계한다")
    func categoryItemsFilterByKind() {
        let transactions = [
            makeTransaction(amount: 100, transactionType: .expense),
            makeTransaction(amount: 40, transactionType: .income)
        ]

        let expenses = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .expense,
            baseAmount: { $0.amount }
        )
        let incomes = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .income,
            baseAmount: { $0.amount }
        )

        #expect(expenses.map(\.amount) == [100])
        #expect(incomes.map(\.amount) == [40])
    }

    @Test("카테고리 소계와 퍼센트는 주입된 환산 금액을 사용한다")
    func categoryItemsUseConvertedAmounts() {
        let transactions = [
            makeTransaction(amount: 2, currencyCode: "USD", categoryID: 10),
            makeTransaction(
                clientEntryID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
                amount: 1,
                currencyCode: "USD",
                categoryID: 10,
                transactionDate: "2026-08-02"
            ),
            makeTransaction(amount: 400, categoryID: 20)
        ]

        let items = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .expense,
            baseAmount: { $0.currencyCode == "USD" ? $0.amount * 1300 : $0.amount }
        )

        #expect(items.map(\.categoryID) == [10, 20])
        #expect(items.map(\.amount) == [3900, 400])
        #expect(items.map(\.percent) == [91, 9])
    }

    @Test("총합 0과 환산 전부 실패는 0 나눗셈 없이 빈 조각 또는 0 조각을 만든다")
    func zeroTotalProducesOnlyZeroFractions() {
        let emptyItems = MonthReportAggregator.categoryItems(
            transactions: [],
            kind: .expense,
            baseAmount: { _ in nil }
        )
        let unavailableItems = MonthReportAggregator.categoryItems(
            transactions: [makeTransaction(amount: 100, categoryID: 10)],
            kind: .expense,
            baseAmount: { _ in nil }
        )
        let zeroItems = MonthReportAggregator.categoryItems(
            transactions: [makeTransaction(amount: 0, categoryID: 10)],
            kind: .expense,
            baseAmount: { $0.amount }
        )

        #expect(emptyItems.isEmpty)
        #expect(unavailableItems.isEmpty)
        #expect(MonthReportAggregator.donutSlices(items: emptyItems, total: 0).isEmpty)
        #expect(zeroItems.map(\.percent) == [0])
        #expect(
            MonthReportAggregator.donutSlices(items: zeroItems, total: 0)
                == [ReportDonutSlice(categoryID: 10, start: 0, end: 0)]
        )
    }

    @Test("동액 카테고리는 ID 오름차순으로 결정적 rank를 받는다")
    func equalAmountsUseCategoryIDTieBreak() {
        let transactions = [
            makeTransaction(amount: 50, categoryID: 20),
            makeTransaction(amount: 50, categoryID: 10)
        ]

        let first = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .expense,
            baseAmount: { $0.amount }
        )
        let second = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .expense,
            baseAmount: { $0.amount }
        )

        #expect(first.map(\.categoryID) == [10, 20])
        #expect(first.map(\.colorRank) == [0, 1])
        #expect(first == second)
    }

    @Test("11개 이상 카테고리의 rank는 자르지 않고 0부터 연속한다")
    func colorRanksRemainContinuousBeyondPaletteSize() {
        let transactions = (0 ..< 11).map { index in
            makeTransaction(amount: Decimal(11 - index), categoryID: 100 + index)
        }

        let items = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .expense,
            baseAmount: { $0.amount }
        )

        #expect(items.map(\.colorRank) == Array(0 ..< 11))
    }

    @Test("대표 스냅샷은 최신 날짜와 가장 큰 UUID로 고르고 입력 순서에 의존하지 않는다")
    func representativeSnapshotUsesLatestDeterministicTransaction() throws {
        let olderID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000000"))
        let latestLowID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000000"))
        let latestHighID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000000"))
        let transactions = [
            makeTransaction(
                clientEntryID: latestLowID,
                amount: 10,
                categoryID: 10,
                categorySnapshot: "latest-low",
                transactionDate: "2026-08-02"
            ),
            makeTransaction(
                clientEntryID: olderID,
                amount: 10,
                categoryID: 10,
                categorySnapshot: "older",
                transactionDate: "2026-08-01"
            ),
            makeTransaction(
                clientEntryID: latestHighID,
                amount: 10,
                categoryID: 10,
                categorySnapshot: "latest-high",
                transactionDate: "2026-08-02"
            )
        ]

        let forward = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .expense,
            baseAmount: { $0.amount }
        )
        let reversed = MonthReportAggregator.categoryItems(
            transactions: transactions.reversed(),
            kind: .expense,
            baseAmount: { $0.amount }
        )

        #expect(forward.first?.categorySnapshot == "latest-high")
        #expect(forward == reversed)
    }

    @Test("환산 불가 거래는 소계와 퍼센트 및 조각에서 제외한다")
    func unavailableConversionsAreExcluded() {
        let transactions = [
            makeTransaction(amount: 70, categoryID: 10),
            makeTransaction(amount: 900, currencyCode: "USD", categoryID: 10),
            makeTransaction(amount: 30, categoryID: 20)
        ]

        let items = MonthReportAggregator.categoryItems(
            transactions: transactions,
            kind: .expense,
            baseAmount: { $0.currencyCode == "USD" ? nil : $0.amount }
        )
        let slices = MonthReportAggregator.donutSlices(items: items, total: 100)

        #expect(items.map(\.amount) == [70, 30])
        #expect(items.map(\.percent) == [70, 30])
        #expect(slices.map(\.categoryID) == [10, 20])
        #expect(slices.map(\.end) == [0.7, 1.0])
    }

    @Test("상세 정렬은 날짜와 금액의 양방향에서 UUID 오름차순 tie-break를 쓴다")
    func entryRowsSupportAllSortCombinations() throws {
        let firstID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000000"))
        let secondID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000000"))
        let thirdID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000000"))
        let transactions = [
            makeTransaction(clientEntryID: thirdID, amount: 10, transactionDate: "2026-08-02"),
            makeTransaction(clientEntryID: secondID, amount: 10, transactionDate: "2026-08-01"),
            makeTransaction(clientEntryID: firstID, amount: 20, transactionDate: "2026-08-01")
        ]

        func sortedIDs(field: ReportSortField, descending: Bool) -> [UUID] {
            MonthReportAggregator.entryRows(
                transactions: transactions,
                categoryID: 10,
                field: field,
                isDescending: descending,
                baseAmount: { $0.amount },
                memo: { $0.memo }
            ).map(\.id)
        }

        #expect(sortedIDs(field: .date, descending: false) == [firstID, secondID, thirdID])
        #expect(sortedIDs(field: .date, descending: true) == [thirdID, firstID, secondID])
        #expect(sortedIDs(field: .amount, descending: false) == [secondID, thirdID, firstID])
        #expect(sortedIDs(field: .amount, descending: true) == [firstID, secondID, thirdID])
    }

    @Test("상세 행은 카테고리와 환산 가능 여부를 거르고 환산 금액과 메모를 사용한다")
    func entryRowsFilterAndUseInjectedValues() throws {
        let includedID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000000"))
        let otherCategoryID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000000"))
        let unavailableID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000000"))
        let transactions = [
            makeTransaction(
                clientEntryID: includedID,
                amount: 2,
                currencyCode: "USD",
                memo: "included"
            ),
            makeTransaction(
                clientEntryID: otherCategoryID,
                amount: 999,
                categoryID: 20,
                memo: "other category"
            ),
            makeTransaction(
                clientEntryID: unavailableID,
                amount: 3,
                currencyCode: "JPY",
                memo: "unavailable"
            )
        ]

        let rows = MonthReportAggregator.entryRows(
            transactions: transactions,
            categoryID: 10,
            field: .date,
            isDescending: false,
            baseAmount: {
                if $0.currencyCode == "JPY" { return nil }
                return $0.currencyCode == "USD" ? $0.amount * 1300 : $0.amount
            },
            memo: { $0.memo.map { "memo: \($0)" } }
        )

        #expect(rows == [
            ReportEntryRow(
                id: includedID,
                transactionDate: "2026-08-01",
                amount: 2600,
                memo: "memo: included"
            )
        ])
    }

    @Test("도넛 조각은 서로 맞닿고 마지막 end를 정확히 1로 확정한다")
    func donutSlicesCloseRoundingGap() {
        let items = [10, 20, 30, 40, 50, 60, 70].enumerated().map { rank, categoryID in
            ReportCategoryItem(
                categoryID: categoryID,
                categorySnapshot: nil,
                amount: 1,
                percent: 14,
                colorRank: rank
            )
        }

        let slices = MonthReportAggregator.donutSlices(items: items, total: 7)

        #expect(slices.first?.start == 0)
        #expect(slices.last?.end == 1.0)
        for index in slices.indices.dropFirst() {
            #expect(slices[index].start == slices[index - 1].end)
        }
        #expect(ReportDonutSlice(categoryID: 10, start: 0.25, end: 0.75).midAngleFraction == 0.5)
    }

    private func makeTransaction(
        clientEntryID: UUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
        amount: Decimal,
        currencyCode: String = "KRW",
        categoryID: Int = 10,
        categorySnapshot: String? = nil,
        transactionType: LocalTransaction.TransactionType = .expense,
        transactionDate: String = "2026-08-01",
        memo: String? = nil
    ) -> LocalTransaction {
        LocalTransaction(
            clientEntryID: clientEntryID,
            amount: amount,
            currencyCode: currencyCode,
            categoryID: categoryID,
            categorySnapshot: categorySnapshot,
            assetID: 20,
            transactionType: transactionType,
            transactionDate: transactionDate,
            memo: memo
        )
    }
}
