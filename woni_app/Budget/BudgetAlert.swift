//
//  BudgetAlert.swift
//  woni_app
//

import Foundation

/// 예산 알림 기준. 원시값은 발송 기록 키에 들어간다.
enum BudgetAlertThreshold: String, CaseIterable {
    case nearLimit = "80"
    case reached = "100"
}

struct BudgetAlert: Equatable {
    let threshold: BudgetAlertThreshold
    let year: Int
    let month: Int
    let currency: CurrencyCode
    /// 80% 만 값이 있다.
    let remainingAmount: Decimal?
}

/// 서버가 방금 준 전체 줄 `status` 로만 알림을 정한다 — 기기에서 퍼센트·남은 돈을 세지 않는다(스펙 §2.6).
enum BudgetAlertDecision {
    /// 보낼 알림과 함께 기록할 기준들. 보낼 것이 없으면 nil.
    /// 응답의 이번 달만 판정하고(스펙 §5), 둘 다 처음 넘었으면 100% 만 보내고 80% 는 보낸 것으로 친다.
    static func decide(
        _ budget: MonthlyBudget,
        isSent: (BudgetAlertThreshold) -> Bool
    ) -> (alert: BudgetAlert, record: [BudgetAlertThreshold])? {
        guard budget.year == budget.currentYear,
              budget.month == budget.currentMonth,
              budget.status != .notSet,
              let currency = budget.currency,
              let total = budget.total,
              total.budgetAmount != nil,
              let status = total.status
        else {
            return nil
        }

        switch status {
        case .nearLimit:
            // 계약상 넘었을 때만 nil 이다 — 없으면 깨진 응답이라 보내지 않는다.
            guard !isSent(.nearLimit), let remaining = total.remainingAmount else {
                return nil
            }
            let alert = BudgetAlert(
                threshold: .nearLimit,
                year: budget.year,
                month: budget.month,
                currency: currency,
                remainingAmount: remaining
            )
            return (alert, [.nearLimit])
        case .reached, .exceeded:
            guard !isSent(.reached) else {
                return nil
            }
            let alert = BudgetAlert(
                threshold: .reached,
                year: budget.year,
                month: budget.month,
                currency: currency,
                remainingAmount: nil
            )
            return (alert, [.nearLimit, .reached])
        case .notSet, .none, .inProgress:
            return nil
        }
    }

    /// 기록 키 = (계정, 달, 기준, 응답의 예산 통화, 전체 금액). 응답이 키를 만들 수 없으면(통화·전체 금액 없음) nil.
    /// 금액은 `Decimal.description`(기기 로케일과 무관한 POSIX 형식)으로 적는다.
    static func recordKey(userID: UUID, budget: MonthlyBudget, threshold: BudgetAlertThreshold) -> String? {
        guard let currency = budget.currency, let totalAmount = budget.total?.budgetAmount else {
            return nil
        }
        return [
            userID.uuidString,
            "\(budget.year)-\(budget.month)",
            threshold.rawValue,
            currency.rawValue,
            totalAmount.description
        ].joined(separator: "|")
    }

    /// 알림 본문(ko·en).
    static func body(for alert: BudgetAlert, language: AppLanguage) -> String {
        let monthName = monthName(alert.month, language: language)
        switch alert.threshold {
        case .nearLimit:
            guard let remaining = alert.remainingAmount else {
                preconditionFailure("An 80% budget alert must carry the remaining amount")
            }
            let code = alert.currency.rawValue
            let remainingText = "\(code) \(CurrencyFormat.string(remaining, currencyCode: code))"
            return WoniStrings.budgetAlertNearLimit(
                monthName: monthName,
                remainingText: remainingText,
                language: language
            )
        case .reached:
            return WoniStrings.budgetAlertUsedUp(monthName: monthName, language: language)
        }
    }

    /// `YearMonthPickerOverlay.monthLabel` 과 같은 방식.
    private static func monthName(_ month: Int, language: AppLanguage) -> String {
        switch language {
        case .ko:
            "\(month)\(WoniStrings.monthSuffix(language))"
        case .en:
            WoniDateFormat.monthName(month: month, calendar: WoniDateFormat.defaultCalendar)
        }
    }
}

/// 발송 기록 — 기기에 남기고 로그아웃·purge·계정 전환 때 비운다(step 5 가 훅에 잇는다).
@MainActor
final class BudgetAlertRecordStore {
    private let userDefaults: UserDefaults
    private static let sentKey = "woni.app.budgetAlerts.sent"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func contains(_ key: String) -> Bool {
        sentKeys.contains(key)
    }

    func insert(_ keys: [String]) {
        userDefaults.set(sentKeys.union(keys).sorted(), forKey: Self.sentKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.sentKey)
    }

    private var sentKeys: Set<String> {
        Set(userDefaults.stringArray(forKey: Self.sentKey) ?? [])
    }
}
