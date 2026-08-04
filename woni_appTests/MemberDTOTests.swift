//
//  MemberDTOTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 탈퇴 요청 DTO가 서버 계약(`MemberWithdrawalRequest`) 필드명 그대로 인코딩되는지 검증한다.
@MainActor
struct MemberDTOTests {
    @Test("탈퇴 요청은 계약 필드 하나만 인코딩한다")
    func withdrawalRequestEncodesContractFieldOnly() throws {
        let data = try JSONEncoder().encode(
            MemberWithdrawalRequest(appleAuthorizationCode: "apple-code")
        )

        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(json == ["appleAuthorizationCode": "apple-code"])
    }
}
