import SwiftUI
import Testing
@testable import woni_app

struct WoniColorTokensTests {
    @Test("차트 팔레트는 열 번째 색 뒤 첫 색부터 순환한다")
    func chartPaletteCyclesEveryTenRanks() {
        #expect(WoniColor.chartColor(forRank: 0) == WoniColor.chart01)
        #expect(WoniColor.chartColor(forRank: 9) == WoniColor.chart10)
        #expect(WoniColor.chartColor(forRank: 10) == WoniColor.chart01)
        #expect(WoniColor.chartColor(forRank: 13) == WoniColor.chart04)
    }
}
