//
//  WoniStringsReport.swift
//  woni_app
//

import Foundation

extension WoniStrings {
    static func reportMonthOverview(
        month: Int,
        language: AppLanguage,
        calendar: Calendar = WoniDateFormat.defaultCalendar
    ) -> String {
        switch language {
        case .ko: "\(month)월 전체"
        case .en: "\(WoniDateFormat.monthName(month: month, calendar: calendar)) overview"
        }
    }

    static func reportMonthEmpty(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "표시할 내역이 없어요"
        case .en: "Nothing to show this month"
        }
    }

    static func reportTabEmptyTitle(
        _ kind: MainSummaryItem.Kind,
        language: AppLanguage
    ) -> String {
        switch (language, kind) {
        case (.ko, .expense): "이 달 지출이 없어요"
        case (.ko, .income): "이 달 수입이 없어요"
        case (.en, .expense): "No expenses this month"
        case (.en, .income): "No income this month"
        case (_, .total): reportMonthEmpty(language)
        }
    }

    static func reportTabEmptyHint(
        _ kind: MainSummaryItem.Kind,
        language: AppLanguage
    ) -> String {
        switch (language, kind) {
        case (.ko, .expense): "위 수입을 누르면 수입 카테고리를 볼 수 있어요"
        case (.ko, .income): "위 지출을 누르면 지출 카테고리를 볼 수 있어요"
        case (.en, .expense): "Tap Income above to see income categories"
        case (.en, .income): "Tap Expense above to see expense categories"
        case (_, .total): ""
        }
    }

    static func reportRemaining(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "남은 돈"
        case .en: "Remaining"
        }
    }

    static func reportSortDate(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "날짜"
        case .en: "Date"
        }
    }

    static func reportSortAmount(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "금액"
        case .en: "Amount"
        }
    }

    static func reportDonutAccessibility(
        kind: MainSummaryItem.Kind,
        total: (amount: String, currency: SelectableCurrency),
        leading: (category: String, percent: Int),
        moreCategoryCount: Int,
        language: AppLanguage
    ) -> String {
        let mode: String
        switch (language, kind) {
        case (.ko, .expense): mode = "지출"
        case (.ko, .income): mode = "수입"
        case (.en, .expense): mode = "Expenses"
        case (.en, .income): mode = "Income"
        case (.ko, .total): mode = "합계"
        case (.en, .total): mode = "Total"
        }

        let localizedAmount: String
        switch (language, total.currency) {
        case (.ko, .krw): localizedAmount = "\(total.amount)원"
        case (.en, .krw): localizedAmount = "₩\(total.amount)"
        default: localizedAmount = "\(total.currency.rawValue) \(total.amount)"
        }

        let summary = "\(mode) \(localizedAmount), \(leading.category) \(leading.percent)%"
        guard moreCategoryCount > 0 else {
            return summary
        }

        switch language {
        case .ko: return "\(summary) 외 \(moreCategoryCount)개 카테고리"
        case .en: return "\(summary) and \(moreCategoryCount) more categories"
        }
    }
}
