//
//  BudgetEditViewModel+Lines.swift
//  woni_app
//

import Foundation

/// 금액 줄·칩 판정(읽기 전용). 동작(줄 빼기·삭제된 칩 넣기·모두 지우기)은 `BudgetEditViewModel.swift` 에 둔다 —
/// 초안 바꾸기(`edit`)와 확인 창(`pending`)을 파일 밖에 열지 않으려고 판정만 나눴다.
extension BudgetEditViewModel {
    /// 칩 묶음 맨 뒤 "삭제된 카테고리" 칩 — 이 달 응답의 서버 목록 `deletedCategoriesWithSpending`(그 달 지출 거래가 있는
    /// 삭제된 카테고리)에서 지금 줄에 있는 카테고리를 뺀 것, 서버 목록 순서. 몫·쓴 돈은 보지 않는다 — 서버가 거래 존재로
    /// 정한 목록이라 몫 없이 쓴 돈만 있던 카테고리도 들어가고, 환율이 없거나 통화를 바꿔 환산이 0 이어도 남는다. 줄이 어느
    /// 길로 빠졌든(X·모두 지우기·지난 달 불러오기) 같다. 서버는 이미 몫이 있는 삭제된 카테고리와 이 목록의 카테고리를 저장에서
    /// 받는다(인계 2026-10-05 budget-deployed §3). 응답이 없으면(신원 없는 비회원·읽는 중) 비어 있다.
    var deletedChipCategoryIDs: [Int] {
        let lineIDs = resolvedLineCategoryIDs
        return (monthBudget?.deletedCategoriesWithSpending ?? [])
            .map(\.id)
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

    /// 이 달 응답이 삭제로 표시한 카테고리(서버 번호) — 삭제된 줄과 서버 목록 `deletedCategoriesWithSpending` 을 합친 것.
    /// 목록을 빼면 몫 없는 목록 카테고리가 삭제가 안 도착한 기기에서만 보통 칩과 삭제된 칩 두 곳에 보인다. 응답이 없으면
    /// 비어 있다.
    var serverDeletedCategoryIDs: Set<Int> {
        guard let monthBudget else {
            return []
        }
        return Set(monthBudget.categories.filter(\.isDeleted).map(\.category.id))
            .union(monthBudget.deletedCategoriesWithSpending.map(\.id))
    }
}

extension BudgetEditLineLabel {
    /// 아이콘 없는 줄 이름 — 줄 끝 X 의 VoiceOver 라벨에 쓴다(UI_GUIDE "금액 줄 끝 X"). 줄에 보이는 이름은 아이콘을 붙인다.
    func bareName(_ language: AppLanguage) -> String {
        switch self {
        case .deleted:
            WoniStrings.budgetDeletedCategory(language)
        case let .category(category):
            CategoryDisplayNameResolver.localizedName(for: category, language: language)
        }
    }
}
