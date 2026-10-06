//
//  BudgetEditTestFixture.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 편집 테스트(`BudgetEditLinesTests` · `BudgetEditLineOrderTests`)가 함께 쓰는 응답 픽스처.
enum BudgetEditTestFixture {
    @MainActor
    static func yearMonth(_ year: Int, _ month: Int) -> ServerMonth {
        ServerMonth(year: year, month: month)
    }

    /// 계약 모양의 줄. 몫이 없으면 사용액만, 몫이 있으면 쓴 돈 0 은 NONE · 그 밖은 IN_PROGRESS(픽스처는 몫을 넘지 않는다).
    static func budgetLine(budget: Decimal?, spent: Decimal) -> BudgetLine {
        guard let budget else {
            return BudgetLine(
                budgetAmount: nil,
                actualAmount: spent,
                status: nil,
                percent: nil,
                remainingAmount: nil,
                overAmount: nil
            )
        }
        return BudgetLine(
            budgetAmount: budget,
            actualAmount: spent,
            status: spent == 0 ? BudgetStatus.none : .inProgress,
            percent: budget == 0 ? nil : NSDecimalNumber(decimal: spent * 100 / budget).intValue,
            remainingAmount: budget - spent,
            overAmount: nil
        )
    }

    static func categoryLine(
        _ id: Int,
        budget: Decimal?,
        spent: Decimal = 0,
        isDeleted: Bool = false
    ) -> BudgetCategoryLine {
        BudgetCategoryLine(
            category: Category(
                id: id, code: "FOOD", displayNameKo: "식비", displayNameEn: "Food", icon: "🍽️", sortOrder: id
            ),
            isDeleted: isDeleted,
            line: budgetLine(budget: budget, spent: spent)
        )
    }

    /// 예산이 있는 달(nil = 2026-10). 전체 쓴 돈 = 카테고리 쓴 돈 합, 결제수단은 몫이 없다.
    /// 그 외 카테고리 몫 = 전체 − 카테고리 몫 합, 0 이면 쓴 돈만 — 서버 규칙 그대로.
    @MainActor
    static func makeBudget(
        _ month: ServerMonth? = nil,
        total: Decimal,
        categories: [BudgetCategoryLine] = []
    ) -> MonthlyBudget {
        let month = month ?? yearMonth(2026, 10)
        let shares = categories.compactMap(\.line.budgetAmount).reduce(0, +)
        let spent = categories.map(\.line.actualAmount).reduce(0, +)
        let groups: [PaymentGroup] = [.creditCard, .cashAndDebit, .accountAndOther]
        let budget = MonthlyBudget(
            year: month.year,
            month: month.month,
            currentYear: 2026,
            currentMonth: 10,
            remainingDaysIncludingToday: month == yearMonth(2026, 10) ? 7 : nil,
            hasAnyBudget: true,
            status: spent == 0 ? BudgetStatus.none : .inProgress,
            currency: .krw,
            total: budgetLine(budget: total, spent: spent),
            paymentGroups: groups.map {
                BudgetPaymentGroupLine(paymentGroup: $0, line: budgetLine(budget: nil, spent: 0))
            },
            categories: categories,
            otherCategories: budgetLine(budget: total > shares ? total - shares : nil, spent: 0),
            missingRateCount: 0,
            dailyAllowance: nil,
            deletedCategoriesWithSpending: []
        )
        #expect(BudgetTabViewModel.isWellFormed(budget))
        return budget
    }

    /// 미설정 달(nil = 2026-10) — 계약상 통화·전체·그 외 카테고리가 nil 이고 결제수단·카테고리는 [] 이다.
    @MainActor
    static func makeNotSetBudget(_ month: ServerMonth? = nil) -> MonthlyBudget {
        let month = month ?? yearMonth(2026, 10)
        let budget = MonthlyBudget(
            year: month.year,
            month: month.month,
            currentYear: 2026,
            currentMonth: 10,
            remainingDaysIncludingToday: month == yearMonth(2026, 10) ? 7 : nil,
            hasAnyBudget: false,
            status: .notSet,
            currency: nil,
            total: nil,
            paymentGroups: [],
            categories: [],
            otherCategories: nil,
            missingRateCount: 0,
            dailyAllowance: nil,
            deletedCategoriesWithSpending: []
        )
        #expect(BudgetTabViewModel.isWellFormed(budget))
        return budget
    }
}
