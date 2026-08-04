//
//  MemberDTO.swift
//  woni_app
//

import Foundation

/// 백엔드 `MemberWithdrawalRequest`에 1:1 대응하는 탈퇴 요청 DTO.
/// 서버 스키마상 필드는 선택이지만 nullable이 아니다 — 코드가 없으면 `null`을 담아 보내는 게
/// 아니라 본문 자체를 생략한다(`MemberService.withdraw`).
struct MemberWithdrawalRequest: Encodable {
    let appleAuthorizationCode: String
}
