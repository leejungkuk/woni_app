//
//  BudgetServiceTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 읽기·저장·삭제 요청 모양과 실패 매핑 검증. 공용 스텁(`URLProtocolStub`)으로 실제 네트워크 없이 확인한다.
/// 응답 픽스처는 계약 스냅샷의 `MonthlyBudgetResponse` 모양 그대로다 — 네트워크 경로에서 실제 응답 해석을 본다.
@MainActor
struct BudgetServiceTests {
    @Test("읽기는 GET 에 year·month query 만 붙여 보내고 응답을 도메인으로 돌려준다")
    func fetchSendsGETWithYearMonthQuery() async throws {
        let (client, log) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: successEnvelope(setMonthJSON))
        }

        let budget = try await BudgetService(client: client).fetch(year: 2026, month: 5)

        let request = try #require(log.requests.first)
        #expect(log.requests.count == 1)
        #expect(request.method == "GET")
        #expect(request.url?.path == "/api/v1/budgets")
        #expect(request.url?.query == "year=2026&month=5")
        #expect(request.body == nil)
        #expect(budget.status == .nearLimit)
        #expect(budget.year == 2026)
        #expect(budget.month == 5)
    }

    @Test("서버 모양 응답의 중첩 금액은 자릿수 그대로, null 자리는 nil 로 온다")
    func fetchDecodesServerShapedMonthlyBudget() async throws {
        let (client, _) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: successEnvelope(setMonthJSON))
        }

        let budget = try await BudgetService(client: client).fetch(year: 2026, month: 5)

        #expect(budget.currency == .usd)
        #expect(budget.remainingDaysIncludingToday == 7)
        #expect(budget.missingRateCount == 1)
        let total = try #require(budget.total)
        #expect(try total.actualAmount == decimal("856.40"))
        #expect(try total.remainingAmount == decimal("143.60"))
        #expect(total.overAmount == nil)

        #expect(budget.paymentGroups.map(\.paymentGroup) == [.creditCard, .cashAndDebit, .accountAndOther])
        #expect(try budget.paymentGroups[0].line.overAmount == decimal("100.15"))
        #expect(try budget.paymentGroups[1].line.remainingAmount == decimal("179.75"))
        let account = budget.paymentGroups[2].line
        #expect(try account.actualAmount == decimal("36.00"))
        #expect(account.budgetAmount == nil)
        #expect(account.status == nil)

        #expect(budget.categories.map(\.category.id) == [3, 101])
        #expect(try budget.categories[0].line.actualAmount == decimal("519.40"))
        #expect(budget.categories[1].isDeleted)
        #expect(budget.categories[1].category.icon == nil)

        let other = try #require(budget.otherCategories)
        #expect(try other.overAmount == decimal("87.00"))
        #expect(other.remainingAmount == nil)

        let allowance = try #require(budget.dailyAllowance)
        #expect(try allowance.amount == decimal("20.51"))
        #expect(allowance.isExceeded == false)
    }

    @Test("저장은 PUT 에 같은 query 와 JSON 본문을 보내고 그 달 전체를 돌려준다")
    func saveSendsPUTWithQueryAndBody() async throws {
        let (client, log) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: successEnvelope(setMonthJSON))
        }
        let sent = try SaveBudgetRequest(
            currency: .usd,
            totalAmount: decimal("1000.00"),
            paymentGroupAmounts: [
                PaymentGroupAmountRequest(paymentGroup: .creditCard, amount: decimal("600.01")),
                PaymentGroupAmountRequest(paymentGroup: .cashAndDebit, amount: decimal("299.99"))
            ],
            categoryAmounts: [
                CategoryAmountRequest(categoryId: 3, amount: decimal("700.25")),
                CategoryAmountRequest(categoryId: 101, amount: decimal("49.75"))
            ]
        )

        let budget = try await BudgetService(client: client).save(year: 2026, month: 5, request: sent)

        let request = try #require(log.requests.first)
        #expect(log.requests.count == 1)
        #expect(request.method == "PUT")
        #expect(request.url?.path == "/api/v1/budgets")
        #expect(request.url?.query == "year=2026&month=5")
        #expect(request.headers["Content-Type"] == "application/json")
        let bodyData = try #require(request.body)
        let body = try JSONDecoder().decode(SentSaveBody.self, from: bodyData)
        #expect(try body == SentSaveBody(
            currency: "USD",
            totalAmount: decimal("1000.00"),
            paymentGroupAmounts: [
                .init(paymentGroup: "CREDIT_CARD", amount: decimal("600.01")),
                .init(paymentGroup: "CASH_AND_DEBIT", amount: decimal("299.99"))
            ],
            categoryAmounts: [
                .init(categoryId: 3, amount: decimal("700.25")),
                .init(categoryId: 101, amount: decimal("49.75"))
            ]
        ))
        // 파싱한 숫자가 아니라 인코딩된 글자로도 본다 — 부동소수점을 거치면 자릿수가 달라진다.
        let json = try #require(String(data: bodyData, encoding: .utf8))
        #expect(json.contains("\"amount\":600.01"))
        #expect(json.contains("\"amount\":299.99"))
        #expect(budget.status == .nearLimit)
        #expect(try budget.total?.budgetAmount == decimal("1000.00"))
    }

    @Test("삭제는 본문 없는 DELETE 에 같은 query 를 붙이고 미설정이 된 그 달을 돌려준다")
    func deleteSendsDELETEWithQueryAndReturnsResponse() async throws {
        let (client, log) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: successEnvelope(deletedMonthJSON))
        }

        let budget = try await BudgetService(client: client).delete(year: 2026, month: 5)

        let request = try #require(log.requests.first)
        #expect(log.requests.count == 1)
        #expect(request.method == "DELETE")
        #expect(request.url?.path == "/api/v1/budgets")
        #expect(request.url?.query == "year=2026&month=5")
        #expect(request.body == nil)
        #expect(budget.status == .notSet)
        #expect(budget.month == 5)
        #expect(budget.remainingDaysIncludingToday == 7)
        #expect(budget.total == nil)
        #expect(budget.paymentGroups.isEmpty)
    }

    @Test("모르는 상태 값은 기본값으로 바꾸지 않고 해석 오류를 던진다")
    func fetchThrowsDecodingErrorForUnknownStatus() async {
        let unknown = deletedMonthJSON.replacingOccurrences(of: "\"NOT_SET\"", with: "\"OFF\"")
        #expect(unknown != deletedMonthJSON)
        let (client, _) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: successEnvelope(unknown))
        }

        do {
            let budget = try await BudgetService(client: client).fetch(year: 2026, month: 5)
            Issue.record("해석 오류를 기대했지만 \(budget.status) 로 해석되었다")
        } catch APIError.decoding {
            // 기대한 실패
        } catch {
            Issue.record("APIError.decoding 을 기대했지만 \(error)")
        }
    }

    @Test("읽기 실패 봉투는 감싸지 않고 원래 APIError.server 를 그대로 던진다")
    func fetchPassesServerFailureThrough() async {
        let (client, _) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, statusCode: 400, body: failureEnvelope("INVALID_PARAMETER"))
        }

        do {
            let budget = try await BudgetService(client: client).fetch(year: 2026, month: 5)
            Issue.record("실패를 기대했지만 \(budget.status) 예산을 돌려받았다")
        } catch let APIError.server(code, _) {
            #expect(code == "INVALID_PARAMETER")
        } catch {
            Issue.record("APIError.server 를 기대했지만 \(error)")
        }
    }
}

