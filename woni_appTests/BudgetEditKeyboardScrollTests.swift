//
//  BudgetEditKeyboardScrollTests.swift
//  woni_appTests
//

import SwiftUI
import Testing
@testable import woni_app

/// 입력 중 스크롤 맞춤 판단(UI_GUIDE "결제수단 칸에 입력 중이면 …" · "카테고리 칸에 입력 중이면(갈래 A) …").
/// UI 테스트 기기(iPhone 17)에서는 늘 들어가서 안 들어가는 갈래(작은 기기)는 여기서만 닿는다. 화면 동작은 `BudgetEditUITests` 가 본다.
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

// MARK: 맞춤 조건 — 스크롤 영역이 키보드만큼 줄어 있을 때만 맞춘다(리뷰 반영 2026-10-04 3회차)

extension BudgetEditKeyboardScrollTests {
    /// 위 끝 100 에서 `maxY` 까지인 스크롤 영역(window 좌표).
    private static func scroll(maxY: CGFloat) -> CGRect {
        CGRect(x: 0, y: 100, width: 402, height: maxY - 100)
    }

    @Test("BDF.S4-R7 스크롤 영역 아래 끝이 키보드 위 끝과 같으면 회피가 적용된 것이다")
    func avoidanceAppliedWhenScrollEndsAtKeyboardTop() {
        #expect(BudgetEditKeyboardScroll.isAvoidanceApplied(
            scrollFrame: Self.scroll(maxY: 566),
            keyboardFrame: Self.keyboard(minY: 566)
        ))
    }

    @Test("BDF.S4-R7 반올림 여유 1pt 안이면 회피가 적용된 것이다")
    func avoidanceAppliedWithinRoundingTolerance() {
        #expect(BudgetEditKeyboardScroll.isAvoidanceApplied(
            scrollFrame: Self.scroll(maxY: 566.5),
            keyboardFrame: Self.keyboard(minY: 566)
        ))
    }

    @Test("BDF.S4-R7 스크롤 영역 아래 끝이 키보드 위 끝보다 위면 회피가 적용된 것이다")
    func avoidanceAppliedWhenScrollEndsAboveKeyboard() {
        #expect(BudgetEditKeyboardScroll.isAvoidanceApplied(
            scrollFrame: Self.scroll(maxY: 451),
            keyboardFrame: Self.keyboard(minY: 566)
        ))
    }

    @Test("BDF.S4-R7 짝: 키보드를 끌어 내리는 중(스크롤 영역이 키보드 위 끝보다 아래)이면 맞추지 않는다")
    func avoidanceNotAppliedWhileDraggingKeyboardDown() {
        #expect(!BudgetEditKeyboardScroll.isAvoidanceApplied(
            scrollFrame: Self.scroll(maxY: 666),
            keyboardFrame: Self.keyboard(minY: 566)
        ))
    }

    @Test("BDF.S4-R7 짝: 스크롤 영역이 키보드만큼 줄기 전이면 맞추지 않는다")
    func avoidanceNotAppliedBeforeScrollShrinks() {
        #expect(!BudgetEditKeyboardScroll.isAvoidanceApplied(
            scrollFrame: Self.scroll(maxY: 874),
            keyboardFrame: Self.keyboard(minY: 566)
        ))
    }

    @Test("BDF.S4-R7 짝: 반올림 여유 1pt 를 넘으면 회피가 적용되지 않은 것이다")
    func avoidanceNotAppliedBeyondRoundingTolerance() {
        #expect(!BudgetEditKeyboardScroll.isAvoidanceApplied(
            scrollFrame: Self.scroll(maxY: 568),
            keyboardFrame: Self.keyboard(minY: 566)
        ))
    }
}

// MARK: 저장하는 키보드 프레임 — 화면 안의 끝 프레임만(리뷰 반영 2026-10-04 4회차)

extension BudgetEditKeyboardScrollTests {
    /// iPhone 17 세로 화면 bounds(= window 좌표).
    private static let screenBounds = CGRect(x: 0, y: 0, width: 402, height: 874)

    @Test("BDF.S4-R8 끝 프레임이 화면 안이면 그 프레임을 저장한다")
    func storesOnScreenEndFrame() {
        let endFrame = CGRect(x: 0, y: 566, width: 402, height: 308)
        #expect(BudgetEditKeyboardScroll.keyboardFrame(endFrame: endFrame, screenBounds: Self.screenBounds) == endFrame)
    }

