//
//  YearMonthPickerOverlayTests.swift
//  woni_appTests
//
//  연/월 피커의 기본 해 범위. 앱의 "오늘"과 같은 서울 gregorian 으로 세야 한다 —
//  기기 달력·시간대로 세면 일본력·불기 기기나 연말 몇 시간 동안 기기마다 휠 범위가 달라진다.
//

import Foundation
import Testing
@testable import woni_app

struct YearMonthPickerOverlayTests {
    @Test("기본 해 범위는 서울 기준 올해 ±10 이다 — UTC 로는 아직 지난해인 시각")
    func defaultYearsCenterOnSeoulYear() throws {
        // 2020-12-31T15:30:00Z = 서울 2021-01-01 00:30. 올해가 아닌 해라야 `now` 를 무시하는 구현이 걸린다.
        let now = try #require(ISO8601DateFormatter().date(from: "2020-12-31T15:30:00Z"))

        #expect(YearMonthPickerOverlay.defaultYears(including: 2021, now: now) == 2011 ... 2031)
    }

    @Test("처음 해가 올해 ±10 밖이면 그 해까지 넓힌다")
    func defaultYearsExtendToIncludeInitialYear() throws {
        // 2019-05-31T15:00:00Z = 서울 2019-06-01 00:00
        let now = try #require(ISO8601DateFormatter().date(from: "2019-05-31T15:00:00Z"))

        #expect(YearMonthPickerOverlay.defaultYears(including: 2040, now: now) == 2009 ... 2040)
        #expect(YearMonthPickerOverlay.defaultYears(including: 1999, now: now) == 1999 ... 2029)
    }
}
