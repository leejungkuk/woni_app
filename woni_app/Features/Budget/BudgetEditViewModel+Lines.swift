//
//  BudgetEditViewModel+Lines.swift
//  woni_app
//

import Foundation

/// 금액 줄·칩 판정(읽기 전용). 동작(줄 빼기·삭제된 칩 넣기·모두 지우기)은 `BudgetEditViewModel.swift` 에 둔다 —
/// 초안 바꾸기(`edit`)와 확인 창(`pending`)을 파일 밖에 열지 않으려고 판정만 나눴다.
extension BudgetEditViewModel {
    /// 칩 묶음 맨 뒤 "삭제된 카테고리" 칩 — 이 달 응답에서 몫이 있던 삭제된 카테고리 중 지금 줄에 없고 이 달에 쓴 돈이
    /// 있는 것, 응답 순서. 줄이 어느 길로 빠졌든(X·모두 지우기·지난 달 불러오기) 같다. 서버는 그 달에 이미 몫이 있던
    /// 삭제된 카테고리만 저장에서 받는다(인계 2026-10-04 budget-deleted-category-spending). 판정은 이 달 응답 값이라
    /// 통화를 바꿔 사용액 줄이 안 보여도 같다.
    var deletedChipCategoryIDs: [Int] {
        let lineIDs = resolvedLineCategoryIDs
        return (monthBudget?.categories ?? [])
            .filter { $0.isDeleted && $0.line.budgetAmount != nil && $0.line.actualAmount > 0 }
            .map(\.category.id)
            .filter { !lineIDs.contains($0) }
    }

    /// `입력 모두 지우기`. 금액(0원 포함)이 하나도 없거나 쓰는 중이면 회색이다.
    var canClearAll: Bool {
        hasAnyAmount && !isWriting
    }

    /// 금액이 하나라도 적혀 있는가. 0 도 금액이다.
    var hasAnyAmount: Bool {
        draft.directTotal != nil
            || draft.categoryLines.contains { $0.amount != nil }
            || !draft.paymentAmounts.isEmpty
    }

    var resolvedLineCategoryIDs: Set<Int> {
        Set(draft.categoryLines.map { resolvedCategoryID($0.categoryID) })
    }

    /// 이 달 응답이 삭제로 표시한 카테고리(서버 번호). 미설정 달·응답이 없으면 비어 있다.
    var serverDeletedCategoryIDs: Set<Int> {
        Set((monthBudget?.categories ?? []).filter(\.isDeleted).map(\.category.id))
    }
}
