//
//  CurrencyCodeTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 백엔드 `CurrencyCode` enum 직렬화 계약(KRW/USD/EUR/JPY/CNY/GBP) 검증.
/// 앱 타깃 기본 격리(MainActor)로 합성된 Decodable 준수와 격리를 맞추기 위해 @MainActor.
@MainActor
struct CurrencyCodeTests {
    @Test("지원 통화 코드는 JSON 라운드트립이 성립한다", arguments: CurrencyCode.allCases)
    func decodesEverySupportedCode(code: CurrencyCode) throws {
        let json = Data("\"\(code.rawValue)\"".utf8)

        let decoded = try JSONDecoder().decode(CurrencyCode.self, from: json)

        #expect(decoded == code)
    }

    @Test("미지원 통화 코드는 디코딩에 실패한다")
    func failsToDecodeUnsupportedCode() {
        let json = Data("\"AUD\"".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CurrencyCode.self, from: json)
        }
    }
}
