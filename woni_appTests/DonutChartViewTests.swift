//
//  DonutChartViewTests.swift
//  woni_appTests
//

import Testing
@testable import woni_app

@MainActor
struct DonutChartViewTests {
    @Test("도넛 주변 % 라벨은 표시 퍼센트 4% 이상인 조각에만 붙는다")
    func percentLabelStartsAtFourPercent() {
        #expect(!DonutChartView.showsPercentLabel(percent: 3))
        #expect(DonutChartView.showsPercentLabel(percent: 4))
    }
}
