import SwiftUI
import Testing
@testable import woni_app

struct WoniColorTokensTests {
    /// UI_GUIDE "카테고리 색"의 2~9위 순서: 청록 · 황토 · 청회색 · 로즈 · 데님 · 비취 · 브라운 · 머스터드.
    private let middle = [
        WoniColor.category01, WoniColor.category02, WoniColor.category03, WoniColor.category04,
        WoniColor.category05, WoniColor.category06, WoniColor.category07, WoniColor.category08
    ]

    @Test("지출 카테고리 색은 terracotta 로 시작해 olive 로 끝나고 열 번째 뒤 다시 돈다")
    func expenseCategoryColorsStartWithTerracottaAndEndWithOlive() {
        let colors = (0 ... 10).map { WoniColor.categoryColor(rank: $0, type: .expense) }

        #expect(colors == [WoniColor.terracotta100] + middle + [WoniColor.olive100, WoniColor.terracotta100])
    }

    @Test("수입 카테고리 색은 olive 로 시작해 terracotta 로 끝나고 열 번째 뒤 다시 돈다")
    func incomeCategoryColorsStartWithOliveAndEndWithTerracotta() {
        let colors = (0 ... 10).map { WoniColor.categoryColor(rank: $0, type: .income) }

        #expect(colors == [WoniColor.olive100] + middle + [WoniColor.terracotta100, WoniColor.olive100])
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
