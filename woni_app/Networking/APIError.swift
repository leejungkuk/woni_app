//
//  APIError.swift
//  woni_app
//

import Foundation

/// 네트워크/서버 오류. 서버 비즈니스 오류는 봉투의 `code` 로 분기한다(HTTP status 아님).
enum APIError: Error, LocalizedError {
    case invalidURL
    case transport(Error)
    case decoding(Error)
    case emptyResponse
    /// 봉투 `success=false`. `code` 로 세부 분기한다.
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 요청 주소입니다."
        case let .transport(error):
            return error.localizedDescription
        case .decoding:
            return "응답을 해석할 수 없습니다."
        case .emptyResponse:
            return "응답 데이터가 비어 있습니다."
        case let .server(_, message):
            return message
        }
    }
}
