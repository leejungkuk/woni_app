//
//  BudgetModels.swift
//  woni_app
//

import Foundation

/// 백엔드 `BudgetStatus` enum. 모르는 값은 기본값으로 바꾸지 않고 해석 실패로 둔다.
enum BudgetStatus: String, Decodable {
    case notSet = "NOT_SET"
    case none = "NONE"
    case inProgress = "IN_PROGRESS"
    case nearLimit = "NEAR_LIMIT"
    case reached = "REACHED"
    case exceeded = "EXCEEDED"
}

/// 백엔드 `PaymentGroup` enum. 직렬화 값은 enum name이다.
enum PaymentGroup: String, Codable {
    case creditCard = "CREDIT_CARD"
    case cashAndDebit = "CASH_AND_DEBIT"
    case accountAndOther = "ACCOUNT_AND_OTHER"
}

/// 예산 한 줄(전체·결제수단·카테고리·그 외 카테고리 공통). 표시값은 서버가 계산한 값 그대로다.
/// 몫이 없는 줄은 `actualAmount` 만 있고 나머지는 nil.
struct BudgetLine {
    let budgetAmount: Decimal?
    let actualAmount: Decimal
    let status: BudgetStatus?
    let percent: Int?
    let remainingAmount: Decimal?
    let overAmount: Decimal?
}

struct BudgetPaymentGroupLine {
    let paymentGroup: PaymentGroup
    let line: BudgetLine
}

struct BudgetCategoryLine {
    let category: Category
    let isDeleted: Bool
    let line: BudgetLine
}

/// 하루 권장액. 초과면 `amount` 가 nil.
struct DailyAllowance: Equatable {
    let amount: Decimal?
    let isExceeded: Bool
}

/// 화면에서 사용하는 월 예산 도메인 모델. 서버 DTO(`MonthlyBudgetDTO`)와 분리한다.
struct MonthlyBudget {
    let year: Int
    let month: Int
    let currentYear: Int
    let currentMonth: Int
    let remainingDaysIncludingToday: Int?
    let hasAnyBudget: Bool
    let status: BudgetStatus
    let currency: CurrencyCode?
    let total: BudgetLine?
    let paymentGroups: [BudgetPaymentGroupLine]
    let categories: [BudgetCategoryLine]
    let otherCategories: BudgetLine?
    let missingRateCount: Int
    let dailyAllowance: DailyAllowance?
    /// 그 달 지출 거래가 1건 이상 있는 삭제된 지출 카테고리. 순서는 서버가 준 그대로다.
    let deletedCategoriesWithSpending: [Category]
}
