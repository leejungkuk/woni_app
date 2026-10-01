import SwiftUI
import Testing
@testable import woni_app

struct WoniColorTokensTests {
    @Test("지출 카테고리 색은 terracotta 로 시작해 olive 로 끝나고 열 번째 뒤 다시 돈다")
    func expenseCategoryColorsStartWithTerracottaAndEndWithOlive() {
        #expect(WoniColor.categoryColor(rank: 0, type: .expense) == WoniColor.terracotta100)
        #expect(WoniColor.categoryColor(rank: 1, type: .expense) == WoniColor.category01)
        #expect(WoniColor.categoryColor(rank: 8, type: .expense) == WoniColor.category08)
        #expect(WoniColor.categoryColor(rank: 9, type: .expense) == WoniColor.olive100)
        #expect(WoniColor.categoryColor(rank: 10, type: .expense) == WoniColor.terracotta100)
    }

    @Test("수입 카테고리 색은 olive 로 시작해 terracotta 로 끝나고 열 번째 뒤 다시 돈다")
    func incomeCategoryColorsStartWithOliveAndEndWithTerracotta() {
        #expect(WoniColor.categoryColor(rank: 0, type: .income) == WoniColor.olive100)
        #expect(WoniColor.categoryColor(rank: 1, type: .income) == WoniColor.category01)
        #expect(WoniColor.categoryColor(rank: 8, type: .income) == WoniColor.category08)
        #expect(WoniColor.categoryColor(rank: 9, type: .income) == WoniColor.terracotta100)
        #expect(WoniColor.categoryColor(rank: 10, type: .income) == WoniColor.olive100)
    }

    @Test("카테고리 8색은 DS ai_Category 01~08 의 hex 와 같다")
    func categoryColorsMatchDesignSystemHex() {
        #expect(WoniColor.category01 == Color(hex: 0x3F8C84))
        #expect(WoniColor.category02 == Color(hex: 0xB8801F))
        #expect(WoniColor.category03 == Color(hex: 0x63769E))
        #expect(WoniColor.category04 == Color(hex: 0xBA5661))
        #expect(WoniColor.category05 == Color(hex: 0x296B88))
        #expect(WoniColor.category06 == Color(hex: 0x359B75))
        #expect(WoniColor.category07 == Color(hex: 0x7A4A2E))
        #expect(WoniColor.category08 == Color(hex: 0x9C963E))
    }
}
