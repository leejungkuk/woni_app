//
//  BudgetDTOTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 월 예산 응답·요청 DTO 검증. 서버 JSON → `MonthlyBudgetDTO` → `toDomain()` 과 `SaveBudgetRequest` 인코딩.
/// 앱 타깃 기본 격리(MainActor)로 합성된 Codable 준수와 격리를 맞추기 위해 @MainActor.
@MainActor
struct BudgetDTOTests {
    @Test("설정된 달 응답을 해석해 금액·상태·null·카테고리·그룹 순서를 도메인으로 옮긴다")
    func decodesSetMonthAndMapsToDomain() throws {
        let budget = try decode(setMonthJSON).toDomain()

        #expect(budget.year == 2026)
        #expect(budget.month == 5)
        #expect(budget.currentYear == 2026)
        #expect(budget.currentMonth == 5)
        #expect(budget.remainingDaysIncludingToday == 7)
        #expect(budget.hasAnyBudget)
        #expect(budget.status == .nearLimit)
        #expect(budget.currency == .krw)
        #expect(budget.missingRateCount == 2)

        let total = try #require(budget.total)
        #expect(try total.budgetAmount == decimal("1000000"))
        #expect(try total.actualAmount == decimal("856000"))
        #expect(total.status == .nearLimit)
        #expect(total.percent == 85)
        #expect(try total.remainingAmount == decimal("144000"))
        #expect(total.overAmount == nil)

        // 서버가 준 순서 그대로 — 선언 순서도 사전순도 아닌 순서로 보낸다.
        #expect(budget.paymentGroups.map(\.paymentGroup) == [.cashAndDebit, .creditCard, .accountAndOther])
        let cash = budget.paymentGroups[0].line
        #expect(try cash.budgetAmount == decimal("300000"))
        #expect(try cash.actualAmount == decimal("120000"))
        #expect(cash.status == .inProgress)
        #expect(cash.percent == 40)
        let card = budget.paymentGroups[1].line
        #expect(card.status == .exceeded)
        #expect(card.percent == nil)
        #expect(card.remainingAmount == nil)
        #expect(try card.overAmount == decimal("100000"))
        try expectActualOnly(budget.paymentGroups[2].line, actual: "36000")

        #expect(budget.categories.count == 2)
        let food = budget.categories[0]
        #expect(food.category.id == 3)
        #expect(food.category.code == "FOOD")
        #expect(food.category.displayNameKo == "식비")
        #expect(food.category.displayNameEn == "Food")
        #expect(food.isDeleted == false)
        #expect(try food.line.budgetAmount == decimal("700000"))
        #expect(food.line.percent == 74)
        let hobby = budget.categories[1]
        #expect(hobby.category.id == 101)
        #expect(hobby.category.icon == nil)
        #expect(hobby.isDeleted)
        #expect(hobby.line.status == BudgetStatus.none)

        try expectActualOnly(#require(budget.otherCategories), actual: "337000")

        let allowance = try #require(budget.dailyAllowance)
        #expect(try allowance.amount == decimal("20571"))
        #expect(allowance.isExceeded == false)
    }

    @Test("미설정 달은 null 과 빈 배열로 오고 다른 달의 예산 여부는 그대로 온다")
    func decodesNotSetMonthWithNullsAndEmptyArrays() throws {
        let budget = try decode(notSetMonthJSON).toDomain()

        #expect(budget.year == 2026)
        #expect(budget.month == 4)
        #expect(budget.currentMonth == 5)
        #expect(budget.remainingDaysIncludingToday == nil)
        #expect(budget.hasAnyBudget)
        #expect(budget.status == .notSet)
        #expect(budget.currency == nil)
        #expect(budget.total == nil)
        #expect(budget.paymentGroups.isEmpty)
        #expect(budget.categories.isEmpty)
        #expect(budget.otherCategories == nil)
        #expect(budget.missingRateCount == 0)
        #expect(budget.dailyAllowance == nil)
    }

    @Test("JSON 숫자 금액이 Decimal(string:) 과 정확히 같다")
    func decodesAmountsWithoutPrecisionLoss() throws {
        let budget = try decode(precisionJSON).toDomain()

        let total = try #require(budget.total)
        #expect(try total.budgetAmount == decimal("99999999.99"))
        #expect(try total.actualAmount == decimal("0.01"))
        #expect(try total.remainingAmount == decimal("99999999.98"))
        let card = try #require(budget.paymentGroups.first).line
        #expect(try card.budgetAmount == decimal("1234567.89"))
        #expect(try card.remainingAmount == decimal("1234567.88"))
        #expect(try budget.dailyAllowance?.amount == decimal("1234567.89"))
    }

    @Test("초과 줄은 넘은 돈만 있고 하루 권장액은 금액 없이 초과로 온다")
    func decodesExceededLineAndDailyAllowance() throws {
        let budget = try decode(exceededJSON).toDomain()

        #expect(budget.status == .exceeded)
        let total = try #require(budget.total)
        #expect(total.status == .exceeded)
        #expect(total.percent == nil)
        #expect(total.remainingAmount == nil)
        #expect(try total.overAmount == decimal("0.01"))
        #expect(try total.actualAmount == decimal("500.01"))

        let allowance = try #require(budget.dailyAllowance)
        #expect(allowance.amount == nil)
        #expect(allowance.isExceeded)
    }

    @Test("모르는 상태·결제수단 값은 기본값으로 바꾸지 않고 해석 오류를 던진다")
    func rejectsUnknownEnumValues() throws {
        // 대조: 바꾸기 전 픽스처는 해석된다 — 오류의 원인이 바꾼 값 하나뿐임을 보인다.
        _ = try decode(notSetMonthJSON)
        _ = try decode(setMonthJSON)

        let unknownStatus = notSetMonthJSON.replacingOccurrences(of: "\"NOT_SET\"", with: "\"OFF\"")
        let unknownGroup = setMonthJSON.replacingOccurrences(of: "\"CREDIT_CARD\"", with: "\"POINTS\"")
        #expect(unknownStatus != notSetMonthJSON)
        #expect(unknownGroup != setMonthJSON)

        expectDataCorrupted { try decode(unknownStatus) }
        expectDataCorrupted { try decode(unknownGroup) }
    }

    @Test("줄에서 actualAmount 가 빠지면 0 으로 메우지 않고 해석 오류를 던진다")
    func rejectsMissingActualAmount() {
        let totalWithout = setMonthJSON.replacingOccurrences(of: "\"actualAmount\": 856000, ", with: "")
        let groupWithout = setMonthJSON.replacingOccurrences(of: "\"actualAmount\": 36000, ", with: "")
        #expect(totalWithout != setMonthJSON)
        #expect(groupWithout != setMonthJSON)

        expectKeyNotFound("actualAmount") { try decode(totalWithout) }
        expectKeyNotFound("actualAmount") { try decode(groupWithout) }
    }

    @Test("저장 요청은 계약 키로 금액 자릿수를 그대로 인코딩한다")
    func encodesSaveRequestWithExactAmounts() throws {
        let request = try SaveBudgetRequest(
            currency: .usd,
            totalAmount: decimal("99999999.99"),
            paymentGroupAmounts: [PaymentGroupAmountRequest(paymentGroup: .creditCard, amount: decimal("0.01"))],
            categoryAmounts: [CategoryAmountRequest(categoryId: 3, amount: decimal("1234567.89"))]
        )

        let data = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["currency", "totalAmount", "paymentGroupAmounts", "categoryAmounts"])
        #expect(object["currency"] as? String == "USD")
        let group = try #require((object["paymentGroupAmounts"] as? [[String: Any]])?.first)
        #expect(Set(group.keys) == ["paymentGroup", "amount"])
        #expect(group["paymentGroup"] as? String == "CREDIT_CARD")
        let category = try #require((object["categoryAmounts"] as? [[String: Any]])?.first)
        #expect(Set(category.keys) == ["categoryId", "amount"])
        #expect(category["categoryId"] as? Int == 3)

        // 금액은 파싱한 숫자가 아니라 인코딩된 글자로 본다 — 부동소수점을 거치면 자릿수가 달라진다.
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"totalAmount\":99999999.99"))
        #expect(json.contains("\"amount\":0.01"))
        #expect(json.contains("\"amount\":1234567.89"))
    }

    @Test("몫이 없으면 두 배열을 생략하지 않고 빈 배열로 보낸다")
    func encodesEmptyAllocationsAsEmptyArrays() throws {
        let request = SaveBudgetRequest(
            currency: .krw,
            totalAmount: 0,
            paymentGroupAmounts: [],
            categoryAmounts: []
        )

        let data = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try #require(object["paymentGroupAmounts"] as? [Any])
        let categories = try #require(object["categoryAmounts"] as? [Any])
        #expect(groups.isEmpty)
        #expect(categories.isEmpty)
        #expect(object["totalAmount"] as? Int == 0)
    }
}

