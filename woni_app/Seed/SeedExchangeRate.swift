//
//  SeedExchangeRate.swift
//  woni_app
//

import Foundation

/// 번들 시드 환율 도메인 모델. 서버 `ExchangeRateResponse`의 `tts` 계약만 사용한다.
struct SeedExchangeRate: Equatable {
    let currencyCode: CurrencyCode
    let currencyName: String
    let tts: Decimal
    let baseDate: String
    let stale: Bool
}

/// 시드 전용 DTO. 기존 온라인 `ExchangeRateDTO`는 dormant 경로라 건드리지 않는다.
struct SeedExchangeRateDTO: Decodable {
    let currencyCode: CurrencyCode
    let currencyName: String
    let tts: Decimal
    let baseDate: String
    let stale: Bool
}

extension SeedExchangeRateDTO {
    func toDomain() -> SeedExchangeRate {
        SeedExchangeRate(
            currencyCode: currencyCode,
            currencyName: currencyName,
            tts: tts,
            baseDate: baseDate,
            stale: stale
        )
    }
}
