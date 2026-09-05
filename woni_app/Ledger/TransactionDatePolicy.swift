//
//  TransactionDatePolicy.swift
//  woni_app
//

import Foundation

/// 서버 거래일 상한 미러 — `ExchangeRate.MAX_FUTURE_DAYS`(365)·`LedgerEntry.assertNotBeyondFutureLimit`.
/// "오늘"은 서버 `Clock`과 같은 Asia/Seoul이다. 기기 시간대는 결과에 관여하지 않는다(기기 간 동작 차이 0).
enum TransactionDatePolicy {
    private static let maxFutureDays = 365

    /// `transactionDate`(`yyyy-MM-dd`)가 오늘(KST)+365일을 넘으면 true. 형식이 고정이라 문자열 대소 비교가 곧 날짜 비교다.
    static func isBeyondFutureLimit(_ transactionDate: String, now: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ServerDateFormatter.localDate.timeZone
        guard let latestAllowedDate = calendar.date(byAdding: .day, value: maxFutureDays, to: now) else {
            preconditionFailure("Failed to calculate the transaction date limit.")
        }
        return transactionDate > ServerDateFormatter.localDate.string(from: latestAllowedDate)
    }
}
