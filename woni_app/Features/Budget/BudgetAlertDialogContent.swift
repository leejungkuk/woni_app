//
//  BudgetAlertDialogContent.swift
//  woni_app
//

import Foundation
import SwiftUI

/// 예산 알림창 제목·본문(UI_GUIDE "예산 알림창" 모양). 값은 판정한 응답 그대로다.
/// 본문 줄은 예산 탭 문구를 쓰고, 창에는 통화 표시가 따로 없어 금액 앞에 통화 코드를 붙인다.
struct BudgetAlertDialogContent: Equatable {
    let title: String
    /// 줄을 "\n" 으로 이은 한 덩이. 줄이 없으면 "".
    let message: String
}

extension BudgetAlertDialogContent {
    init(alert: BudgetAlert, language: AppLanguage) {
        let code = alert.currency.rawValue
        let amountText = { (amount: Decimal) in
            "\(code) \(CurrencyFormat.string(amount, currencyCode: code))"
        }
        let amountLine: String?
        switch alert.threshold {
        case .nearLimit:
            title = WoniStrings.budgetAlertNearLimitTitle(month: alert.month, language: language)
            amountLine = alert.remainingAmount.map {
                WoniStrings.budgetHeroLabel(isOver: false, language: language) + " " + amountText($0)
            }
        case .reached:
            title = WoniStrings.budgetAlertUsedUpTitle(month: alert.month, language: language)
            // 딱 100%(`REACHED`)는 넘은 돈이 없어 이 줄이 없다.
            amountLine = alert.overAmount.map { WoniStrings.budgetOverAmount(amountText($0), language: language) }
        }
        // 남은 날 줄은 서버가 남은 날·하루 금액을 둘 다 줄 때만 있다.
        let dailyLine = alert.remainingDaysIncludingToday.flatMap { days in
            alert.dailyAllowance.map { allowance in
                BudgetTotalPresentation.dailyWording(
                    allowance,
                    remainingDays: days,
                    language: language,
                    amountText: amountText
                )
            }
        }
        message = [amountLine, dailyLine].compactMap(\.self).joined(separator: "\n")
    }
}

/// 예산 알림창 — 공용 확인 창의 버튼 하나 모양이다. 언어는 띄울 때의 앱 언어다.
struct BudgetAlertDialog: View {
    @Environment(AppLanguageStore.self) private var languageStore
    let alert: BudgetAlert
    let onConfirm: () -> Void

    var body: some View {
        let language = languageStore.language
        let content = BudgetAlertDialogContent(alert: alert, language: language)
        WoniConfirmDialog(
            title: content.title,
            message: content.message,
            confirmTitle: WoniStrings.confirmOK(language),
            identifier: "budgetAlert",
            onConfirm: onConfirm
        )
    }
}
