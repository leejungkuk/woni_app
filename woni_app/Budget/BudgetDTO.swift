//
//  BudgetDTO.swift
//  woni_app
//

import Foundation

/// 백엔드 `MonthlyBudgetResponse`에 1:1 대응하는 서버 DTO.
/// 금액은 부동소수점 금지 → `Decimal`. 서버 nullable 은 Optional.
struct MonthlyBudgetDTO: Decodable {
    let year: Int
    let month: Int
    let currentYear: Int
    let currentMonth: Int
    let remainingDaysIncludingToday: Int?
    let hasAnyBudget: Bool
    let status: BudgetStatus
    let currency: CurrencyCode?
    let total: BudgetLineDTO?
    let paymentGroups: [BudgetPaymentGroupLineDTO]
    let categories: [BudgetCategoryLineDTO]
    let otherCategories: BudgetLineDTO?
    let missingRateCount: Int
    let dailyAllowance: DailyAllowanceDTO?
}

/// 백엔드 `BudgetLine`.
struct BudgetLineDTO: Decodable {
    let budgetAmount: Decimal?
    let actualAmount: Decimal
    let status: BudgetStatus?
    let percent: Int?
    let remainingAmount: Decimal?
    let overAmount: Decimal?
}

/// 백엔드 `BudgetPaymentGroupLine`. 계약처럼 `BudgetLine` 필드가 같은 층에 평평하게 온다.
struct BudgetPaymentGroupLineDTO: Decodable {
    let paymentGroup: PaymentGroup
    let line: BudgetLineDTO

    private enum CodingKeys: String, CodingKey {
        case paymentGroup
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paymentGroup = try container.decode(PaymentGroup.self, forKey: .paymentGroup)
        line = try BudgetLineDTO(from: decoder)
    }
}

/// 백엔드 `BudgetCategoryLine`. 계약처럼 `BudgetLine` 필드가 같은 층에 평평하게 온다.
struct BudgetCategoryLineDTO: Decodable {
    let category: CategoryDTO
    let deleted: Bool
    let line: BudgetLineDTO

    private enum CodingKeys: String, CodingKey {
        case category
        case deleted
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(CategoryDTO.self, forKey: .category)
        deleted = try container.decode(Bool.self, forKey: .deleted)
        line = try BudgetLineDTO(from: decoder)
    }
}

/// 백엔드 `DailyAllowance`.
struct DailyAllowanceDTO: Decodable {
    let amount: Decimal?
    let exceeded: Bool
}

/// 백엔드 `SaveBudgetRequest`. 몫이 없으면 빈 배열로 보낸다.
struct SaveBudgetRequest: Encodable {
    let currency: CurrencyCode
    let totalAmount: Decimal
    let paymentGroupAmounts: [PaymentGroupAmountRequest]
    let categoryAmounts: [CategoryAmountRequest]
}

/// 백엔드 `PaymentGroupAmountRequest`.
struct PaymentGroupAmountRequest: Encodable {
    let paymentGroup: PaymentGroup
    let amount: Decimal
}

/// 백엔드 `CategoryAmountRequest`.
struct CategoryAmountRequest: Encodable {
    let categoryId: Int
    let amount: Decimal
}

extension MonthlyBudgetDTO {
    /// 서버 DTO → 도메인 모델 매핑(DTO가 뷰에 직접 침투하지 않게 분리). 배열 순서는 서버가 준 그대로다.
    func toDomain() -> MonthlyBudget {
        MonthlyBudget(
            year: year,
            month: month,
            currentYear: currentYear,
            currentMonth: currentMonth,
            remainingDaysIncludingToday: remainingDaysIncludingToday,
            hasAnyBudget: hasAnyBudget,
            status: status,
            currency: currency,
            total: total?.toDomain(),
            paymentGroups: paymentGroups.map {
                BudgetPaymentGroupLine(paymentGroup: $0.paymentGroup, line: $0.line.toDomain())
            },
            categories: categories.map {
                BudgetCategoryLine(category: $0.category.toDomain(), isDeleted: $0.deleted, line: $0.line.toDomain())
            },
            otherCategories: otherCategories?.toDomain(),
            missingRateCount: missingRateCount,
            dailyAllowance: dailyAllowance.map { DailyAllowance(amount: $0.amount, isExceeded: $0.exceeded) }
        )
    }
}

extension BudgetLineDTO {
    func toDomain() -> BudgetLine {
        BudgetLine(
            budgetAmount: budgetAmount,
            actualAmount: actualAmount,
            status: status,
            percent: percent,
            remainingAmount: remainingAmount,
            overAmount: overAmount
        )
    }
}
