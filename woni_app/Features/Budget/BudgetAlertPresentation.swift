//
//  BudgetAlertPresentation.swift
//  woni_app
//

import SwiftUI

/// 예산 알림창을 지금 띄울 수 있는지(UI_GUIDE "예산 알림창" 띄우는 때). 루트가 만든다.
/// 예산 탭 선택은 보지 않는다 — 어느 탭에서든 띄운다.
struct BudgetAlertGate: Equatable {
    var isAppActive: Bool
    var hasRootToast: Bool
    var hasBudgetToast: Bool
    var isEntryOpen: Bool
    /// 편집 모달이 아니라 편집 회차다 — 모달은 결과 반영보다 먼저 닫혀, 모달로 보면 그 틈에 창이 저장 토스트보다 먼저 뜬다.
    var isEditSessionOpen: Bool
    var hasRootOverlay: Bool

    var canShow: Bool {
        isAppActive && !hasRootToast && !hasBudgetToast && !isEntryOpen && !isEditSessionOpen && !hasRootOverlay
    }
}

/// 루트가 예산 알림창을 띄우고 닫고, 이 기기의 예산 저장·삭제 응답을 판정기에 넘기는 길(UI_GUIDE "예산 알림창").
/// 언제 부를지는 루트가 정하고 무엇을 할지는 여기서 정한다.
enum BudgetAlertPresentation {
    /// 띄울 수 있고 기다리는 창이 있으면 markShown 이 true 일 때만 `.budgetAlert` 오버레이로 올린다. 올렸으면 true.
    /// 기록은 창이 뜬 순간 `markShown` 이 남긴다 — 판정기를 거치지 않고 올리면 같은 창이 다음 판정에서 또 뜬다.
    @MainActor @discardableResult
    static func presentIfPossible(
        gate: BudgetAlertGate,
        evaluator: BudgetAlertEvaluator,
        overlays: RootOverlayModel
    ) -> Bool {
        guard gate.canShow, let alert = evaluator.pendingAlert, evaluator.markShown(alert) else {
            return false
        }
        overlays.present(
            .budgetAlert,
            content: BudgetAlertDialog(alert: alert, onConfirm: { overlays.dismiss(.budgetAlert) })
        )
        return true
    }

    /// 판정기의 `resetGeneration` 이 바뀌면(로그아웃·계정 전환·purge) 떠 있는 알림창만 닫는다. 다른 오버레이(purge 중의
    /// 설정 확인 창 등)는 그 화면이 닫는다.
    @MainActor
    static func dismissAfterReset(_ overlays: RootOverlayModel) {
        overlays.dismiss(.budgetAlert)
    }

    /// 편집 결과 중 저장·삭제 응답만 판정기에 넘긴다. 닫기·다시 불러오기는 넘기지 않는다.
    /// 표는 쓰기 직전에 받은 것이다 — 계정·세대가 바뀐 뒤 늦게 온 응답은 판정기가 버린다. 쓰기 전에 끝난 편집은 표가 nil 이다.
    @MainActor
    static func forward(
        _ outcome: BudgetEditOutcome,
        token: BudgetAlertSaveToken?,
        to evaluator: BudgetAlertEvaluator
    ) {
        guard let token else {
            return
        }
        switch outcome {
        case let .saved(budget, _), let .deleted(budget, _):
            evaluator.observeSavedBudget(budget, token: token)
        case .dismissed, .reloadRequired:
            return
        }
    }
}