// MARK: - Helpers

private func decode(_ json: String) throws -> MonthlyBudgetDTO {
    try JSONDecoder().decode(MonthlyBudgetDTO.self, from: Data(json.utf8))
}

/// 몫이 없는 줄 모양: `actualAmount` 만 있고 나머지 다섯은 null.
private func expectActualOnly(_ line: BudgetLine, actual: String) throws {
    #expect(try line.actualAmount == decimal(actual))
    #expect(line.budgetAmount == nil)
    #expect(line.status == nil)
    #expect(line.percent == nil)
    #expect(line.remainingAmount == nil)
    #expect(line.overAmount == nil)
}

private func expectDataCorrupted(_ body: () throws -> MonthlyBudgetDTO) {
    do {
        _ = try body()
        Issue.record("해석 오류를 기대했지만 해석되었다")
    } catch DecodingError.dataCorrupted {
        // 기대한 실패 — 모르는 raw 값
    } catch {
        Issue.record("dataCorrupted 를 기대했지만 \(error)")
    }
}

private func expectKeyNotFound(_ key: String, _ body: () throws -> MonthlyBudgetDTO) {
    do {
        _ = try body()
        Issue.record("해석 오류를 기대했지만 해석되었다")
    } catch let DecodingError.keyNotFound(missing, _) {
        #expect(missing.stringValue == key)
    } catch {
        Issue.record("keyNotFound(\(key)) 를 기대했지만 \(error)")
    }
}

