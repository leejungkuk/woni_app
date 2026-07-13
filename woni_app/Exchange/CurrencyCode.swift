//
//  CurrencyCode.swift
//  woni_app
//

import Foundation

/// 백엔드 `CurrencyCode` enum 에 대응. 직렬화 값은 enum name(KRW/USD/EUR/JPY/CNY/GBP).
enum CurrencyCode: String, Codable, CaseIterable {
    case krw = "KRW"
    case usd = "USD"
    case eur = "EUR"
    case jpy = "JPY"
    case cny = "CNY"
    case gbp = "GBP"
}
