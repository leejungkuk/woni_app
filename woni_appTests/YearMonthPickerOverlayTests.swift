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

    @Test("달 범위를 주지 않으면 모든 해에서 1~12월이다 — 가계부·입력·통계 피커는 지금 그대로")
    @MainActor
    func defaultMonthRangeIsWholeYear() {
        let picker = YearMonthPickerOverlay(
            initialYear: 2026,
            initialMonth: 5,
            years: 2000 ... 2040,
            saveColor: WoniColor.terracotta100,
            onSave: { _, _ in },
            onCancel: {}
        )

        for year in [2000, 2026, 2027, 2040] {
            #expect(picker.months(year) == 1 ... 12)
            #expect(picker.monthItems(inYear: year) == Array(1 ... 12))
        }
    }

    @Test("해를 바꿔 고른 달이 새 범위 밖이면 범위 안의 가장 가까운 달로 옮긴다")
    func clampsMonthIntoNewYearRange() {
        #expect(YearMonthPickerOverlay.clampedMonth(12, in: 1 ... 10) == 10)
        #expect(YearMonthPickerOverlay.clampedMonth(1, in: 3 ... 12) == 3)
        #expect(YearMonthPickerOverlay.clampedMonth(7, in: 1 ... 10) == 7)
        #expect(YearMonthPickerOverlay.clampedMonth(10, in: 1 ... 10) == 10)
    }

    @Test("휠의 달 목록은 고른 해의 범위만 보인다 — 예산 끝 해에서 범위 밖 달은 휠에 없다")
    @MainActor
    func monthItemsFollowSelectedYear() {
        let picker = YearMonthPickerOverlay(
            initialYear: 2026,
            initialMonth: 12,
            years: 2000 ... 2027,
            saveColor: WoniColor.terracotta100,
            months: { $0 == 2027 ? 1 ... 10 : 1 ... 12 },
            onSave: { _, _ in },
            onCancel: {}
        )

        #expect(picker.monthItems(inYear: 2027) == Array(1 ... 10))
        #expect(picker.monthItems(inYear: 2026) == Array(1 ... 12))
    }
}
