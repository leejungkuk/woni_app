//
//  BudgetTabToast.swift
//  woni_app
//

/// 예산 탭 위 토스트. 성공(저장·삭제)만 체크 아이콘이다(UI_GUIDE "토스트는 한 줄").
enum BudgetTabToast: Equatable {
    case saved, deleted, reloaded(BudgetEditReloadReason), serverMonthFailed

    var showsCheckmark: Bool {
        switch self {
        case .saved, .deleted: true
        case .reloaded, .serverMonthFailed: false
        }
    }

    func message(_ language: AppLanguage) -> String {
        switch self {
        case .saved: WoniStrings.budgetSavedToast(language)
        case .deleted: WoniStrings.budgetDeletedToast(language)
        case .reloaded(.categoryDeletedReloaded): WoniStrings.budgetCategoryDeletedReloadedToast(language)
        case .reloaded(.monthNotAllowed): WoniStrings.budgetMonthNotAllowedToast(language)
        case .serverMonthFailed: WoniStrings.budgetServerMonthFailedToast(language)
        }
    }
}
