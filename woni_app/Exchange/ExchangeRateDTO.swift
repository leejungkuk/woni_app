//
//  ExchangeRateDTO.swift
//  woni_app
//

import Foundation

/// 백엔드 `ExchangeRateResponse`(record)에 1:1 대응하는 서버 DTO.
/// 금액은 부동소수점 금지 → `Decimal`. 날짜는 서버 문자열("yyyy-MM-dd")을 그대로 받고 도메인에서 변환.
struct ExchangeRateDTO: Decodable {
    let currencyCode: CurrencyCode
    let currencyName: String
    let tts: Decimal
    let baseDate: String
    let stale: Bool
}

extension ExchangeRateDTO {
    /// 서버 DTO → 도메인 모델 매핑(DTO가 뷰에 직접 침투하지 않게 분리).
    func toDomain() -> ExchangeRate {
        ExchangeRate(
            currency: currencyCode,
            currencyName: currencyName,
            tts: tts,
            baseDate: ServerDateFormatter.localDate.date(from: baseDate),
            isStale: stale
        )
    }
}
