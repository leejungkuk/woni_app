//
//  MonthCalendarGridTests.swift
//  woni_appTests
//
//  달력 날짜 그리드의 높이 산식. 월 전환 컨테이너가 이 값으로 `.frame(height:)`를 구동하므로
//  틀리면 슬라이드 중 그리드가 잘리거나 아래 내역 리스트가 어긋난 위치로 밀린다.
//

import Foundation
import Testing
@testable import woni_app

struct MonthCalendarGridTests {
    @Test("주 행 수만큼 셀 높이와 행 간격을 더한다")
    func dayGridHeightSumsRowsAndSpacing() {
        let cell = MonthCalendarGrid.dayCellHeight
        let spacing = MonthCalendarGrid.dayRowSpacing

        #expect(MonthCalendarGrid.dayGridHeight(dayCount: 28) == 4 * cell + 3 * spacing)
        #expect(MonthCalendarGrid.dayGridHeight(dayCount: 35) == 5 * cell + 4 * spacing)
        #expect(MonthCalendarGrid.dayGridHeight(dayCount: 42) == 6 * cell + 5 * spacing)
    }

    /// 첫 스냅샷 커밋 전에는 `calendarDays`가 비어 있다. 한 행도 못 채우는 값에서 행 간격을
    /// 빼면 음수 높이가 나오므로 7 미만은 0으로 끊는다.
    @Test("한 행을 못 채우는 개수는 높이가 0이다")
    func dayGridHeightIsZeroBelowOneRow() {
        #expect(MonthCalendarGrid.dayGridHeight(dayCount: 0) == 0)
        #expect(MonthCalendarGrid.dayGridHeight(dayCount: 6) == 0)
    }
}