    @Test("BDF.S4-R8 떠 있는 키보드가 낮아지면 낮아진 프레임을 저장한다")
    func storesLoweredEndFrame() {
        let endFrame = CGRect(x: 0, y: 620, width: 402, height: 254)
        #expect(BudgetEditKeyboardScroll.keyboardFrame(endFrame: endFrame, screenBounds: Self.screenBounds) == endFrame)
    }

    @Test("BDF.S4-R8 끝 프레임이 화면 아래 끝에서 시작하면 내려간 키보드다")
    func endFrameAtScreenBottomIsNil() {
        let endFrame = CGRect(x: 0, y: 874, width: 402, height: 308)
        #expect(BudgetEditKeyboardScroll.keyboardFrame(endFrame: endFrame, screenBounds: Self.screenBounds) == nil)
    }

    @Test("BDF.S4-R8 끝 프레임이 화면 밖이면 내려간 키보드다")
    func endFrameBelowScreenIsNil() {
        let endFrame = CGRect(x: 0, y: 900, width: 402, height: 308)
        #expect(BudgetEditKeyboardScroll.keyboardFrame(endFrame: endFrame, screenBounds: Self.screenBounds) == nil)
    }

    @Test("BDF.S4-R8 끝 프레임이 없으면 저장하지 않는다")
    func missingEndFrameIsNil() {
        #expect(BudgetEditKeyboardScroll.keyboardFrame(endFrame: nil, screenBounds: Self.screenBounds) == nil)
    }

    @Test("BDF.S4-R8 짝: 화면 아래 끝 바로 안(873)이면 그 프레임을 저장한다")
    func endFrameJustInsideScreenIsStored() {
        let endFrame = CGRect(x: 0, y: 873, width: 402, height: 308)
        #expect(BudgetEditKeyboardScroll.keyboardFrame(endFrame: endFrame, screenBounds: Self.screenBounds) == endFrame)
    }
}

// MARK: 맞출 대상 — 결제수단 칸 · 갈래 A 의 카테고리 칸(UI_GUIDE "카테고리 칸에 입력 중이면(갈래 A) …", 2026-10-05)

extension BudgetEditKeyboardScrollTests {
    @Test("BETR.S2-R1 갈래 A 의 카테고리 칸은 그 줄부터 그 외 카테고리 자리 끝까지 맞춘다")
    func directCategoryTargetsSlotEnd() {
        let targets = BudgetEditKeyboardScroll.targets(focus: .category(1), mode: .direct)
        #expect(targets?.field == .categoryRow(1))
        #expect(targets?.end == .categorySlotEnd)
    }

    @Test("BETR.S2-R1 다른 카테고리 칸이면 그 줄이 맞출 칸이다")
    func directCategoryTargetsFocusedRow() {
        let targets = BudgetEditKeyboardScroll.targets(focus: .category(7), mode: .direct)
        #expect(targets?.field == .categoryRow(7))
        #expect(targets?.end == .categorySlotEnd)
    }

    @Test("BETR.S2-R1 결제수단 칸은 그 줄부터 결제수단 섹션 끝까지 그대로 맞춘다", arguments: [
        BudgetEditTotalMode.direct,
        .categorySum
    ])
    func paymentTargetsPaymentSectionEnd(mode: BudgetEditTotalMode) {
        let targets = BudgetEditKeyboardScroll.targets(focus: .payment(.cashAndDebit), mode: mode)
        #expect(targets?.field == .paymentRow(.cashAndDebit))
        #expect(targets?.end == .paymentSectionEnd)
    }

    @Test("BETR.S2-R1 짝: 갈래 B·빈 화면의 카테고리 칸은 맞추지 않는다", arguments: [
        BudgetEditTotalMode.categorySum,
        .empty
    ])
    func nonDirectCategoryHasNoTargets(mode: BudgetEditTotalMode) {
        #expect(BudgetEditKeyboardScroll.targets(focus: .category(1), mode: mode) == nil)
    }

    @Test("BETR.S2-R1 짝: 전체 칸·입력 중인 칸 없음은 맞추지 않는다", arguments: [
        BudgetEditTotalMode.direct,
        .categorySum,
        .empty
    ])
    func totalOrNoFocusHasNoTargets(mode: BudgetEditTotalMode) {
        #expect(BudgetEditKeyboardScroll.targets(focus: .total, mode: mode) == nil)
        #expect(BudgetEditKeyboardScroll.targets(focus: nil, mode: mode) == nil)
    }
}
