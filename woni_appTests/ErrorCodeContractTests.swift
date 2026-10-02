//
//  ErrorCodeContractTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 앱이 분기하는 서버 에러 코드가 그 오퍼레이션의 계약 `x-error-codes` 안에 있는지 지킨다.
/// 빨개지면 앱이 서버가 낼 수 없는 코드를 분기하고 있다는 뜻이다.
///
/// - 사본 `Contract/openapi.json` 은 백엔드 리포 `api-contract/openapi.json`(main `4893bef`)을 바이트 그대로 복사한 것이다.
/// - 갱신: 백엔드 인계가 새 선언을 알리면 백엔드 main 의 같은 파일로 덮어쓰고 아래 `operations` 표를 점검한다.
/// - 대상은 `x-error-codes` 키가 있는 오퍼레이션뿐이다. 키가 없으면 "미선언"이지 "코드 없음"이 아니다.
///   미선언 오퍼레이션에서 앱이 분기하는 곳 — `CustomCategoryStore`·`CategoryAddViewModel`·`SyncEngine`·
///   `DataPurgeCoordinator`(카테고리·거래 동기화·회원 삭제) — 은 백엔드가 선언하면 상수로 옮기고 표에 더한다.
///
/// 계약은 번들 리소스가 아니라 `#filePath` 로 소스 트리에서 읽는다(`LegalTextParityTests` 와 같다).
@MainActor
struct ErrorCodeContractTests {
    @Test("표의 오퍼레이션은 모두 계약에 있고 x-error-codes 를 선언한다")
    func listedOperationsDeclareErrorCodes() throws {
        let contract = try Self.loadContract()

        for operation in Self.operations {
            #expect(
                Self.declaredCodes(method: operation.method, path: operation.path, in: contract) != nil,
                "\(operation.label) 가 계약에 없거나 x-error-codes 를 선언하지 않았다"
            )
        }
    }

    @Test("앱이 분기하는 코드는 그 오퍼레이션의 x-error-codes 안에 있다")
    func branchedCodesAreDeclaredForTheirOperation() throws {
        let contract = try Self.loadContract()

        for operation in Self.operations {
            // 지역 변수로 먼저 받는다 — `#require` 안에 `contract` 를 두면 실패 때 계약 전체가 로그에 펼쳐진다.
            let undeclared = Self.undeclaredCodes(
                operation.branchedCodes,
                method: operation.method,
                path: operation.path,
                in: contract
            )
            let missing = try #require(undeclared, "\(operation.label) 가 계약에 없거나 x-error-codes 를 선언하지 않았다")
            #expect(missing.isEmpty, "\(operation.label) 에 선언되지 않은 코드: \(missing.sorted())")
        }
    }

    @Test("계약에 없는 코드와 다른 오퍼레이션에만 선언된 코드는 빠진 코드로 돌려준다")
    func reportsCodesMissingFromTheContract() throws {
        let contract = try Self.loadContract()
        let categoryNotFound = try #require(
            BudgetService.saveErrorCodes.first { entry in
                if case .categoryNotFound = entry.value {
                    return true
                }
                return false
            }?.key
        )

        let fake = Self.undeclaredCodes(["NOT_IN_CONTRACT"], method: "PUT", path: "/api/v1/budgets", in: contract)
        let onPut = Self.undeclaredCodes([categoryNotFound], method: "PUT", path: "/api/v1/budgets", in: contract)
        let onDelete = Self.undeclaredCodes([categoryNotFound], method: "DELETE", path: "/api/v1/budgets", in: contract)

        #expect(fake == ["NOT_IN_CONTRACT"])
        #expect(onPut?.isEmpty == true)
        #expect(onDelete == [categoryNotFound])
    }
}

private extension ErrorCodeContractTests {
    struct ContractOperation {
        let method: String
        let path: String
        let branchedCodes: Set<String>

        var label: String {
            "\(method) \(path)"
        }
    }

    /// 앱이 부르고 계약이 `x-error-codes` 를 선언한 오퍼레이션 → 앱이 그 응답에서 분기하는 코드(앱 상수).
    /// 모든 요청이 401 재시도에서 `APIClient.unauthorizedCode` 로 분기한다.
    /// `GET /api/v1/exchange-rates/status` 는 선언됐지만 앱이 부르지 않아 빠진다.
    static var operations: [ContractOperation] {
        let unauthorized: Set = [APIClient.unauthorizedCode]
        return [
            ContractOperation(method: "GET", path: "/api/v1/budgets", branchedCodes: unauthorized),
            ContractOperation(
                method: "PUT",
                path: "/api/v1/budgets",
                branchedCodes: unauthorized.union(BudgetService.saveErrorCodes.keys)
            ),
            ContractOperation(
                method: "DELETE",
                path: "/api/v1/budgets",
                branchedCodes: unauthorized.union(BudgetService.deleteErrorCodes.keys)
            ),
            ContractOperation(method: "GET", path: "/api/v1/exchange-rates", branchedCodes: unauthorized),
            ContractOperation(method: "GET", path: "/api/v1/exchange-rates/snapshot", branchedCodes: unauthorized),
            ContractOperation(method: "GET", path: "/api/v1/exchange-rates/range", branchedCodes: unauthorized),
            ContractOperation(
                method: "GET",
                path: "/api/v1/exchange-rates/{currencyCode}",
                branchedCodes: unauthorized.union([ServerRateProvider.rejectedDateCode])
            )
        ]
    }

    static func loadContract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // woni_appTests
            .appendingPathComponent("Contract/openapi.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require(object as? [String: Any])
    }

    /// 그 오퍼레이션의 `x-error-codes`. 오퍼레이션이 없거나 키가 없으면 nil — 미선언을 빈 집합으로 읽지 않는다.
    static func declaredCodes(method: String, path: String, in contract: [String: Any]) -> Set<String>? {
        let paths = contract["paths"] as? [String: Any]
        let pathItem = paths?[path] as? [String: Any]
        let operation = pathItem?[method.lowercased()] as? [String: Any]
        return (operation?["x-error-codes"] as? [String]).map(Set.init)
    }

    /// `codes` 중 그 오퍼레이션이 선언하지 않은 코드. 미선언 오퍼레이션이면 nil.
    static func undeclaredCodes(
        _ codes: Set<String>,
        method: String,
        path: String,
        in contract: [String: Any]
    ) -> Set<String>? {
        declaredCodes(method: method, path: path, in: contract).map { codes.subtracting($0) }
    }
}
