//
//  BudgetService.swift
//  woni_app
//

import Foundation

/// 예산 쓰기(저장·삭제) 실패. 서버 코드를 화면이 다룰 갈래로 나눈다 — 문구는 화면 몫이다.
enum BudgetWriteError: Error {
    case invalidAmount, categoryNotFound, monthOutOfRange, totalRequired, allocationExceedsTotal
    /// 표에 없는 코드·HTTP 오류·전송 실패·해석 실패. 원래 오류를 그대로 담는다.
    case other(any Error)
}

/// 월 예산 읽기·저장·삭제 API. 백엔드 `/api/v1/budgets` 계약에 대응한다.
/// 예산은 서버가 주인인 값이라 캐시하지 않는다.
struct BudgetService {
    /// 오퍼레이션별로 앱이 분기하는 서버 코드 — 매핑의 유일한 출처다. 표 밖에서 코드를 분기하지 않는다.
    /// 키는 그 오퍼레이션의 계약 `x-error-codes` 안에 있어야 한다(에러 코드 계약 테스트가 이 키를 대조한다).
    static let saveErrorCodes: [String: BudgetWriteError] = [
        "BUDGET_INVALID_AMOUNT": .invalidAmount,
        "CATEGORY_NOT_FOUND": .categoryNotFound,
        "BUDGET_MONTH_OUT_OF_RANGE": .monthOutOfRange,
        "BUDGET_TOTAL_REQUIRED": .totalRequired,
        "BUDGET_ALLOCATION_EXCEEDS_TOTAL": .allocationExceedsTotal
    ]
    static let deleteErrorCodes: [String: BudgetWriteError] = [
        "BUDGET_MONTH_OUT_OF_RANGE": .monthOutOfRange
    ]

    private static let path = "/api/v1/budgets"
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    /// 실패는 `APIError` 그대로 던진다 — 화면은 어떤 실패든 "불러올 수 없음"이고, 미설정으로 바꾸지 않는다.
    func fetch(year: Int, month: Int) async throws -> MonthlyBudget {
        let dto: MonthlyBudgetDTO = try await client.get(Self.path, query: monthQuery(year: year, month: month))
        return dto.toDomain()
    }

    /// 실패는 `BudgetWriteError`.
    func save(year: Int, month: Int, request: SaveBudgetRequest) async throws -> MonthlyBudget {
        try await write(errorCodes: Self.saveErrorCodes) {
            try await client.put(Self.path, query: monthQuery(year: year, month: month), body: request)
        }
    }

    /// 그 달을 미설정으로 만든다. 실패는 `BudgetWriteError`.
    func delete(year: Int, month: Int) async throws -> MonthlyBudget {
        try await write(errorCodes: Self.deleteErrorCodes) {
            try await client.delete(Self.path, query: monthQuery(year: year, month: month))
        }
    }
}

private extension BudgetService {
    func monthQuery(year: Int, month: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "year", value: String(year)), URLQueryItem(name: "month", value: String(month))]
    }

    /// 서버 코드는 그 오퍼레이션의 표로만 바꾼다. 표에 없는 코드와 서버 코드가 아닌 실패는 원래 오류를 담은 `.other`.
    func write(
        errorCodes: [String: BudgetWriteError],
        _ operation: () async throws -> MonthlyBudgetDTO
    ) async throws -> MonthlyBudget {
        do {
            return try await operation().toDomain()
        } catch {
            if case let APIError.server(code, _) = error, let mapped = errorCodes[code] {
                throw mapped
            }
            throw BudgetWriteError.other(error)
        }
    }
}
