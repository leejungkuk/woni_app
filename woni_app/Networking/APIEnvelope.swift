//
//  APIEnvelope.swift
//  woni_app
//

import Foundation

/// 백엔드 공통 응답 봉투 `ApiResponse<T>` 에 1:1 대응하는 서버 DTO.
/// 성공: `success=true` + `data`. 실패: `success=false` + `code`/`message`.
/// (`code`/`message`/`data` 는 상황에 따라 생략되므로 모두 Optional)
struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let code: String?
    let data: T?
    let message: String?
    let timestamp: String?
}