extension BudgetServiceTests {
    @Test("저장의 선언된 코드 5개는 각자 타입 있는 실패가 된다")
    func saveMapsDeclaredCodes() async {
        let cases: [(code: String, expected: String)] = [
            ("BUDGET_INVALID_AMOUNT", "invalidAmount"),
            ("CATEGORY_NOT_FOUND", "categoryNotFound"),
            ("BUDGET_MONTH_OUT_OF_RANGE", "monthOutOfRange"),
            ("BUDGET_TOTAL_REQUIRED", "totalRequired"),
            ("BUDGET_ALLOCATION_EXCEEDS_TOTAL", "allocationExceedsTotal")
        ]

        for item in cases {
            let failure = await saveFailure(code: item.code)
            #expect(failure.map(caseName) == item.expected, "\(item.code)")
        }
    }

    @Test("저장의 그 밖의 코드는 .other 가 되고 원래 APIError.server 와 코드를 잃지 않는다")
    func saveMapsOtherCodesToOther() async {
        let codes = ["CONCURRENT_MODIFICATION", "BUDGET_INVALID_ALLOCATION", "REQUEST_BODY_TOO_LARGE", "SOMETHING_NEW"]

        for code in codes {
            let failure = await saveFailure(code: code)
            #expect(serverCode(inOther: failure) == code, "\(code)")
        }
    }

