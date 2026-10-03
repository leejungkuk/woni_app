//
//  BudgetEditToast.swift
//  woni_app
//

/// 예산 편집 화면 토스트. 안내·실패라 체크 아이콘이 없다(UI_GUIDE "토스트는 한 줄").
enum BudgetEditToast: Equatable {
    case totalBelowCategorySum
    case amountOverLimit
    case noPreviousBudget
    case previousLoadFailed
    case droppedDeletedCategories(Int)
    /// 저장의 "그 밖·연결 실패" — 신원 발급 실패도 같다.
    case saveFailed
    /// `이 달 예산 삭제` 의 "그 밖·연결 실패"(2026-10-04 사용자 결정 — 저장 문구와 나눔).
    case deleteFailed
    case categoryUploadFailed
    case totalRequired
    case allocationExceedsTotal

    func message(_ language: AppLanguage) -> String {
        switch self {
        case .totalBelowCategorySum:
            WoniStrings.budgetEditTotalBelowCategorySum(language)
        case .amountOverLimit:
            WoniStrings.amountOverLimitToast(language, limit: AddExpenseViewModel.maximumAmountLabel)
        case .noPreviousBudget:
            WoniStrings.budgetEditNoPreviousBudget(language)
        case .previousLoadFailed:
            WoniStrings.budgetEditPreviousLoadFailed(language)
        case let .droppedDeletedCategories(count):
            WoniStrings.budgetEditDroppedDeletedCategories(count, language: language)
        case .saveFailed:
            WoniStrings.budgetEditSaveFailed(language)
        case .deleteFailed:
            WoniStrings.budgetEditDeleteFailed(language)
        case .categoryUploadFailed:
            WoniStrings.budgetEditCategoryUploadFailed(language)
        case .totalRequired:
            WoniStrings.budgetEditTotalRequired(language)
        case .allocationExceedsTotal:
            WoniStrings.budgetEditAllocationExceedsTotal(language)
        }
    }
}
