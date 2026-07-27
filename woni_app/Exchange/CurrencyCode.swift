//
//  CurrencyCode.swift
//  woni_app
//

import Foundation

/// 백엔드 `CurrencyCode` enum에 대응하며 직렬화 값은 enum name이다.
/// `IDR(100)`은 EximBank 전용 apiCode이고 wire 값은 JPY 선례와 같은 `IDR`이다.
enum CurrencyCode: String, Codable, CaseIterable {
    case krw = "KRW"
    case usd = "USD"
    case eur = "EUR"
    case jpy = "JPY"
    case cny = "CNY"
    case gbp = "GBP"
    case thb = "THB"
    case hkd = "HKD"
    case sgd = "SGD"
    case idr = "IDR"
    case myr = "MYR"
    case aud = "AUD"
    case nzd = "NZD"
}