// MARK: - Fixtures (백엔드 MonthlyBudgetResponse 모양, null 은 키 생략 없이 null)

private let setMonthJSON = """
{
  "year": 2026, "month": 5, "currentYear": 2026, "currentMonth": 5,
  "remainingDaysIncludingToday": 7, "hasAnyBudget": true, "status": "NEAR_LIMIT", "currency": "KRW",
  "total": {"budgetAmount": 1000000, "actualAmount": 856000, "status": "NEAR_LIMIT", "percent": 85,
            "remainingAmount": 144000, "overAmount": null},
  "paymentGroups": [
    {"paymentGroup": "CASH_AND_DEBIT", "budgetAmount": 300000, "actualAmount": 120000, "status": "IN_PROGRESS",
     "percent": 40, "remainingAmount": 180000, "overAmount": null},
    {"paymentGroup": "CREDIT_CARD", "budgetAmount": 600000, "actualAmount": 700000, "status": "EXCEEDED",
     "percent": null, "remainingAmount": null, "overAmount": 100000},
    {"paymentGroup": "ACCOUNT_AND_OTHER", "budgetAmount": null, "actualAmount": 36000, "status": null,
     "percent": null, "remainingAmount": null, "overAmount": null}
  ],
  "categories": [
    {"category": {"id": 3, "code": "FOOD", "displayNameKo": "식비", "displayNameEn": "Food", "icon": "fork.knife",
                  "sortOrder": 1},
     "deleted": false, "budgetAmount": 700000, "actualAmount": 519000, "status": "IN_PROGRESS", "percent": 74,
     "remainingAmount": 181000, "overAmount": null},
    {"category": {"id": 101, "code": "CUSTOM_101", "displayNameKo": "취미", "displayNameEn": "Hobby", "icon": null,
                  "sortOrder": 50},
     "deleted": true, "budgetAmount": 300000, "actualAmount": 0, "status": "NONE", "percent": 0,
     "remainingAmount": 300000, "overAmount": null}
  ],
  "otherCategories": {"budgetAmount": null, "actualAmount": 337000, "status": null, "percent": null,
                      "remainingAmount": null, "overAmount": null},
  "missingRateCount": 2,
  "dailyAllowance": {"amount": 20571, "exceeded": false}
}
"""

private let notSetMonthJSON = """
{
  "year": 2026, "month": 4, "currentYear": 2026, "currentMonth": 5,
  "remainingDaysIncludingToday": null, "hasAnyBudget": true, "status": "NOT_SET", "currency": null,
  "total": null, "paymentGroups": [], "categories": [], "otherCategories": null,
  "missingRateCount": 0, "dailyAllowance": null
}
"""

private let precisionJSON = """
{
  "year": 2026, "month": 5, "currentYear": 2026, "currentMonth": 5,
  "remainingDaysIncludingToday": 7, "hasAnyBudget": true, "status": "IN_PROGRESS", "currency": "USD",
  "total": {"budgetAmount": 99999999.99, "actualAmount": 0.01, "status": "IN_PROGRESS", "percent": 0,
            "remainingAmount": 99999999.98, "overAmount": null},
  "paymentGroups": [
    {"paymentGroup": "CREDIT_CARD", "budgetAmount": 1234567.89, "actualAmount": 0.01, "status": "IN_PROGRESS",
     "percent": 0, "remainingAmount": 1234567.88, "overAmount": null}
  ],
  "categories": [],
  "otherCategories": {"budgetAmount": 99999999.99, "actualAmount": 0.01, "status": "IN_PROGRESS", "percent": 0,
                      "remainingAmount": 99999999.98, "overAmount": null},
  "missingRateCount": 0,
  "dailyAllowance": {"amount": 1234567.89, "exceeded": false}
}
"""

private let exceededJSON = """
{
  "year": 2026, "month": 5, "currentYear": 2026, "currentMonth": 5,
  "remainingDaysIncludingToday": 7, "hasAnyBudget": true, "status": "EXCEEDED", "currency": "USD",
  "total": {"budgetAmount": 500.00, "actualAmount": 500.01, "status": "EXCEEDED", "percent": null,
            "remainingAmount": null, "overAmount": 0.01},
  "paymentGroups": [],
  "categories": [],
  "otherCategories": {"budgetAmount": null, "actualAmount": 500.01, "status": null, "percent": null,
                      "remainingAmount": null, "overAmount": null},
  "missingRateCount": 0,
  "dailyAllowance": {"amount": null, "exceeded": true}
}
"""
