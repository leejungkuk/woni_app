//
//  WoniStringsBudgetEditTests.swift
//  woni_appTests
//

import Testing
@testable import woni_app

/// 예산 편집 화면 문구 중 수·달을 넣는 것(UI_GUIDE en 표). en 건수 문구는 1건/여러 건을 나눈다.
@MainActor
struct WoniStringsBudgetEditTests {
    @Test("삭제된 카테고리를 빼고 불러온 토스트 — en 은 1개와 여러 개를 나눈다")
    func droppedCategoriesToastPluralizes() {
        let dropped = WoniStrings.budgetEditDroppedDeletedCategories
        #expect(dropped(1, .ko) == "삭제된 카테고리 1개는 빼고 불러왔습니다.")
        #expect(dropped(1, .en) == "Copied without 1 deleted category.")
        #expect(dropped(2, .en) == "Copied without 2 deleted categories.")
    }

    @Test("이 달 예산 삭제 확인 창 제목은 그 달 이름을 넣는다")
    func deleteDialogTitleUsesMonth() {
        #expect(WoniStrings.budgetEditDeleteDialogTitle(month: 5, language: .ko) == "5월 예산을 삭제할까요?")
        #expect(WoniStrings.budgetEditDeleteDialogTitle(month: 5, language: .en) == "Delete your May budget?")
    }

    @Test("사용액 줄은 그 달 이름과 금액을 넣는다")
    func spentLineUsesMonthAndAmount() {
        #expect(WoniStrings.budgetEditSpent(month: 5, amountText: "330,000", language: .ko) == "5월에 쓴 돈 330,000")
        #expect(WoniStrings.budgetEditSpent(month: 5, amountText: "330,000", language: .en) == "Spent in May: 330,000")
    }

    @Test("나눌 수 있는 금액 줄 — en 도 ko 처럼 라벨과 금액을 나눈다")
    func paymentRemainingFollowsGuide() {
        let en = WoniStrings.budgetEditPaymentRemaining("100,000", language: .en)
        #expect(en.label == "Left to split")
        #expect(en.amount == "100,000")
        let ko = WoniStrings.budgetEditPaymentRemaining("100,000", language: .ko)
        #expect(ko.label == "나눌 수 있는 금액")
        #expect(ko.amount == "100,000")
    }

    @Test("예산 탭 토스트 다섯 — 저장됨·삭제됨·다시 불러옴·범위 밖 달·서버 시각 실패가 UI_GUIDE 표와 같다")
    func tabToastsFollowGuide() {
        #expect(WoniStrings.budgetSavedToast(.ko) == "예산이 저장되었습니다.")
        #expect(WoniStrings.budgetSavedToast(.en) == "Budget saved.")
        #expect(WoniStrings.budgetDeletedToast(.ko) == "예산이 삭제되었습니다.")
        #expect(WoniStrings.budgetDeletedToast(.en) == "Budget deleted.")
        #expect(WoniStrings.budgetCategoryDeletedReloadedToast(.ko) == "삭제된 카테고리가 있어 예산을 다시 불러왔습니다.")
        #expect(
            WoniStrings.budgetCategoryDeletedReloadedToast(.en)
                == "A category was deleted, so your budget was reloaded."
        )
        #expect(WoniStrings.budgetMonthNotAllowedToast(.ko) == "이 달의 예산은 정할 수 없습니다.")
        #expect(WoniStrings.budgetMonthNotAllowedToast(.en) == "You can't set a budget for this month.")
        #expect(WoniStrings.budgetServerMonthFailedToast(.ko) == "예산을 불러올 수 없습니다. 연결을 확인해 주세요.")
        #expect(
            WoniStrings.budgetServerMonthFailedToast(.en)
                == "Couldn't load your budget. Check your network connection and try again."
        )
    }

    @Test("예산 탭 토스트 다섯 경우의 ko 문구 — 성공(저장·삭제)만 체크 아이콘이다")
    func tabToastCasesMapToGuide() {
        let reloaded = BudgetTabToast.reloaded(.categoryDeletedReloaded)
        let monthNotAllowed = BudgetTabToast.reloaded(.monthNotAllowed)
        #expect(BudgetTabToast.saved.message(.ko) == "예산이 저장되었습니다.")
        #expect(BudgetTabToast.deleted.message(.ko) == "예산이 삭제되었습니다.")
        #expect(reloaded.message(.ko) == "삭제된 카테고리가 있어 예산을 다시 불러왔습니다.")
        #expect(monthNotAllowed.message(.ko) == "이 달의 예산은 정할 수 없습니다.")
        #expect(BudgetTabToast.serverMonthFailed.message(.ko) == "예산을 불러올 수 없습니다. 연결을 확인해 주세요.")

        #expect(BudgetTabToast.saved.showsCheckmark)
        #expect(BudgetTabToast.deleted.showsCheckmark)
        #expect(!reloaded.showsCheckmark)
        #expect(!monthNotAllowed.showsCheckmark)
        #expect(!BudgetTabToast.serverMonthFailed.showsCheckmark)
    }
}

extension WoniStringsBudgetEditTests {
    @Test("BETR.S0-R8 먼저 적은 쪽 규칙 문구가 UI_GUIDE en 표 2026-10-05 줄과 글자까지 같다 — 빈 화면 안내는 두 줄")
    func totalRuleCopyFollowsGuide() {
        #expect(
            WoniStrings.budgetEditTotalHint(.ko)
                == "전체 금액을 먼저 정하면 카테고리는 그 안에서 나눕니다.\n카테고리부터 정하면 합계가 전체 금액이 됩니다."
        )
        #expect(
            WoniStrings.budgetEditTotalHint(.en)
                == "Set a total first to split it across categories.\n"
                + "Start with categories and their sum becomes your total."
        )
        #expect(WoniStrings.budgetEditCategoryHintDirect(.ko) == "전체 금액 안에서 나눠 정합니다.")
        #expect(WoniStrings.budgetEditCategoryHintDirect(.en) == "Split within your total.")
        #expect(WoniStrings.budgetEditCategoryOverTotal(.ko) == "카테고리 합은 전체 금액을 넘을 수 없습니다.")
        #expect(WoniStrings.budgetEditCategoryOverTotal(.en) == "Categories can't add up to more than your total.")
        #expect(
            WoniStrings.budgetEditCategoryExcess("100,000", language: .ko)
                == "카테고리 합이 전체보다 100,000 많습니다. 줄여야 저장할 수 있습니다."
        )
        #expect(
            WoniStrings.budgetEditCategoryExcess("100,000", language: .en)
                == "Categories are 100,000 over your total. Lower them to save."
        )
        #expect(WoniStrings.budgetEditTotalLocked(.ko) == "전체는 카테고리 합계입니다. 직접 정하려면 카테고리 금액을 비우세요.")
        #expect(
            WoniStrings.budgetEditTotalLocked(.en)
                == "Your total is the sum of your categories. Clear the category amounts to set it yourself."
        )
        #expect(WoniStrings.budgetEditMaximum("200,000", language: .ko) == "최대 200,000")
        #expect(WoniStrings.budgetEditMaximum("200,000", language: .en) == "Up to 200,000")

        // 짝: 갈래 B 칩 아래 문구는 그대로다.
        #expect(WoniStrings.budgetEditCategoryHint(.ko) == "정한 금액은 전체에 더해집니다.")
        #expect(WoniStrings.budgetEditCategoryHint(.en) == "Amounts here add up to your total.")
    }
}
