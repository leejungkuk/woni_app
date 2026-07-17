//
//  ExchangeRateDTOTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 서버 DTO → 도메인 모델 매핑(`toDomain()`) 검증. 금액은 `Decimal` 리터럴만 사용.
/// 앱 타깃 기본 격리(MainActor)로 합성된 Decodable 준수와 격리를 맞추기 위해 @MainActor.
@MainActor
struct ExchangeRateDTOTests {
    /// 기대 날짜를 구현(ServerDateFormatter)과 무관하게 독립 구성 — 동어반복 단언 방지.
    private func seoulDate(year: Int, month: Int, day: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    @Test("toDomain은 모든 필드를 도메인 모델로 전달한다")
    func mapsAllFieldsToDomain() throws {
        let rate = try #require(Decimal(string: "1387.50"))
        let dto = ExchangeRateDTO(
            currencyCode: .usd,
            currencyName: "미국 달러",
            tts: rate,
            baseDate: "2026-06-12",
            stale: false
        )

        let domain = dto.toDomain()

        #expect(domain.currency == .usd)
        #expect(domain.currencyName == "미국 달러")
        #expect(domain.tts == rate)
        #expect(try domain.baseDate == seoulDate(year: 2026, month: 6, day: 12))
        #expect(domain.isStale == false)
    }

    @Test("baseDate 형식이 yyyy-MM-dd가 아니면 도메인 baseDate는 nil이 된다")
    func mapsInvalidBaseDateToNil() throws {
        let dto = try ExchangeRateDTO(
            currencyCode: .jpy,
            currencyName: "일본 엔",
            tts: #require(Decimal(string: "9.42")),
            baseDate: "12-06-2026",
            stale: true
        )

        let domain = dto.toDomain()

        #expect(domain.baseDate == nil)
        #expect(domain.isStale)
    }

    @Test("서버 응답 JSON 디코딩부터 toDomain까지 한 흐름으로 동작한다")
    func decodesServerJSONAndMapsToDomain() throws {
        let json = Data(
            """
            {
                "currencyCode": "EUR",
                "currencyName": "유로",
                "tts": 1512.34,
                "baseDate": "2026-06-11",
                "stale": true
            }
            """.utf8
        )

        let dto = try JSONDecoder().decode(ExchangeRateDTO.self, from: json)
        let domain = dto.toDomain()

        #expect(domain.currency == .eur)
        #expect(domain.tts == Decimal(string: "1512.34"))
        #expect(try domain.baseDate == seoulDate(year: 2026, month: 6, day: 11))
        #expect(domain.isStale)
    }
}