    @Test("삭제의 BUDGET_MONTH_OUT_OF_RANGE 는 .monthOutOfRange 가 된다")
    func deleteMapsMonthOutOfRange() async {
        let failure = await deleteFailure(code: "BUDGET_MONTH_OUT_OF_RANGE")

        #expect(failure.map(caseName) == "monthOutOfRange")
    }

    @Test("삭제가 선언하지 않은 CATEGORY_NOT_FOUND 와 그 밖의 코드는 .other 가 된다")
    func deleteMapsOtherCodesToOther() async {
        for code in ["CONCURRENT_MODIFICATION", "CATEGORY_NOT_FOUND"] {
            let failure = await deleteFailure(code: code)
            #expect(serverCode(inOther: failure) == code, "\(code)")
        }
    }

    @Test("저장의 전송 실패는 .other 가 되고 원래 APIError.transport 를 담는다")
    func saveMapsTransportFailureToOther() async {
        let (client, _) = makeStubbedClient { _ in
            throw URLError(.notConnectedToInternet)
        }

        let failure = await writeFailure {
            try await BudgetService(client: client).save(year: 2026, month: 5, request: sampleRequest())
        }

        guard case let .other(underlying) = failure, case APIError.transport = underlying else {
            Issue.record(".other(APIError.transport) 를 기대했지만 \(String(describing: failure))")
            return
        }
    }

    @Test("저장의 봉투 없는 HTTP 오류와 해석 실패는 .other 에 원래 오류를 담는다")
    func saveMapsHTTPAndDecodingFailuresToOther() async {
        let httpFailure = await saveFailure(status: 500, body: "<html>Internal Server Error</html>")
        if case let .other(underlying) = httpFailure, case let APIError.httpStatus(code, _) = underlying {
            #expect(code == 500)
        } else {
            Issue.record(".other(APIError.httpStatus) 를 기대했지만 \(String(describing: httpFailure))")
        }

        let decodingFailure = await saveFailure(status: 200, body: successEnvelope(#"{ "id": 1 }"#))
        guard case let .other(underlying) = decodingFailure, case APIError.decoding = underlying else {
            Issue.record(".other(APIError.decoding) 을 기대했지만 \(String(describing: decodingFailure))")
            return
        }
    }
}

// MARK: - 쓴 돈이 있는 삭제된 카테고리 목록 (인계 2026-10-05 §3)

extension BudgetServiceTests {
    @Test("BLO.S0-R1 읽기·저장 응답의 삭제된 카테고리 목록을 필드 그대로·서버 순서 그대로 돌려준다")
    func fetchAndSaveReturnDeletedCategoriesWithSpendingInServerOrder() async throws {
        let (client, _) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: successEnvelope(setMonthJSON))
        }
        let service = BudgetService(client: client)

        let fetched = try await service.fetch(year: 2026, month: 5)
        let saved = try await service.save(year: 2026, month: 5, request: sampleRequest())

        // 서버 순서(정렬값 61·64)는 id 오름차순과 반대다 — 앱이 다시 세우면 순서가 뒤집힌다.
        for budget in [fetched, saved] {
            let deleted = budget.deletedCategoriesWithSpending
            #expect(deleted.map(\.id) == [205, 188])
            #expect(deleted.map(\.code) == ["CUSTOM_205", "CUSTOM_188"])
            #expect(deleted.map(\.displayNameKo) == ["여행", "선물"])
            #expect(deleted.map(\.displayNameEn) == ["Travel", "Gift"])
            #expect(deleted.map(\.icon) == ["airplane", nil])
            #expect(deleted.map(\.sortOrder) == [61, 64])
        }
    }

