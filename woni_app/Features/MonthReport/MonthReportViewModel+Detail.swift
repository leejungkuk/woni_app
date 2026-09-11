//
//  MonthReportViewModel+Detail.swift
//  woni_app
//

import Foundation

extension MonthReportViewModel {
    /// 상세 화면 표시 모델. entryRows(categoryID:)를 한 번만 호출한다.
    func categoryDetail(categoryID: Int) -> ReportCategoryDetail {
        let rows = historyRows(categoryID: categoryID)
        let sections = sortField == .date ? dateSections(rows) : amountSections(rows)
        return ReportCategoryDetail(
            periodText: monthTitle,
            entryCountText: WoniStrings.reportEntryCountLabel(rows.count, language: language),
            totalText: formatBaseAmount(categoryTotal(categoryID: categoryID)),
            tone: sections.first?.tone ?? .expense,
            sections: sections
        )
    }
}

private extension MonthReportViewModel {
    func historyRows(categoryID: Int) -> [(entry: ReportEntryRow, row: MainHistoryRow)] {
        entryRows(categoryID: categoryID).compactMap { entry in
            // 같은 displaySnapshot에서 파생된 행이므로 원 거래 조회는 nil이 될 수 없다.
            guard let transaction = transaction(clientEntryID: entry.id) else { return nil }
            let row = MainHistoryRow(
                id: entry.id,
                title: entry.memo,
                categoryAssetText: "\(categoryDisplayName(categoryID: categoryID)) · "
                    + assetDisplayName(id: transaction.assetID),
                exchangeInfoText: exchangeInfoText(for: transaction),
                amountText: formatBaseAmount(entry.amount),
                secondaryAmountText: transaction.currencyCode != baseCurrency.rawValue
                    ? "\(transaction.currencyCode) "
                    + CurrencyFormat.string(transaction.amount, currencyCode: transaction.currencyCode) : nil,
                tone: transaction.transactionType == .expense ? .expense : .income
            )
            return (entry, row)
        }
    }

    func dateSections(_ rows: [(entry: ReportEntryRow, row: MainHistoryRow)]) -> [ReportDetailSection] {
        var sections: [ReportDetailSection] = []
        var start = rows.startIndex
        while start < rows.endIndex {
            let first = rows[start]
            var end = start + 1
            while end < rows.endIndex, rows[end].entry.transactionDate == first.entry.transactionDate {
                end += 1
            }
            let group = rows[start ..< end]
            let subtotal = group.reduce(Decimal(0)) { $0 + $1.entry.amount }
            sections.append(ReportDetailSection(
                id: first.entry.transactionDate,
                dateTitle: entryDateText(first.entry.transactionDate),
                subtotalText: (first.row.tone == .expense ? "-" : "+") + formatBaseAmount(subtotal),
                tone: first.row.tone,
                rows: group.map(\.row)
            ))
            start = end
        }
        return sections
    }

    func amountSections(_ rows: [(entry: ReportEntryRow, row: MainHistoryRow)]) -> [ReportDetailSection] {
        rows.map { entry, row in
            ReportDetailSection(
                id: row.id.uuidString.lowercased(),
                dateTitle: entryDateText(entry.transactionDate),
                subtotalText: nil,
                tone: row.tone,
                rows: [row]
            )
        }
    }

    func assetDisplayName(id: Int) -> String {
        assetsByID[id].map { language == .ko ? $0.displayNameKo : $0.displayNameEn }
            ?? WoniStrings.unassigned(language)
    }
}
