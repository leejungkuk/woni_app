//
//  RateQuote.swift
//  woni_app
//

import Foundation

/// 화면 표시용 환율 quote. 서버/시드의 `tts`를 그대로 운반하고 클라이언트에서 보정하지 않는다.
struct RateQuote: Equatable {
    enum Source: Equatable {
        case server
        case seed
    }

    let tts: Decimal
    let baseDate: Date?
    let isStale: Bool
    let source: Source
}

/// base 통화처럼 `exchangeCode == nil`인 통화는 외부 조회 없이 `tts = 1`, `baseDate = nil`,
/// `isStale = false`를 반환하며 `source`는 호출된 provider의 source를 따른다.
protocol RateProviding {
    func quote(for currency: SelectableCurrency, on date: Date) async -> RateQuote?
}

extension RateProviding {
    /// Step 4에서 ViewModel이 `quote`를 직접 쓰기 전까지 기존 임시 `rate` 호출을 유지한다.
    func rate(for currency: SelectableCurrency, on localDate: String) async -> Decimal? {
        guard let date = ServerDateFormatter.localDate.date(from: localDate) else {
            return nil
        }

        let quote = await quote(for: currency, on: date)
        return quote?.tts
    }
}
