//
//  ExchangeRate.swift
//  woni_app
//

import Foundation

/// 화면에서 사용하는 환율 도메인 모델. 서버 DTO(`ExchangeRateDTO`)와 분리한다.
struct ExchangeRate: Identifiable {
    let currency: CurrencyCode
    let currencyName: String
    let dealBasRate: Decimal
    /// 환율 기준일. 서버 문자열 파싱 실패 시 nil(서버 nullable 아님 — 방어적 Optional).
    let baseDate: Date?
    /// 요청일과 기준일이 다른 fallback 환율 여부.
    let isStale: Bool

    var id: String {
        currency.rawValue
    }
}
