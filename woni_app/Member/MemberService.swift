//
//  MemberService.swift
//  woni_app
//

import Foundation

/// 탈퇴 요청 표면. 응답 `data`는 항상 null이라 반환값이 없고, 성공은 throw하지 않는 것으로만
/// 표현된다(Apple revoke 성패는 응답에 담기지 않는다).
protocol WithdrawalRequesting {
    func withdraw(appleAuthorizationCode: String?) async throws
}

/// 회원 탈퇴 API. 재시도·상태 전이는 호출부(코디네이션 계층)가 맡고 여기서는 한 번만 보낸다.
struct MemberService: WithdrawalRequesting {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    /// 코드가 없거나 공백뿐이면 본문 없이 보낸다. `null`이나 빈 JSON을 보내면 서버 결과는 같지만
    /// 검증할 조합만 늘어난다.
    func withdraw(appleAuthorizationCode: String?) async throws {
        let path = "/api/v1/members/me"
        let code = appleAuthorizationCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let code, !code.isEmpty else {
            try await client.delete(path)
            return
        }
        try await client.delete(path, body: MemberWithdrawalRequest(appleAuthorizationCode: code))
    }
}
