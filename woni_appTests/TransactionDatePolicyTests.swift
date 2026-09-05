//
//  TransactionDatePolicyTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

struct TransactionDatePolicyTests {
    @Test("KST 자정 직전에는 당일 기준 365일까지 허용한다")
    func limitBeforeSeoulMidnight() throws {
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-09-05T14:59:59Z"))

        #expect(!TransactionDatePolicy.isBeyondFutureLimit("2027-09-05", now: now))
        #expect(TransactionDatePolicy.isBeyondFutureLimit("2027-09-06", now: now))
        #expect(!TransactionDatePolicy.isBeyondFutureLimit("2020-01-01", now: now))
    }

    @Test("KST 자정 직후에는 다음 날 기준 365일까지 허용한다")
    func limitAfterSeoulMidnight() throws {
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-09-05T15:00:00Z"))

        #expect(!TransactionDatePolicy.isBeyondFutureLimit("2027-09-06", now: now))
        #expect(TransactionDatePolicy.isBeyondFutureLimit("2027-09-07", now: now))
    }
}
