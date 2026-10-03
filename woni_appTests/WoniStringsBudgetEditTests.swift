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

    @Test("나눌 수 있는 금액 줄 — en 은 UI_GUIDE 표의 한 문장, ko 는 라벨과 금액을 나눈다")
    func paymentRemainingFollowsGuide() {
        let en = WoniStrings.budgetEditPaymentRemaining("100,000", language: .en)
        #expect(en.label == "100,000 left to split")
        #expect(en.amount == nil)
        let ko = WoniStrings.budgetEditPaymentRemaining("100,000", language: .ko)
        #expect(ko.label == "나눌 수 있는 금액")
        #expect(ko.amount == "100,000")
    }
}
