//
//  MonthReportAggregator.swift
//  woni_app
//

import Foundation

enum MonthReportAggregator {
    static func categoryItems(
        transactions: [LocalTransaction],
        kind: MainSummaryItem.Kind,
        baseAmount: (LocalTransaction) -> Decimal?
    ) -> [ReportCategoryItem] {
        var categories: [Int: (amount: Decimal, representative: LocalTransaction)] = [:]

        for transaction in transactions where transaction.matches(kind) {
            guard let amount = baseAmount(transaction) else { continue }

            if var category = categories[transaction.categoryID] {
                category.amount += amount
                if isMoreRecent(transaction, than: category.representative) {
                    category.representative = transaction
                }
                categories[transaction.categoryID] = category
            } else {
                categories[transaction.categoryID] = (amount, transaction)
            }
        }

        let sortedCategories = categories.sorted { lhs, rhs in
            if lhs.value.amount != rhs.value.amount {
                return lhs.value.amount > rhs.value.amount
            }
            return lhs.key < rhs.key
        }
        let total = sortedCategories.reduce(Decimal(0)) { $0 + $1.value.amount }

        return sortedCategories.enumerated().map { rank, category in
            ReportCategoryItem(
                categoryID: category.key,
                categorySnapshot: category.value.representative.categorySnapshot,
                amount: category.value.amount,
                percent: percent(amount: category.value.amount, total: total),
                colorRank: rank
            )
        }
    }

    static func donutSlices(
        items: [ReportCategoryItem],
        total: Decimal
    ) -> [ReportDonutSlice] {
        guard total != 0 else {
            return items.map { ReportDonutSlice(categoryID: $0.categoryID, start: 0, end: 0) }
        }

        var cumulative = 0.0
        return items.enumerated().map { index, item in
            let start = cumulative
            let isLast = index == items.index(before: items.endIndex)
            let end = isLast
                ? 1.0
                : cumulative + NSDecimalNumber(decimal: item.amount / total).doubleValue
            cumulative = end
            return ReportDonutSlice(categoryID: item.categoryID, start: start, end: end)
        }
    }

    // swiftlint:disable:next function_parameter_count
    static func entryRows(
        transactions: [LocalTransaction],
        categoryID: Int,
        field: ReportSortField,
        isDescending: Bool,
        baseAmount: (LocalTransaction) -> Decimal?,
        memo: (LocalTransaction) -> String?
    ) -> [ReportEntryRow] {
        transactions.compactMap { transaction in
            guard transaction.categoryID == categoryID,
                  let amount = baseAmount(transaction)
            else {
                return nil
            }

            return ReportEntryRow(
                id: transaction.clientEntryID,
                transactionDate: transaction.transactionDate,
                amount: amount,
                memo: memo(transaction)
            )
        }.sorted { lhs, rhs in
            if field == .date, lhs.transactionDate != rhs.transactionDate {
                return isDescending
                    ? lhs.transactionDate > rhs.transactionDate
                    : lhs.transactionDate < rhs.transactionDate
            }
            if field == .amount, lhs.amount != rhs.amount {
                return isDescending ? lhs.amount > rhs.amount : lhs.amount < rhs.amount
            }
            return lhs.id < rhs.id
        }
    }

    private static func isMoreRecent(
        _ candidate: LocalTransaction,
        than current: LocalTransaction
    ) -> Bool {
        if candidate.transactionDate != current.transactionDate {
            return candidate.transactionDate > current.transactionDate
        }
        return candidate.clientEntryID > current.clientEntryID
    }

    private static func percent(amount: Decimal, total: Decimal) -> Int {
        guard total != 0 else { return 0 }

        var rawPercent = amount / total * 100
        if rawPercent > 0, rawPercent < 1 {
            return 1
        }

        var roundedPercent = Decimal()
        NSDecimalRound(&roundedPercent, &rawPercent, 0, .plain)
        return NSDecimalNumber(decimal: roundedPercent).intValue
    }
}

private extension LocalTransaction {
    func matches(_ kind: MainSummaryItem.Kind) -> Bool {
        switch kind {
        case .expense:
            transactionType == .expense
        case .income:
            transactionType == .income
        case .total:
            // 합계 탭은 expense와 income을 각각 집계해 합성하므로 total 직접 조회는 비운다.
            false
        }
    }
}
