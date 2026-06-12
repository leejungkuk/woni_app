//
//  APIEnvelopeTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 백엔드 공통 응답 봉투 `ApiResponse<T>` 디코딩 계약 검증.
/// 앱 타깃 기본 격리(MainActor)로 합성된 Decodable 준수와 격리를 맞추기 위해 @MainActor.
@MainActor
struct APIEnvelopeTests {

    @Test("성공 봉투는 success=true와 data를 디코딩한다")
    func decodesSuccessEnvelope() throws {
        let json = Data(
            """
            {
                "success": true,
                "data": [{
                    "currencyCode": "USD",
                    "currencyName": "미국 달러",
                    "dealBasRate": 1387.5,
                    "baseDate": "2026-06-12",
                    "stale": false
                }],
                "timestamp": "2026-06-12T09:00:00"
            }
            """.utf8)

        let envelope = try JSONDecoder().decode(APIEnvelope<[ExchangeRateDTO]>.self, from: json)

        #expect(envelope.success)
        #expect(envelope.data?.count == 1)
        #expect(envelope.data?.first?.currencyCode == .usd)
        #expect(envelope.code == nil)
        #expect(envelope.message == nil)
    }

    @Test("실패 봉투는 success=false와 code/message를 디코딩하고 data는 nil이다")
    func decodesErrorEnvelope() throws {
        let json = Data(
            """
            {
                "success": false,
                "code": "VALIDATION_ERROR",
                "message": "잘못된 통화 코드입니다.",
                "timestamp": "2026-06-12T09:00:00"
            }
            """.utf8)

        let envelope = try JSONDecoder().decode(APIEnvelope<[ExchangeRateDTO]>.self, from: json)

        #expect(!envelope.success)
        #expect(envelope.code == "VALIDATION_ERROR")
        #expect(envelope.message == "잘못된 통화 코드입니다.")
        #expect(envelope.data == nil)
    }

    @Test("Optional 필드가 모두 생략돼도 디코딩된다")
    func decodesEnvelopeWithoutOptionalFields() throws {
        let json = Data(#"{ "success": true }"#.utf8)

        let envelope = try JSONDecoder().decode(APIEnvelope<String>.self, from: json)

        #expect(envelope.success)
        #expect(envelope.data == nil)
        #expect(envelope.code == nil)
        #expect(envelope.message == nil)
        #expect(envelope.timestamp == nil)
    }
}
