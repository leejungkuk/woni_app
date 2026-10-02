//
//  WoniStringsBudget.swift
//  woni_app
//

import Foundation

/// 예산 탭 총액 카드 문구(UI_GUIDE "월 예산 화면"·en 표).
extension WoniStrings {
    static func budgetHeroLabel(isOver: Bool, language: AppLanguage) -> String {
        switch (language, isOver) {
        case (.ko, false): "남은 돈"
        case (.ko, true): "넘은 돈"
        case (.en, false): "Remaining"
        case (.en, true): "Over by"
        }
    }

    static func budgetStatusNothingSpent(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "아직 쓰지 않았습니다"
        case .en: "Nothing spent yet"
        }
    }

    static func budgetStatusPercentUsed(_ percent: Int, language: AppLanguage) -> String {
        switch language {
        case .ko: "\(percent)% 썼습니다"
        case .en: "\(percent)% used"
        }
    }

    static func budgetStatusUsedUp(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산을 다 썼습니다"
        case .en: "Budget used up"
        }
    }

    static func budgetStatusOver(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산을 넘었습니다"
        case .en: "Over budget"
        }
    }

    static func budgetDailyAllowance(days: Int, amountText: String, language: AppLanguage) -> String {
        switch language {
        case .ko: "남은 \(days)일, 하루 \(amountText)씩 쓸 수 있습니다"
        case .en: "\(budgetDaysLeft(days)) · \(amountText) a day"
        }
    }

    static func budgetDailyNothingLeft(days: Int, language: AppLanguage) -> String {
        switch language {
        case .ko: "남은 \(days)일, 더 쓸 수 있는 돈이 없습니다"
        case .en: "\(budgetDaysLeft(days)) · nothing remaining"
        }
    }

    static func budgetTodayMarkerInfo(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "▼는 이번 달 중 오늘의 자리입니다. 막대가 ▼를 넘었다면 예산을 고르게 나눠 쓸 때보다 많이 쓴 것입니다."
        case .en: "▼ marks today in this month. If the bar has passed ▼, you're spending faster than an even pace."
        }
    }

    static func budgetUnsyncedExcluded(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .ko: "동기화 전 거래 \(count)건은 아직 빠져 있습니다."
        case .en: count == 1 ? "1 unsynced entry isn't included yet." : "\(count) unsynced entries aren't included yet."
        }
    }

    static func budgetMissingRateExcluded(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .ko: "환율이 없는 거래 \(count)건은 빠져 있습니다."
        case .en: count == 1
            ? "1 entry without an exchange rate isn't included."
            : "\(count) entries without an exchange rate aren't included."
        }
    }

    private static func budgetDaysLeft(_ days: Int) -> String {
        days == 1 ? "1 day left" : "\(days) days left"
    }
}
