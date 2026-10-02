//
//  RootOverlayModelTests.swift
//  woni_appTests
//

import SwiftUI
import Testing
@testable import woni_app

/// 루트가 탭바 위에 그리는 오버레이 한 칸을 지킨다.
@MainActor
struct RootOverlayModelTests {
    @Test("모두 닫으면 떠 있던 오버레이가 없어지고 그 화면의 닫기 처리가 한 번 불린다")
    func dismissAllClearsPresentedOverlay() {
        let model = RootOverlayModel()
        var dismissAllCount = 0
        model.present(.reportMonthPicker, content: EmptyView(), onDismissAll: { dismissAllCount += 1 })

        model.dismissAll()

        #expect(model.presentation == nil)
        #expect(!model.isPresented(.reportMonthPicker))
        #expect(dismissAllCount == 1)

        // 이미 닫힌 뒤 다시 리셋돼도 화면의 닫기 처리를 또 부르지 않는다.
        model.dismissAll()
        #expect(dismissAllCount == 1)
    }

    @Test("화면은 자기 오버레이만 닫는다 — 다른 오버레이가 떠 있으면 그대로이고 리셋용 닫기 처리는 부르지 않는다")
    func dismissClosesOnlyItsOwnOverlay() {
        let model = RootOverlayModel()
        var dismissAllCount = 0
        model.present(.withdrawConfirm, content: EmptyView(), onDismissAll: { dismissAllCount += 1 })

        model.dismiss(.ledgerMonthPicker)
        #expect(model.isPresented(.withdrawConfirm))

        model.dismiss(.withdrawConfirm)
        #expect(model.presentation == nil)
        #expect(dismissAllCount == 0)
    }
}
