//
//  APIError.swift
//  woni_app
//

import Foundation

/// 네트워크/서버 오류. 서버 비즈니스 오류는 봉투의 `code` 로 분기한다(HTTP status 아님).
enum APIError: Error, LocalizedError {
    case invalidURL
    case transport(Error)
    case encoding(Error)
    case decoding(Error)
    case emptyResponse
    case httpStatus(code: Int, message: String)
    /// 봉투 `success=false`. `code` 로 세부 분기한다.
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 요청 주소입니다."
        case let .transport(error):
            return error.localizedDescription
        case .encoding:
            return "요청 데이터를 만들 수 없습니다."
        case .decoding:
            return "응답을 해석할 수 없습니다."
        case .emptyResponse:
            return "응답 데이터가 비어 있습니다."
        case let .httpStatus(code, message):
            return "HTTP \(code): \(message)"
        case let .server(_, message):
            return message
        }
    }
}
