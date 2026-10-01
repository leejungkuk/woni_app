//
//  MonthReportPickerSaveColorTests.swift
//  woni_appTests
//
//  통계 달 제목 피커의 저장 버튼 색. 색은 XCUITest 로 관측할 수 없어 고르는 식을 유닛으로 지킨다.
//

import Testing
@testable import woni_app

struct MonthReportPickerSaveColorTests {
    @Test("저장 색은 보고 있는 탭을 따른다 — 수입 olive, 지출·합계 terracotta")
    func saveColorFollowsSelectedTab() {
        #expect(MonthReportView.pickerSaveColor(for: .income) == WoniColor.olive100)
        #expect(MonthReportView.pickerSaveColor(for: .expense) == WoniColor.terracotta100)
        #expect(MonthReportView.pickerSaveColor(for: .total) == WoniColor.terracotta100)
    }
}