    @Test("BLO.S0-R3 목록 키가 없는 응답은 빈 목록으로 메우지 않고 해석 오류를 던진다")
    func fetchThrowsDecodingErrorForMissingDeletedCategoriesWithSpending() async throws {
        // 대조: 키를 지우지 않은 응답은 해석된다 — 오류의 원인이 지운 키 하나뿐임을 보인다.
        let (intactClient, _) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: successEnvelope(deletedMonthJSON))
        }
        let intact = try await BudgetService(client: intactClient).fetch(year: 2026, month: 5)
        #expect(intact.deletedCategoriesWithSpending.isEmpty)

        let missing = deletedMonthJSON.replacingOccurrences(of: ", \"deletedCategoriesWithSpending\": []", with: "")
        #expect(missing != deletedMonthJSON)
        let (client, _) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: successEnvelope(missing))
        }

        do {
            let budget = try await BudgetService(client: client).fetch(year: 2026, month: 5)
            Issue.record("해석 오류를 기대했지만 목록 \(budget.deletedCategoriesWithSpending.count)개로 해석되었다")
        } catch let APIError.decoding(underlying) {
            guard case let DecodingError.keyNotFound(key, _) = underlying else {
                Issue.record("keyNotFound 를 기대했지만 \(underlying)")
                return
            }
            #expect(key.stringValue == "deletedCategoriesWithSpending")
        } catch {
            Issue.record("APIError.decoding 을 기대했지만 \(error)")
        }
    }
}

// MARK: - Helpers

private extension BudgetServiceTests {
    func saveFailure(code: String) async -> BudgetWriteError? {
        await saveFailure(status: httpStatus(of: code), body: failureEnvelope(code))
    }

    func saveFailure(status: Int, body: String) async -> BudgetWriteError? {
        let (client, _) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, statusCode: status, body: body)
        }
        return await writeFailure {
            try await BudgetService(client: client).save(year: 2026, month: 5, request: sampleRequest())
        }
    }

    func deleteFailure(code: String) async -> BudgetWriteError? {
        let (client, _) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, statusCode: httpStatus(of: code), body: failureEnvelope(code))
        }
        return await writeFailure {
            try await BudgetService(client: client).delete(year: 2026, month: 5)
        }
    }

    /// 쓰기가 `BudgetWriteError` 로 실패하면 그 실패를, 아니면 이슈를 남기고 nil.
    func writeFailure(_ operation: () async throws -> MonthlyBudget) async -> BudgetWriteError? {
        do {
            let budget = try await operation()
            Issue.record("실패를 기대했지만 \(budget.status) 예산을 돌려받았다")
        } catch let failure as BudgetWriteError {
            return failure
        } catch {
            Issue.record("BudgetWriteError 를 기대했지만 \(error)")
        }
        return nil
    }

    /// `.other(APIError.server)` 에 담긴 코드. 다른 모양이면 nil.
    func serverCode(inOther failure: BudgetWriteError?) -> String? {
        guard case let .other(underlying) = failure, case let APIError.server(code, _) = underlying else {
            return nil
        }
        return code
    }

    /// 표 주도 단언용 케이스 이름. `.other` 는 담긴 오류를 따로 본다.
    func caseName(_ failure: BudgetWriteError) -> String {
        switch failure {
        case .invalidAmount: "invalidAmount"
        case .categoryNotFound: "categoryNotFound"
        case .monthOutOfRange: "monthOutOfRange"
        case .totalRequired: "totalRequired"
        case .allocationExceedsTotal: "allocationExceedsTotal"
        case .other: "other"
        }
    }

    func sampleRequest() throws -> SaveBudgetRequest {
        try SaveBudgetRequest(
            currency: .krw,
            totalAmount: decimal("500000"),
            paymentGroupAmounts: [],
            categoryAmounts: []
        )
    }
}

/// `SaveBudgetRequest` 로 보낸 본문을 금액을 `Decimal` 로 다시 읽는 테스트 전용 거울 타입.
private struct SentSaveBody: Decodable, Equatable {
    struct GroupAmount: Decodable, Equatable {
        let paymentGroup: String
        let amount: Decimal
    }

    struct CategoryAmount: Decodable, Equatable {
        let categoryId: Int
        let amount: Decimal
    }

    let currency: String
    let totalAmount: Decimal
    let paymentGroupAmounts: [GroupAmount]
    let categoryAmounts: [CategoryAmount]
}

// MARK: - Fixtures (백엔드 ApiResponse·ErrorResponse 봉투 + MonthlyBudgetResponse 모양, null 은 키 생략 없이 null)

