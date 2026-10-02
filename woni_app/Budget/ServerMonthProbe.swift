//
//  ServerMonthProbe.swift
//  woni_app
//

import Foundation

/// 서버(서울) 시각의 해·달.
struct ServerMonth: Equatable {
    let year: Int
    let month: Int
}

enum ServerMonthProbeError: Error, Equatable {
    case missingTimestamp
    /// 앞 7자리가 `yyyy-MM` 으로 읽히지 않는다. 받은 값을 그대로 담는다.
    case unreadableTimestamp(String)
}

/// 신원이 없는 비회원이 편집할 달을 서버 시각으로 정한다(스펙 §3 C1). 기기 시계·달력·로케일을 읽지 않는다 —
/// 읽으면 시계가 틀리거나 해외 시간대인 기기만 다른 달에 조용히 저장된다. 실패하면 던지고 다른 달로 대신하지 않는다.
struct ServerMonthProbe {
    /// 인증 없이 부를 수 있는 작은 공개 조회. `data` 는 보지 않는다.
    private static let path = "/api/v1/assets"
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    /// 서버(서울) 시각의 이번 달. `GET /api/v1/assets` 봉투 timestamp 의 앞 7자리.
    /// 전송·서버 실패는 `APIClient` 가 던진 오류 그대로다.
    func currentMonth() async throws -> ServerMonth {
        guard let timestamp = try await client.serverTimestamp(Self.path) else {
            throw ServerMonthProbeError.missingTimestamp
        }
        guard let month = Self.month(from: timestamp) else {
            throw ServerMonthProbeError.unreadableTimestamp(timestamp)
        }
        return month
    }
}

private extension ServerMonthProbe {
    /// 서버는 서울 시각을 시간대 없는 `2026-09-30T21:45:00.123456` 로 보낸다(백엔드 `ApiResponse`).
    /// 날짜 파서는 기기 달력(일본력·불기)과 로케일을 타므로 앞 7자리를 글자 단위로 직접 읽는다.
    static func month(from timestamp: String) -> ServerMonth? {
        let head = Array(timestamp.prefix(7))
        guard head.count == 7, head[4] == "-",
              let year = asciiNumber(head[0 ..< 4]),
              let month = asciiNumber(head[5 ..< 7]),
              (1 ... 12).contains(month)
        else {
            return nil
        }
        return ServerMonth(year: year, month: month)
    }

    /// ASCII 숫자 `0`~`9` 만 읽는다. 전각·아라비아-인도 숫자처럼 다른 숫자 글자가 하나라도 있으면 nil.
    static func asciiNumber(_ characters: ArraySlice<Character>) -> Int? {
        var value = 0
        for character in characters {
            guard let ascii = character.asciiValue,
                  (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(ascii)
            else {
                return nil
            }
            value = value * 10 + Int(ascii - UInt8(ascii: "0"))
        }
        return value
    }
}
