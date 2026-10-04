//
//  BudgetEditKeyboardScrollTests.swift
//  woni_appTests
//

import SwiftUI
import Testing
@testable import woni_app

/// 결제수단 칸 입력 중 스크롤 맞춤 판단(UI_GUIDE "결제수단 칸에 입력 중이면 …"). UI 테스트 기기(iPhone 17)에서는 늘 들어가서
/// 안 들어가는 갈래(작은 기기)는 여기서만 닿는다. 화면 동작은 `BudgetEditUITests` 가 본다.
@MainActor
struct BudgetEditKeyboardScrollTests {
    @Test("BDF.S4-R1 칸 꼭대기~섹션 끝이 보이는 높이에 들어가면 섹션 끝을 맞춘다")
    func fitsAlignsSectionBottom() {
        let alignment = BudgetEditKeyboardScroll.alignment(fieldTop: 400, sectionBottom: 600, visibleHeight: 430)
        #expect(alignment == .sectionBottom)
    }

    @Test("BDF.S4-R1 짝: 칸 꼭대기~섹션 끝이 보이는 높이를 넘으면 입력 중인 칸 꼭대기를 맞춘다")
    func overflowAlignsFieldTop() {
        let alignment = BudgetEditKeyboardScroll.alignment(fieldTop: 400, sectionBottom: 900, visibleHeight: 280)
        #expect(alignment == .fieldTop)
    }

    @Test("BDF.S4-R1 길이가 보이는 높이와 같으면 들어간 것이다")
    func equalLengthAlignsSectionBottom() {
        let alignment = BudgetEditKeyboardScroll.alignment(fieldTop: 520, sectionBottom: 770, visibleHeight: 250)
        #expect(alignment == .sectionBottom)
    }

    @Test("BDF.S4-R1 짝: 길이가 보이는 높이보다 1 크면 넘친 것이다")
    func oneOverAlignsFieldTop() {
        let alignment = BudgetEditKeyboardScroll.alignment(fieldTop: 520, sectionBottom: 771, visibleHeight: 250)
        #expect(alignment == .fieldTop)
    }

    @Test("BDF.S4-R1 판단은 차로 한다 — 칸 꼭대기가 보이는 높이보다 커도 길이가 들어가면 섹션 끝을 맞춘다")
    func largeFieldTopStillFits() {
        let alignment = BudgetEditKeyboardScroll.alignment(fieldTop: 900, sectionBottom: 1080, visibleHeight: 300)
        #expect(alignment == .sectionBottom)
    }

    @Test("BDF.S4-R1 짝: 칸 꼭대기가 0 이어도 길이가 넘으면 칸 꼭대기를 맞춘다")
    func zeroFieldTopStillOverflows() {
        let alignment = BudgetEditKeyboardScroll.alignment(fieldTop: 0, sectionBottom: 360, visibleHeight: 340)
        #expect(alignment == .fieldTop)
    }

    @Test("BDF.S4-R1 섹션 끝을 맞출 때는 섹션 끝 id 를 아래 기준으로 준다")
    func sectionBottomTargetsSectionEnd() {
        let target = BudgetEditKeyboardScroll.target(for: .sectionBottom, field: "field", sectionEnd: "sectionEnd")
        #expect(target.id == "sectionEnd")
        #expect(target.anchor == .bottom)
    }

    @Test("BDF.S4-R1 짝: 칸 꼭대기를 맞출 때는 칸 id 를 위 기준으로 준다")
    func fieldTopTargetsField() {
        let target = BudgetEditKeyboardScroll.target(for: .fieldTop, field: "field", sectionEnd: "sectionEnd")
        #expect(target.id == "field")
        #expect(target.anchor == .top)
    }
}

// MARK: 보이는 높이 — 키보드 최종 프레임으로 센다(리뷰 반영 2026-10-04)

extension BudgetEditKeyboardScrollTests {
    /// iPhone 17 세로 폭. 키보드 프레임은 화면(= window) 좌표다.
    private static func keyboard(minY: CGFloat) -> CGRect {
        CGRect(x: 0, y: minY, width: 402, height: 308)
    }

    @Test("BDF.S4-R5 스크롤 영역이 키보드만큼 줄기 전이면 키보드 위 끝까지가 보이는 높이다")
    func visibleHeightBeforeScrollShrinks() {
        let height = BudgetEditKeyboardScroll.visibleHeight(
            scrollFrame: CGRect(x: 0, y: 100, width: 402, height: 700),
            keyboardFrame: Self.keyboard(minY: 566)
        )
        #expect(height == 466)
    }

    @Test("BDF.S4-R5 스크롤 영역이 키보드만큼 줄은 뒤에도 같은 높이다")
    func visibleHeightAfterScrollShrinks() {
        let height = BudgetEditKeyboardScroll.visibleHeight(
            scrollFrame: CGRect(x: 0, y: 100, width: 402, height: 466),
            keyboardFrame: Self.keyboard(minY: 566)
        )
        #expect(height == 466)
    }

    @Test("BDF.S4-R5 키보드가 스크롤 영역 아래에 있으면 스크롤 영역 높이 그대로다")
    func keyboardBelowScrollKeepsScrollHeight() {
        let height = BudgetEditKeyboardScroll.visibleHeight(
            scrollFrame: CGRect(x: 0, y: 100, width: 402, height: 700),
            keyboardFrame: Self.keyboard(minY: 900)
        )
        #expect(height == 700)
    }

    @Test("BDF.S4-R5 키보드 위 끝이 스크롤 영역보다 위면 0 이다 — 음수가 아니다")
    func keyboardAboveScrollIsZero() {
        let height = BudgetEditKeyboardScroll.visibleHeight(
            scrollFrame: CGRect(x: 0, y: 100, width: 402, height: 700),
            keyboardFrame: Self.keyboard(minY: 50)
        )
        #expect(height == 0)
    }

    @Test("BDF.S4-R5 짝: 키보드 위 끝이 바뀌면 보이는 높이도 바뀐다")
    func keyboardTopChangesVisibleHeight() {
        let height = BudgetEditKeyboardScroll.visibleHeight(
            scrollFrame: CGRect(x: 0, y: 100, width: 402, height: 700),
            keyboardFrame: Self.keyboard(minY: 600)
        )
        #expect(height == 500)
    }
}
