//
//  BudgetAlert.swift
//  woni_app
//

import Foundation

/// 예산 알림 기준. 원시값은 알림 기록 키에 들어간다.
enum BudgetAlertThreshold: String, CaseIterable {
    case nearLimit = "80"
    case reached = "100"
}

/// 띄울 예산 알림창 하나. 금액·남은 날은 판정한 응답의 서버 값 그대로다 — 기기에서 세지 않는다(스펙 §2.6 금액·§2.7 남은 일수).
struct BudgetAlert: Equatable {
    let threshold: BudgetAlertThreshold
    let year: Int
    let month: Int
    let currency: CurrencyCode
    /// 80% 만 값이 있다(전체 줄 `remainingAmount`).
    let remainingAmount: Decimal?
    /// 100% 이고 넘었을 때(`EXCEEDED`)만 값이 있다(전체 줄 `overAmount`). 딱 100%(`REACHED`)는 nil.
    let overAmount: Decimal?
    let remainingDaysIncludingToday: Int?
    let dailyAllowance: DailyAllowance?
}

/// 서버가 방금 준 전체 줄 `status` 로만 알림을 정한다 — 기기에서 퍼센트·남은 돈을 세지 않는다(스펙 §2.6).
enum BudgetAlertDecision {
    /// 띄울 창과 그 창을 띄우면 기록할 기준들. 띄울 것이 없으면 nil.
    /// 응답의 이번 달만 판정하고(스펙 §5), 둘 다 처음 넘었으면 100% 만 띄우고 80% 는 알린 것으로 친다.
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
            // 계약상 넘었을 때만 nil 이다 — 없으면 깨진 응답이라 띄우지 않는다.
            guard !isSent(.nearLimit), let remaining = total.remainingAmount else {
                return nil
            }
            let alert = BudgetAlert(
                threshold: .nearLimit,
                year: budget.year,
                month: budget.month,
                currency: currency,
                remainingAmount: remaining,
                overAmount: nil,
                remainingDaysIncludingToday: budget.remainingDaysIncludingToday,
                dailyAllowance: budget.dailyAllowance
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
                remainingAmount: nil,
                overAmount: status == .exceeded ? total.overAmount : nil,
                remainingDaysIncludingToday: budget.remainingDaysIncludingToday,
                dailyAllowance: budget.dailyAllowance
            )
            return (alert, [.nearLimit, .reached])
        case .notSet, .none, .inProgress:
            return nil
        }
    }

    /// 기록 키 = (계정, 달, 기준, 응답의 예산 통화, 전체 금액). 응답이 키를 만들 수 없으면(통화·전체 금액 없음) nil.
    /// 금액은 `Decimal.description`(기기 로케일과 무관한 POSIX 형식)으로 적는다.
    static func recordKey(userID: UUID, budget: MonthlyBudget, threshold: BudgetAlertThreshold) -> String? {
        key(userID: userID, budget: budget, slot: threshold.rawValue)
    }

    /// 이 기기가 그 예산(계정·달·통화·전체 금액)을 확인했다는 표시 키. 기준 자리가 `seen` 이라 기준 키와 겹치지 않고,
    /// 발송 기록과 같은 저장소에 있어 `BudgetAlertRecordStore.clear()` 가 함께 비운다(UI_GUIDE "넘는 걸 본 기기만 띄운다").
    static func confirmationKey(userID: UUID, budget: MonthlyBudget) -> String? {
        key(userID: userID, budget: budget, slot: "seen")
    }

    private static func key(userID: UUID, budget: MonthlyBudget, slot: String) -> String? {
        guard let currency = budget.currency, let totalAmount = budget.total?.budgetAmount else {
            return nil
        }
        return [
            userID.uuidString,
            "\(budget.year)-\(budget.month)",
            slot,
            currency.rawValue,
            totalAmount.description
        ].joined(separator: "|")
    }
}

/// 알림 기록 — 창이 뜬 순간(`BudgetAlertEvaluator.markShown`) 기기에 남기고 로그아웃·purge·계정 전환 때 비운다.
/// 이 기기가 예산을 확인했다는 표시(`BudgetAlertDecision.confirmationKey`)도 같은 키에 함께 둔다.
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
