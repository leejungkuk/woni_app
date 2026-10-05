//
//  BudgetEditViewModel+CategorySlot.swift
//  woni_app
//

import Foundation

/// 카테고리 금액 줄 아래 한 자리(UI_GUIDE "먼저 적은 쪽이 기준이다").
enum BudgetEditCategorySlot: Equatable {
    case none
    /// 갈래 A, 전체 > 합 — "그 외 카테고리" 줄.
    case otherCategories(Decimal)
    /// 갈래 A, 합 > 전체 — 경고 줄, 저장 꺼짐.
    case excess(Decimal)
    /// 넘는 입력을 막은 직후 — 경고 줄.
    case overTotal

    /// 금액을 뺀 종류. 카테고리 칸 키보드 맞춤은 이것이 바뀔 때 다시 맞춘다 — 그 외 줄 금액만 바뀌는 키마다 스크롤하지 않고,
    /// 자리가 없다가 생길 때(없음 → 그 외)도 놓치지 않는다.
    enum Kind {
        case none, otherCategories, excess, overTotal
    }

    var kind: Kind {
        switch self {
        case .none: .none
        case .otherCategories: .otherCategories
        case .excess: .excess
        case .overTotal: .overTotal
        }
    }

    /// 합 초과 경고 → 넘는 입력 경고 → 그 외 카테고리 순이다. 합 초과가 있는 동안은 이 경고 줄만 보인다(가정).
    init(draft: BudgetEditDraft, showsOverTotalWarning: Bool) {
        if let excess = draft.categoryExcess {
            self = .excess(excess)
        } else if showsOverTotalWarning {
            self = .overTotal
        } else if let other = draft.otherCategoriesAmount {
            self = .otherCategories(other)
        } else {
            self = .none
        }
    }
}

/// "그 외 카테고리" 자리·입력 방법 안내 판정(읽기 전용). 경고를 켜고 끄는 동작은 `BudgetEditViewModel.swift` 에 둔다.
extension BudgetEditViewModel {
    var categorySlot: BudgetEditCategorySlot {
        BudgetEditCategorySlot(draft: draft, showsOverTotalWarning: showsCategoryOverTotalWarning)
    }

    /// 전체 칸 아래 — 빈 화면은 두 길 설명, 갈래 B 는 "카테고리 합계", 갈래 A 는 없음(전체를 지우는 중도 A 다).
    func totalHint(_ language: AppLanguage) -> String? {
        switch draft.totalMode {
        case .empty: WoniStrings.budgetEditTotalHint(language)
        case .direct: nil
        case .categorySum: WoniStrings.budgetEditCategorySum(language)
        }
    }

    /// 칩 묶음 아래 — 빈 화면은 없음.
    func categoryHint(_ language: AppLanguage) -> String? {
        switch draft.totalMode {
        case .empty: nil
        case .direct: WoniStrings.budgetEditCategoryHintDirect(language)
        case .categorySum: WoniStrings.budgetEditCategoryHint(language)
        }
    }
}
