//
//  BudgetTotalPresentation.swift
//  woni_app
//

import Foundation
import SwiftUI

/// 예산 막대의 그리기용 비율. 금액·상태는 서버 값 그대로이고 이 비율만 기기에서 센다.
struct BudgetBarFill: Equatable {
    /// 넘지 않았으면 사용 ÷ 예산(0~1). 넘었으면 예산 눈금 = 예산 ÷ (예산 + 넘은 돈) — 그 오른쪽이 넘친 구간이다.
    let ratio: Double
    let isOver: Bool

    /// 몫이 없는 줄(예산 없음)과 넘은 돈이 없는 초과 줄은 막대를 만들지 않는다.
    init?(line: BudgetLine) {
        guard let budget = line.budgetAmount else {
            return nil
        }
        if line.status == .exceeded {
            // 표시 사용액으로 세지 않는다 — 사용액은 내림이라 1.00 예산에 1.004 를 쓰면 1.00 으로 보여
            // 넘친 구간이 0 이 된다(스펙 §3 V6). 넘은 돈은 올림이라 늘 0 보다 크다.
            guard let over = line.overAmount, over > 0 else {
                return nil
            }
            ratio = Self.double(budget / (budget + over))
            isOver = true
        } else {
            ratio = budget > 0 ? min(Self.double(line.actualAmount / budget), 1) : 0
            isOver = false
        }
    }

    /// 넘친 구간이 시작하는 x(예산 눈금). 넘친 구간은 막대 두께보다 좁아지지 않는다. 넘지 않았으면 nil.
    func tickX(width: CGFloat, thickness: CGFloat) -> CGFloat? {
        guard isOver else {
            return nil
        }
        return max(min(width * ratio, width - thickness), 0)
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

/// 예산 탭 총액 카드의 표시 규칙. 퍼센트·남은 돈·넘은 돈·상태·하루 권장액은 서버 값 그대로 쓴다(스펙 §2.6).
/// 기기에서 세는 것은 막대 비율과 오늘 표시선 위치뿐이다.
struct BudgetTotalPresentation {
    static let barThickness: CGFloat = 14

    let heroLabel: String
    let heroAmount: Decimal
    let heroText: String
    let heroColor: Color
    let currencyCode: String
    let usedOverBudgetText: String
    let statusText: String
    let statusColor: Color
    let bar: BudgetBarFill
    /// 오늘의 자리 = (그 달 일수 − 남은 일수 + 1) ÷ 그 달 일수. 이번 달이고 전체 예산이 0 보다 클 때만 있다.
    let todayRatio: Double?
    let infoText: String
    let dailyText: String?
    let missingLines: [String]

    /// (i) 는 표시선이 보이는 카드에만 둔다.
    var showsInfo: Bool {
        todayRatio != nil
    }

    /// 미설정 달이거나 계약상 있어야 할 값(통화·전체 예산·상태·남은 돈 또는 넘은 돈)이 없으면 nil —
    /// 빈 값을 기본값으로 메워 카드를 그리지 않는다.
    init?(content: BudgetTabContent, language: AppLanguage) {
        let budget = content.budget
        guard let currency = budget.currency,
              let total = budget.total,
              let budgetAmount = total.budgetAmount,
              let status = total.status,
              let statusText = Self.statusWording(status, percent: total.percent, language: language),
              let bar = BudgetBarFill(line: total)
        else {
            return nil
        }
        let isOver = status == .exceeded
        guard let heroAmount = isOver ? total.overAmount : total.remainingAmount else {
            return nil
        }
        let code = currency.rawValue
        let remainingDays = Self.remainingDaysThisMonth(budget)

        heroLabel = WoniStrings.budgetHeroLabel(isOver: isOver, language: language)
        self.heroAmount = heroAmount
        heroText = CurrencyFormat.string(heroAmount, currencyCode: code)
        heroColor = isOver ? WoniColor.terracotta100 : WoniColor.gray100
        currencyCode = code
        usedOverBudgetText = CurrencyFormat.string(total.actualAmount, currencyCode: code)
            + " / " + CurrencyFormat.string(budgetAmount, currencyCode: code)
        self.statusText = statusText
        statusColor = status == .none ? WoniColor.gray80 : WoniColor.terracotta100
        self.bar = bar
        todayRatio = budgetAmount > 0
            ? remainingDays.flatMap { Self.dayRatio(year: budget.year, month: budget.month, remainingDays: $0) }
            : nil
        infoText = WoniStrings.budgetTodayMarkerInfo(language)
        dailyText = remainingDays.flatMap { days in
            budget.dailyAllowance.map {
                Self.dailyWording($0, remainingDays: days, currencyCode: code, language: language)
            }
        }
        missingLines = [
            content.unsyncedExpenseCount > 0
                ? WoniStrings.budgetUnsyncedExcluded(content.unsyncedExpenseCount, language: language) : nil,
            budget.missingRateCount > 0
                ? WoniStrings.budgetMissingRateExcluded(budget.missingRateCount, language: language) : nil
        ].compactMap { $0 }
    }

    /// 표시선의 x. 넘친 막대에서는 막대 전체 폭이 아니라 예산 눈금 위치 × 날짜 비율이다(V3).
    func todayMarkerX(barWidth: CGFloat) -> CGFloat? {
        guard let todayRatio else {
            return nil
        }
        let span = bar.tickX(width: barWidth, thickness: Self.barThickness) ?? barWidth
        return span * todayRatio
    }
}

private extension BudgetTotalPresentation {
    /// 이번 달 판정은 응답 하나 안에서 한다 — ViewModel 의 서버 달과 섞지 않는다. 이번 달이 아니면 nil.
    static func remainingDaysThisMonth(_ budget: MonthlyBudget) -> Int? {
        guard budget.year == budget.currentYear,
              budget.month == budget.currentMonth,
              let days = budget.remainingDaysIncludingToday
        else {
            return nil
        }
        return days
    }

    /// 그 달 일수는 응답의 달을 서울 gregorian 으로 센다 — 기기 달력·기기 시계를 쓰지 않는다.
    static func dayRatio(year: Int, month: Int, remainingDays: Int) -> Double? {
        let calendar = WoniDateFormat.defaultCalendar
        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)?.count,
              (1 ... daysInMonth).contains(remainingDays)
        else {
            return nil
        }
        return Double(daysInMonth - remainingDays + 1) / Double(daysInMonth)
    }

    /// 미설정 달이거나 진행 중·임박인데 퍼센트가 없으면 nil.
    static func statusWording(_ status: BudgetStatus, percent: Int?, language: AppLanguage) -> String? {
        switch status {
        case .notSet:
            return nil
        case .none:
            return WoniStrings.budgetStatusNothingSpent(language)
        case .inProgress, .nearLimit:
            return percent.map { WoniStrings.budgetStatusPercentUsed($0, language: language) }
        case .reached:
            return WoniStrings.budgetStatusUsedUp(language)
        case .exceeded:
            return WoniStrings.budgetStatusOver(language)
        }
    }

    static func dailyWording(
        _ allowance: DailyAllowance,
        remainingDays: Int,
        currencyCode: String,
        language: AppLanguage
    ) -> String {
        guard let amount = allowance.amount, amount > 0 else {
            return WoniStrings.budgetDailyNothingLeft(days: remainingDays, language: language)
        }
        let amountText = CurrencyFormat.string(amount, currencyCode: currencyCode)
        return WoniStrings.budgetDailyAllowance(days: remainingDays, amountText: amountText, language: language)
    }
}
