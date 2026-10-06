//
//  BudgetAlertGateTests.swift
//  woni_appTests
//

import Testing
@testable import woni_app

/// 예산 알림창을 지금 띄울 수 있는지(UI_GUIDE "예산 알림창" 띄우는 때) — 앱이 앞이고 토스트·입력 모달·편집 회차·
/// 루트 오버레이가 모두 없을 때만이다.
@MainActor
struct BudgetAlertGateTests {
    /// 하나만 어긋난 조건.
    enum Blocker: CaseIterable {
        case appInactive, rootToast, budgetToast, entryOpen, editSessionOpen, rootOverlay

        func apply(to gate: inout BudgetAlertGate) {
            switch self {
            case .appInactive: gate.isAppActive = false
            case .rootToast: gate.hasRootToast = true
            case .budgetToast: gate.hasBudgetToast = true
            case .entryOpen: gate.isEntryOpen = true
            case .editSessionOpen: gate.isEditSessionOpen = true
            case .rootOverlay: gate.hasRootOverlay = true
            }
        }
    }

    /// 여섯 조건이 모두 맞는 조건.
    static let ready = BudgetAlertGate(
        isAppActive: true,
        hasRootToast: false,
        hasBudgetToast: false,
        isEntryOpen: false,
        isEditSessionOpen: false,
        hasRootOverlay: false
    )

    @Test("BAD.S4-R1 앱이 앞이고 토스트·입력 모달·편집 회차·루트 오버레이가 모두 없으면 띄울 수 있다")
    func allClearCanShow() {
        #expect(Self.ready.canShow)
    }

    @Test("BAD.S4-R1 조건 하나만 어긋나도 띄울 수 없다", arguments: Blocker.allCases)
    func singleBlockerPreventsShowing(_ blocker: Blocker) {
        var gate = Self.ready
        blocker.apply(to: &gate)

        #expect(!gate.canShow)
    }

    @Test("BAD.S4-R1 짝: 조건 둘이 어긋나도 띄울 수 없다 — 하나를 풀어도 남은 하나가 막는다")
    func twoBlockersPreventShowing() {
        var gate = Self.ready
        Blocker.entryOpen.apply(to: &gate)
        Blocker.budgetToast.apply(to: &gate)
        #expect(!gate.canShow)

        gate.isEntryOpen = false
        #expect(!gate.canShow)

        gate.hasBudgetToast = false
        #expect(gate.canShow)
    }
}
