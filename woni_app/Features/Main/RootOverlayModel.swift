//
//  RootOverlayModel.swift
//  woni_app
//

import SwiftUI

/// 루트가 탭바보다 위에 화면 전체로 그리는 오버레이. 입력 화면·카테고리 관리 화면의 것은 전체 화면 모달 안이라 여기 없다.
enum RootOverlay: Hashable {
    case ledgerMonthPicker
    case reportMonthPicker
    case budgetMonthPicker
    case baseCurrencyPicker
    case withdrawConfirm
    case purgeConfirm
    case notificationAsk
}

/// 지금 떠 있는 오버레이 한 칸. 화면은 무엇을 띄울지만 알리고 루트가 그린다 — 신원 리셋이 한 번에 닫는다.
@MainActor
@Observable
final class RootOverlayModel {
    struct Presentation {
        let overlay: RootOverlay
        let content: AnyView
        /// 루트가 리셋으로 닫을 때만 부른다. 확인 창은 취소와 같게 화면 상태를 되돌린다.
        let onDismissAll: () -> Void
    }

    private(set) var presentation: Presentation?

    func isPresented(_ overlay: RootOverlay) -> Bool {
        presentation?.overlay == overlay
    }

    func present(_ overlay: RootOverlay, content: some View, onDismissAll: @escaping () -> Void = {}) {
        presentation = Presentation(overlay: overlay, content: AnyView(content), onDismissAll: onDismissAll)
    }

    /// 화면이 자기 오버레이를 닫는다. 다른 오버레이가 떠 있으면 건드리지 않는다.
    func dismiss(_ overlay: RootOverlay) {
        guard isPresented(overlay) else {
            return
        }

        presentation = nil
    }

    func dismissAll() {
        let dismissed = presentation
        presentation = nil
        dismissed?.onDismissAll()
    }
}
