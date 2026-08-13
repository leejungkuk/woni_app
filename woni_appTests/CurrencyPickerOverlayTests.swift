//
//  CurrencyPickerOverlayTests.swift
//  woni_appTests
//
//  통화 선택 시트의 드래그 기하 산식. 리스트 높이와 아래로 밀려난 거리를 한 산식이 함께 내므로
//  틀리면 손가락을 따라 내려가지 않거나, 기기마다 다른 거리에서 시트가 닫힌다.
//

import Foundation
import Testing
@testable import woni_app

struct CurrencyPickerOverlayTests {
    private let expandedListHeight: CGFloat = 800

    @Test("축소 상태에서 아래로 끌면 높이는 그대로 두고 끈 만큼 시트를 내린다")
    func compactDragDownPushesSheetDown() {
        let geometry = CurrencyPickerOverlay.sheetGeometry(
            isExpanded: false,
            expandedListHeight: expandedListHeight,
            dragTranslation: 120
        )

        #expect(geometry.listHeight == CurrencyPickerOverlay.compactListHeight)
        #expect(geometry.offset == 120)
    }

    @Test("축소 상태에서 위로 끌면 높이만 늘고 확장 높이에서 멈춘다")
    func compactDragUpGrowsHeightUpToExpanded() {
        let partial = CurrencyPickerOverlay.sheetGeometry(
            isExpanded: false,
            expandedListHeight: expandedListHeight,
            dragTranslation: -150
        )
        #expect(partial.listHeight == CurrencyPickerOverlay.compactListHeight + 150)
        #expect(partial.offset == 0)

        let beyond = CurrencyPickerOverlay.sheetGeometry(
            isExpanded: false,
            expandedListHeight: expandedListHeight,
            dragTranslation: -300
        )
        #expect(beyond.listHeight == expandedListHeight)
        #expect(beyond.offset == 0)
    }

    /// 확장 상태의 아래 드래그는 먼저 축소 하한까지 높이를 줄이고, 그 뒤부터 시트를 내린다.
    /// 두 구간이 한 제스처 안에서 이어져야 손가락을 놓치지 않는다.
    @Test("확장 상태에서 아래로 끌면 축소 하한까지 줄어든 뒤부터 시트가 내려간다")
    func expandedDragDownShrinksBeforePushing() {
        let shrinking = CurrencyPickerOverlay.sheetGeometry(
            isExpanded: true,
            expandedListHeight: expandedListHeight,
            dragTranslation: 150
        )
        #expect(shrinking.listHeight == expandedListHeight - 150)
        #expect(shrinking.offset == 0)

        let pushing = CurrencyPickerOverlay.sheetGeometry(
            isExpanded: true,
            expandedListHeight: expandedListHeight,
            dragTranslation: expandedListHeight - CurrencyPickerOverlay.compactListHeight + 70
        )
        #expect(pushing.listHeight == CurrencyPickerOverlay.compactListHeight)
        #expect(pushing.offset == 70)
    }

    /// 확장 높이가 축소 하한보다 작은 소형 화면. 하한을 화면 높이로 함께 클램프하지 않으면
    /// 끌지도 않았는데 밀림 거리가 남아 시트가 내려간 채로 그려진다.
    @Test("확장 높이가 축소 하한보다 작아도 끌기 전에는 제자리이고 끈 만큼만 내려간다")
    func smallScreenKeepsSheetAtRestUntilDragged() {
        let smallExpanded = CurrencyPickerOverlay.compactListHeight - 40

        let atRest = CurrencyPickerOverlay.sheetGeometry(
            isExpanded: true,
            expandedListHeight: smallExpanded,
            dragTranslation: 0
        )
        #expect(atRest.listHeight == smallExpanded)
        #expect(atRest.offset == 0)

        let dragged = CurrencyPickerOverlay.sheetGeometry(
            isExpanded: false,
            expandedListHeight: smallExpanded,
            dragTranslation: 100
        )
        #expect(dragged.listHeight == smallExpanded)
        #expect(dragged.offset == 100)
    }

    @Test("닫기 임계는 밀린 거리를 넘을 때만 초과한다")
    func offsetCrossesDismissThresholdOnlyBeyondIt() {
        let atThreshold = CurrencyPickerOverlay.sheetGeometry(
            isExpanded: false,
            expandedListHeight: expandedListHeight,
            dragTranslation: CurrencyPickerOverlay.dismissThreshold
        )
        #expect(atThreshold.offset == CurrencyPickerOverlay.dismissThreshold)

        let beyondThreshold = CurrencyPickerOverlay.sheetGeometry(
            isExpanded: false,
            expandedListHeight: expandedListHeight,
            dragTranslation: CurrencyPickerOverlay.dismissThreshold + 1
        )
        #expect(beyondThreshold.offset > CurrencyPickerOverlay.dismissThreshold)
    }

    @Test("축소 상태는 밀린 거리가 임계를 넘어야 닫고, 그 전까지는 닫지 않는다")
    func compactDismissesOnlyBeyondThreshold() {
        func outcome(_ dragTranslation: CGFloat) -> CurrencyPickerOverlay.DragOutcome {
            CurrencyPickerOverlay.dragOutcome(
                isExpanded: false,
                expandedListHeight: expandedListHeight,
                dragTranslation: dragTranslation
            )
        }

        #expect(outcome(CurrencyPickerOverlay.dismissThreshold + 1) == .dismiss)
        #expect(outcome(CurrencyPickerOverlay.dismissThreshold) != .dismiss)
        #expect(outcome(10) == .stay)
        #expect(outcome(-100) == .expand)
    }

    /// 확장 상태의 아래 드래그는 먼저 축소를 부르고, 하한을 넘어 더 끌었을 때만 닫는다.
    @Test("확장 상태는 축소를 거친 뒤에야 닫힌다")
    func expandedCollapsesBeforeDismissing() {
        let toCompactHeight = expandedListHeight - CurrencyPickerOverlay.compactListHeight

        func outcome(_ dragTranslation: CGFloat) -> CurrencyPickerOverlay.DragOutcome {
            CurrencyPickerOverlay.dragOutcome(
                isExpanded: true,
                expandedListHeight: expandedListHeight,
                dragTranslation: dragTranslation
            )
        }

        #expect(outcome(toCompactHeight) == .collapse)
        #expect(outcome(toCompactHeight + CurrencyPickerOverlay.dismissThreshold) == .collapse)
        #expect(outcome(toCompactHeight + CurrencyPickerOverlay.dismissThreshold + 1) == .dismiss)
    }
}