private func successEnvelope(_ data: String) -> String {
    """
    {"success": true, "code": null, "data": \(data), "message": null,
     "timestamp": "2026-05-25T21:45:00.123456"}
    """
}

/// 백엔드 `ErrorCode` 의 HTTP 상태. 실패 봉투는 상태보다 먼저 해석되지만 응답 모양은 서버를 따른다.
private func httpStatus(of code: String) -> Int {
    ["CATEGORY_NOT_FOUND": 404, "CONCURRENT_MODIFICATION": 409, "REQUEST_BODY_TOO_LARGE": 413][code] ?? 400
}

private func failureEnvelope(_ code: String) -> String {
    """
    {"success": false, "code": "\(code)", "message": "서버 메시지",
     "timestamp": "2026-05-25T21:45:00.123456"}
    """
}

/// 이번 달(남은 7일), USD. 카드는 넘었고 계좌는 몫이 없으며, 카테고리 몫 합(750)이 전체보다 작아
/// "그 외 카테고리"가 남는 몫 250 을 넘었다. 하루 권장액 = 남은 돈 143.60 ÷ 7 을 자릿수에서 내림.
private let setMonthJSON = """
{
  "year": 2026, "month": 5, "currentYear": 2026, "currentMonth": 5,
  "remainingDaysIncludingToday": 7, "hasAnyBudget": true, "status": "NEAR_LIMIT", "currency": "USD",
  "total": {"budgetAmount": 1000.00, "actualAmount": 856.40, "status": "NEAR_LIMIT", "percent": 85,
            "remainingAmount": 143.60, "overAmount": null},
  "paymentGroups": [
    {"paymentGroup": "CREDIT_CARD", "budgetAmount": 600.00, "actualAmount": 700.15, "status": "EXCEEDED",
     "percent": null, "remainingAmount": null, "overAmount": 100.15},
    {"paymentGroup": "CASH_AND_DEBIT", "budgetAmount": 300.00, "actualAmount": 120.25, "status": "IN_PROGRESS",
     "percent": 40, "remainingAmount": 179.75, "overAmount": null},
    {"paymentGroup": "ACCOUNT_AND_OTHER", "budgetAmount": null, "actualAmount": 36.00, "status": null,
     "percent": null, "remainingAmount": null, "overAmount": null}
  ],
  "categories": [
    {"category": {"id": 3, "code": "FOOD", "displayNameKo": "식비", "displayNameEn": "Food", "icon": "fork.knife",
                  "sortOrder": 1},
     "deleted": false, "budgetAmount": 700.00, "actualAmount": 519.40, "status": "IN_PROGRESS", "percent": 74,
     "remainingAmount": 180.60, "overAmount": null},
    {"category": {"id": 101, "code": "CUSTOM_101", "displayNameKo": "취미", "displayNameEn": "Hobby", "icon": null,
                  "sortOrder": 50},
     "deleted": true, "budgetAmount": 50.00, "actualAmount": 0.00, "status": "NONE", "percent": 0,
     "remainingAmount": 50.00, "overAmount": null}
  ],
  "otherCategories": {"budgetAmount": 250.00, "actualAmount": 337.00, "status": "EXCEEDED", "percent": null,
                      "remainingAmount": null, "overAmount": 87.00},
  "missingRateCount": 1,
  "dailyAllowance": {"amount": 20.51, "exceeded": false},
  "deletedCategoriesWithSpending": [
    {"id": 205, "code": "CUSTOM_205", "displayNameKo": "여행", "displayNameEn": "Travel", "icon": "airplane",
     "sortOrder": 61},
    {"id": 188, "code": "CUSTOM_188", "displayNameKo": "선물", "displayNameEn": "Gift", "icon": null, "sortOrder": 64}
  ]
}
"""

/// 이번 달 예산을 지운 직후. 미설정이라 금액 자리는 null·배열은 비고, 남은 일수는 이번 달이라 온다.
private let deletedMonthJSON = """
{
  "year": 2026, "month": 5, "currentYear": 2026, "currentMonth": 5,
  "remainingDaysIncludingToday": 7, "hasAnyBudget": false, "status": "NOT_SET", "currency": null,
  "total": null, "paymentGroups": [], "categories": [], "otherCategories": null,
  "missingRateCount": 0, "dailyAllowance": null, "deletedCategoriesWithSpending": []
}
"""
