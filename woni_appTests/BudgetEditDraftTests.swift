//
//  BudgetEditDraftTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 편집 화면의 금액 계산(스펙 §2.1·§2.4·§2.5). T = 직접 입력한 전체, S = 카테고리 몫의 합.
/// 따로 적지 않으면 통화는 KRW 다.
@MainActor
struct BudgetEditDraftTests {
    // MARK: 전체 = max(T, S)

    @Test("T 가 없으면 전체는 카테고리 합을 따라 오르내리고 '카테고리 합계' 상태다")
    func totalFollowsCategorySumWithoutDirectTotal() {
        var draft = makeDraft(lines: [line(1, 300_000), line(2, 100_000)])

        #expect(draft.categorySum == 400_000)
        #expect(draft.total == 400_000)
        #expect(draft.isTotalAutomatic)
        #expect(draft.otherCategoriesAmount == nil)
        #expect(draft.isSaveable)

        let cleared = draft.setCategoryAmount(nil, for: 2)
        #expect(cleared == .accepted)
        #expect(draft.total == 300_000)
    }

    @Test("카테고리 합이 0 이면 전체는 빈칸이고 저장·결제수단 입력이 꺼진다 — 직접 적은 0 만 0원 예산이다")
    func zeroCategorySumLeavesTotalEmpty() {
        var draft = makeDraft(lines: [line(1, 0), line(2, 0)])

        #expect(draft.categorySum == 0)
        #expect(draft.total == nil)
        #expect(!draft.isTotalAutomatic)
        #expect(!draft.isSaveable)
        #expect(!draft.isPaymentInputEnabled)

        // 줄이 아예 없어도 같다.
        let empty = makeDraft()
        #expect(empty.total == nil)
        #expect(!empty.isSaveable)

        draft.setDirectTotal(0)
        #expect(draft.total == 0)
        #expect(!draft.isTotalAutomatic)
        #expect(draft.isSaveable)
    }

    @Test("T 가 S 보다 크면 전체는 T 이고 차이가 '그 외 카테고리'다")
    func directTotalAboveSumShowsOtherCategories() {
        let draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000), line(2, 100_000)])

        #expect(draft.total == 500_000)
        #expect(draft.otherCategoriesAmount == 100_000)
        #expect(!draft.isTotalAutomatic)
        #expect(draft.isSaveable)
    }

    @Test("T 를 S 보다 작게 적고 끝내도 S 로 맞추지 않는다 — 입력 중에도 끝낸 뒤에도 전체는 T 이고 넘은 만큼이 남는다")
    func endingTotalBelowSumKeepsTyped() {
        var below = makeDraft(directTotal: 500_000, lines: [line(1, 300_000), line(2, 100_000)])
        below.setDirectTotal(300_000)

        #expect(below.directTotal == 300_000)
        #expect(below.total == 300_000)
        below.endTotalEditing()
        #expect(below.directTotal == 300_000)
        #expect(below.total == 300_000)
        #expect(below.categoryExcess == 100_000)

        var above = makeDraft(directTotal: 500_000, lines: [line(1, 300_000), line(2, 100_000)])
        above.endTotalEditing()
        #expect(above.directTotal == 500_000)

        // T 가 없으면(카테고리 합계) 끝내도 그대로다.
        var automatic = makeDraft(lines: [line(1, 300_000)])
        automatic.endTotalEditing()
        #expect(automatic.directTotal == nil)
        #expect(automatic.total == 300_000)
    }

    @Test("카테고리 입력으로 S 가 99,999,999 를 넘으면 거절하고 아무것도 바꾸지 않는다 — 검사는 바꾼 뒤의 S 로 한다")
    func categoryInputBeyondLimitIsRejected() {
        var draft = makeDraft(lines: [line(1, 99_998_999), line(2, nil)])

        let atLimit = draft.setCategoryAmount(1000, for: 2)
        #expect(atLimit == .accepted)
        #expect(draft.categorySum == 99_999_999)
        #expect(draft.total == 99_999_999)

        let overLimit = draft.setCategoryAmount(1001, for: 2)
        #expect(overLimit == .overLimit)
        #expect(draft.categoryLines.map(\.amount) == [99_998_999, 1000])
        #expect(draft.categorySum == 99_999_999)

        // 그 줄의 옛 값을 빼고 센다 — 지금 S 에 새 값을 더하면 999 로 줄이는 입력까지 막힌다.
        let lowered = draft.setCategoryAmount(999, for: 2)
        #expect(lowered == .accepted)
        #expect(draft.categorySum == 99_999_998)
    }

    @Test("S 가 T 를 넘게 하는 카테고리 입력은 거절되고 전체는 T 그대로다 — 줄이면 '그 외 카테고리'가 그만큼 는다")
    func categoryInputCannotOutgrowTyped() {
        var draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000), line(2, 100_000)])

        #expect(draft.total == 500_000)
        #expect(draft.otherCategoriesAmount == 100_000)

        let raised = draft.setCategoryAmount(300_000, for: 2)
        #expect(raised == .overTotal)
        #expect(draft.total == 500_000)
        #expect(draft.directTotal == 500_000)
        #expect(draft.otherCategoriesAmount == 100_000)

        let lowered = draft.setCategoryAmount(50000, for: 2)
        #expect(lowered == .accepted)
        #expect(draft.total == 500_000)
        #expect(draft.otherCategoriesAmount == 150_000)
    }

    @Test("새 카테고리를 올린 뒤 임시 번호를 서버 번호로 바꾸면 금액은 그대로이고 칩이 다시 나타나지 않는다")
    func remapReplacesTemporaryIDs() {
        var draft = makeDraft(lines: [line(-3, 50000)])

        draft.remapCategoryIDs { $0 == -3 ? 42 : $0 }

        #expect(draft.categoryLines.map(\.categoryID) == [42])
        #expect(draft.categoryLines.map(\.amount) == [50000])
        #expect(draft.chipCategoryIDs(chipOrder: [42, 1]) == [1])

        // 여러 번 불러도 같다.
        let once = draft
        draft.remapCategoryIDs { $0 == -3 ? 42 : $0 }
        #expect(draft == once)
    }

    // MARK: 결제수단

    @Test("결제수단 합이 전체를 넘으면 넘은 만큼이 경고 숫자이고 저장이 꺼진다")
    func paymentExcessBlocksSave() {
        var draft = makeDraft(directTotal: 500_000)
        draft.setPaymentAmount(300_000, for: .creditCard)
        draft.setPaymentAmount(250_000, for: .cashAndDebit)

        #expect(draft.paymentSum == 550_000)
        #expect(draft.paymentExcess == 50000)
        #expect(draft.paymentRemaining == nil)
        #expect(!draft.isSaveable)
        #expect(draft.paymentMaximum(for: .cashAndDebit) == 200_000)

        draft.setPaymentAmount(150_000, for: .cashAndDebit)
        #expect(draft.paymentRemaining == 50000)
        #expect(draft.paymentExcess == nil)
        #expect(draft.isSaveable)

        // 다른 결제수단 합이 전체보다 크면 최대는 0 이다(음수 아님).
        draft.setPaymentAmount(600_000, for: .creditCard)
        #expect(draft.paymentMaximum(for: .cashAndDebit) == 0)
        #expect(!draft.isSaveable)
    }

    @Test("결제수단 합이 전체와 같으면 넘은 것이 아니다 — 저장할 수 있고 나눌 수 있는 금액은 0 이다")
    func paymentSumEqualToTotalIsSaveable() {
        var draft = makeDraft(directTotal: 500_000)
        draft.setPaymentAmount(500_000, for: .creditCard)

        #expect(draft.paymentExcess == nil)
        #expect(draft.paymentRemaining == 0)
        #expect(draft.isSaveable)

        draft.setPaymentAmount(500_001, for: .creditCard)
        #expect(draft.paymentExcess == 1)
        #expect(draft.paymentRemaining == nil)
        #expect(!draft.isSaveable)
    }

    @Test("전체가 없으면 결제수단을 입력할 수 없고 최대도 없다")
    func paymentInputNeedsTotal() {
        var draft = makeDraft()

        #expect(!draft.isPaymentInputEnabled)
        #expect(draft.paymentMaximum(for: .creditCard) == nil)

        draft.setDirectTotal(100_000)
        #expect(draft.isPaymentInputEnabled)
        #expect(draft.paymentMaximum(for: .creditCard) == 100_000)
    }

    @Test("칸을 비우면 빈칸으로 돌아간다 — 결제수단은 몫이 없어지고(0 이 아니다), 전체는 칸을 벗어나면 카테고리 합을 따른다")
    func clearingFieldsReturnsToEmpty() {
        var draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000)])
        draft.setPaymentAmount(300_000, for: .creditCard)
        #expect(draft.paymentAmounts[.creditCard] == 300_000)

        draft.setPaymentAmount(nil, for: .creditCard)
        #expect(draft.paymentAmounts[.creditCard] == nil)
        #expect(draft.paymentAmounts.isEmpty)

        // 0 은 빈칸이 아니라 0원 몫이다.
        draft.setPaymentAmount(0, for: .creditCard)
        #expect(draft.paymentAmounts[.creditCard] == 0)

        // T 를 지우는 동안은 전체가 없고, 칸을 벗어나면 전체는 S 다.
        draft.setDirectTotal(nil)
        #expect(draft.directTotal == nil)
        #expect(draft.total == nil)
        draft.endTotalEditing()
        #expect(draft.total == 300_000)
        #expect(draft.isTotalAutomatic)

        // 카테고리가 없으면 전체도 없다.
        var noLines = makeDraft(directTotal: 500_000)
        noLines.setDirectTotal(nil)
        #expect(noLines.directTotal == nil)
        #expect(noLines.total == nil)
    }

    // MARK: 카테고리 줄

    @Test("칩으로 넣은 줄은 누른 순서로 맨 뒤에 붙고 칩 묶음에서 빠진다 — 칩 순서 자리에 끼우지 않는다")
    func addCategoryAppendsInTapOrder() {
        let chipOrder = [-3, 1, 2, 5]
        var draft = makeDraft()

        draft.addCategory(5)
        draft.addCategory(1)
        draft.addCategory(-3)

        #expect(draft.categoryLines.map(\.categoryID) == [5, 1, -3])
        #expect(draft.categoryLines.allSatisfy { $0.amount == nil && !$0.isDeleted })
        #expect(draft.chipCategoryIDs(chipOrder: chipOrder) == [2])

        // 이미 줄이 있으면 무시한다 — 적어 둔 금액도 그대로다.
        let filled = draft.setCategoryAmount(10000, for: 1)
        #expect(filled == .accepted)
        draft.addCategory(1)
        #expect(draft.categoryLines.map(\.categoryID) == [5, 1, -3])
        #expect(draft.categoryLines[1].amount == 10000)

        // 서버가 준 삭제된 카테고리 줄은 제자리에 남고 새 줄들이 그 뒤에 붙는다.
        var withDeleted = makeDraft(lines: [BudgetEditCategoryLine(categoryID: 9, isDeleted: true, amount: 20000)])
        withDeleted.addCategory(5)
        withDeleted.addCategory(1)
        #expect(withDeleted.categoryLines.map(\.categoryID) == [9, 5, 1])
        #expect(withDeleted.categoryLines.first?.isDeleted == true)
    }

    @Test("통화를 바꿔 금액을 비우면 줄은 남고 T·몫·결제수단이 모두 빈칸이며 펼침은 그대로다")
    func clearAmountsKeepsLines() {
        var draft = makeDraft(
            directTotal: 500_000,
            lines: [line(1, 300_000), line(2, 0)],
            payments: [.creditCard: 100_000],
            isPaymentExpanded: true
        )

        draft.clearAmounts()

        #expect(draft.categoryLines.map(\.categoryID) == [1, 2])
        #expect(draft.categoryLines.allSatisfy { $0.amount == nil })
        #expect(draft.directTotal == nil)
        #expect(draft.paymentAmounts.isEmpty)
        #expect(draft.isPaymentExpanded)
        #expect(draft.total == nil)
    }

    @Test("결제수단이 접힌 채 금액을 비우면 접힌 채다 — 펼친 경우의 짝")
    func clearAmountsKeepsCollapsedPayment() {
        var draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000)], isPaymentExpanded: false)

        draft.clearAmounts()

        #expect(!draft.isPaymentExpanded)
        #expect(draft.directTotal == nil)
        #expect(draft.total == nil)
    }

    // MARK: 도우미

    private func makeDraft(
        directTotal: Decimal? = nil,
        lines: [BudgetEditCategoryLine] = [],
        payments: [PaymentGroup: Decimal] = [:],
        isPaymentExpanded: Bool = false
    ) -> BudgetEditDraft {
        BudgetEditDraft(
            currency: .krw,
            directTotal: directTotal,
            categoryLines: lines,
            paymentAmounts: payments,
            isPaymentExpanded: isPaymentExpanded
        )
    }

    private func line(_ id: Int, _ amount: Decimal?) -> BudgetEditCategoryLine {
        BudgetEditCategoryLine(categoryID: id, isDeleted: false, amount: amount)
    }
}

extension BudgetEditDraftTests {
    @Test("카테고리 칸을 비우면 줄은 남고 금액만 빈칸이다 — 0 은 빈칸이 아니라 0원 몫이다")
    func clearingCategoryAmountReturnsToEmpty() {
        var draft = makeDraft(lines: [line(1, nil)])
        let filled = draft.setCategoryAmount(200_000, for: 1)
        #expect(filled == .accepted)
        #expect(draft.categoryLines.map(\.amount) == [200_000])

        let cleared = draft.setCategoryAmount(nil, for: 1)
        #expect(cleared == .accepted)
        #expect(draft.categoryLines.map(\.categoryID) == [1])
        #expect(draft.categoryLines.map(\.amount) == [nil])

        let zeroed = draft.setCategoryAmount(0, for: 1)
        #expect(zeroed == .accepted)
        #expect(draft.categoryLines.map(\.amount) == [0])
    }

    @Test("T 가 S 와 같으면 넘은 것이 아니다 — S 보다 1 작으면 넘은 만큼 1 이고 저장이 꺼진다, 둘 다 맞추지 않는다")
    func directTotalEqualToSumIsNotExcess() {
        var equal = makeDraft(directTotal: 500_000, lines: [line(1, 200_000), line(2, 100_000)])
        equal.setDirectTotal(300_000)
        equal.endTotalEditing()
        #expect(equal.directTotal == 300_000)
        #expect(equal.categoryExcess == nil)
        #expect(equal.isSaveable)

        var below = makeDraft(directTotal: 500_000, lines: [line(1, 200_000), line(2, 100_000)])
        below.setDirectTotal(299_999)
        below.endTotalEditing()
        #expect(below.directTotal == 299_999)
        #expect(below.categoryExcess == 1)
        #expect(!below.isSaveable)
    }

    @Test("이미 있는 줄이 여럿이면 원래 순서 그대로 두고 칩으로 넣은 줄을 그 뒤에 붙인다")
    func addCategoryKeepsExistingLinesInOrder() {
        // 서버가 준 순서: 삭제된 9 다음 8.
        var draft = makeDraft(lines: [
            BudgetEditCategoryLine(categoryID: 9, isDeleted: true, amount: 20000),
            BudgetEditCategoryLine(categoryID: 8, isDeleted: true, amount: 10000)
        ])

        draft.addCategory(3)

        #expect(draft.categoryLines.map(\.categoryID) == [9, 8, 3])
        #expect(draft.categoryLines.map(\.amount) == [20000, 10000, nil])
    }
}

// MARK: 먼저 적은 쪽이 기준(UI_GUIDE 2026-10-05) — 전체 500,000 · 식비(1) 300,000 · 교통(2) 100,000

extension BudgetEditDraftTests {
    @Test("BETR.S0-R1 빈 화면에서 먼저 적은 칸이 갈래를 정한다 — 전체 먼저 A · 카테고리 먼저 B · 0 만 적으면 빈 화면 그대로")
    func firstFilledFieldPicksMode() {
        var direct = makeDraft(lines: [line(1, nil)])
        #expect(direct.totalMode == .empty)
        let typed = direct.setDirectTotal(500_000)
        #expect(typed)
        #expect(direct.totalMode == .direct)
        #expect(!direct.isTotalAutomatic)

        var bySum = makeDraft(lines: [line(1, nil)])
        #expect(bySum.setCategoryAmount(300_000, for: 1) == .accepted)
        #expect(bySum.totalMode == .categorySum)
        #expect(bySum.isTotalAutomatic)

        // 0 만 적은 카테고리는 합이 0 이라 빈 화면이다 — 전체 칸이 열려 있다.
        var zeros = makeDraft(lines: [line(1, nil), line(2, nil)])
        #expect(zeros.setCategoryAmount(0, for: 1) == .accepted)
        #expect(zeros.totalMode == .empty)
        #expect(zeros.total == nil)
        let reopened = zeros.setDirectTotal(100_000)
        #expect(reopened)
        #expect(zeros.totalMode == .direct)

        // 짝: 비우기만 하고 칸을 벗어나면 빈 화면 그대로다.
        var untouched = makeDraft(lines: [line(1, nil)])
        untouched.setDirectTotal(nil)
        untouched.endTotalEditing()
        #expect(untouched.totalMode == .empty)
        #expect(untouched.total == nil)
    }

    @Test("BETR.S0-R1 다시 열기는 저장 값으로 정한다 — 전체 > 합 A · 전체 == 합 B · 합 0 A")
    func reopeningPicksModeFromSavedTotal() {
        let lines = [
            BudgetEditTestFixture.categoryLine(1, budget: 300_000),
            BudgetEditTestFixture.categoryLine(2, budget: 100_000)
        ]
        let above = BudgetEditDraft(
            budget: BudgetEditTestFixture.makeBudget(total: 500_000, categories: lines),
            baseCurrency: .krw
        )
        #expect(above.totalMode == .direct)
        #expect(above.total == 500_000)

        let equal = BudgetEditDraft(
            budget: BudgetEditTestFixture.makeBudget(total: 400_000, categories: lines),
            baseCurrency: .krw
        )
        #expect(equal.totalMode == .categorySum)
        #expect(equal.total == 400_000)

        let noShares = BudgetEditDraft(budget: BudgetEditTestFixture.makeBudget(total: 0), baseCurrency: .krw)
        #expect(noShares.totalMode == .direct)
        #expect(noShares.total == 0)
    }

    @Test("BETR.S0-R1 지난 달을 불러와 삭제된 몫을 빼 합이 전체보다 작아지면 A · 통화 바꾸기·모두 지우기는 빈 화면")
    func previousAndClearingPickMode() {
        let previous = BudgetEditTestFixture.makeBudget(
            BudgetEditTestFixture.yearMonth(2026, 9),
            total: 400_000,
            categories: [
                BudgetEditTestFixture.categoryLine(1, budget: 300_000),
                BudgetEditTestFixture.categoryLine(9, budget: 100_000, isDeleted: true)
            ]
        )
        var loaded = BudgetEditDraft(emptyWith: .krw)
        let dropped = loaded.applyPrevious(previous)
        #expect(dropped == 1)
        #expect(loaded.totalMode == .direct)
        #expect(loaded.total == 400_000)

        var currencyCleared = makeDraft(directTotal: 500_000, lines: [line(1, 300_000), line(2, 100_000)])
        currencyCleared.clearAmounts()
        #expect(currencyCleared.totalMode == .empty)

        var allCleared = makeDraft(lines: [line(1, 300_000)])
        #expect(allCleared.totalMode == .categorySum)
        allCleared.clearAll()
        #expect(allCleared.totalMode == .empty)

        // 전체를 비우는 중(A)이어도 빈 화면으로 돌아간다.
        let clears: [(inout BudgetEditDraft) -> Void] = [{ $0.clearAmounts() }, { $0.clearAll() }]
        for clear in clears {
            var clearing = makeDraft(directTotal: 500_000, lines: [line(1, 300_000)])
            clearing.setDirectTotal(nil)
            #expect(clearing.totalMode == .direct)
            clear(&clearing)
            #expect(clearing.totalMode == .empty)
        }
    }

    @Test("BETR.S0-R2 갈래 A 에서 카테고리는 전체 안에서만 받는다 — 합 == 전체는 받고 전체 + 1 은 줄·합·전체 그대로 거절")
    func directModeCapsCategorySum() {
        var draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000), line(2, 100_000)])

        #expect(draft.setCategoryAmount(200_001, for: 2) == .overTotal)
        #expect(draft.categoryLines.map(\.amount) == [300_000, 100_000])
        #expect(draft.categorySum == 400_000)
        #expect(draft.total == 500_000)

        #expect(draft.setCategoryAmount(200_000, for: 2) == .accepted)
        #expect(draft.categorySum == 500_000)
        #expect(draft.total == 500_000)

        // 빈칸으로 지우기는 늘 받는다.
        #expect(draft.setCategoryAmount(nil, for: 1) == .accepted)
        #expect(draft.categoryLines.map(\.amount) == [nil, 200_000])

        // 소수 통화도 같은 경계다 — 전체 500.00 · 식비 300.25.
        var usd = BudgetEditDraft(
            currency: .usd,
            directTotal: cents(50000),
            categoryLines: [line(1, cents(30025)), line(2, nil)]
        )
        #expect(usd.setCategoryAmount(cents(19976), for: 2) == .overTotal)
        #expect(usd.categoryLines.map(\.amount) == [cents(30025), nil])
        #expect(usd.setCategoryAmount(cents(19975), for: 2) == .accepted)
        #expect(usd.categorySum == cents(50000))
    }

    @Test("BETR.S0-R2 합이 이미 전체를 넘었어도 줄이거나 같은 값은 받고 늘리는 값은 거절한다")
    func excessStateAcceptsOnlyLowering() {
        var draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000), line(2, 100_000)])
        let lowered = draft.setDirectTotal(350_000)
        #expect(lowered)
        #expect(draft.categoryExcess == 50000)

        #expect(draft.setCategoryAmount(150_000, for: 2) == .overTotal)
        #expect(draft.categoryLines.map(\.amount) == [300_000, 100_000])
        #expect(draft.setCategoryAmount(80000, for: 2) == .accepted)
        #expect(draft.categoryExcess == 30000)
        #expect(draft.setCategoryAmount(80000, for: 2) == .accepted)
        #expect(draft.setCategoryAmount(nil, for: 1) == .accepted)
        #expect(draft.categoryLines.map(\.amount) == [nil, 80000])
    }

    @Test("BETR.S0-R2 칸마다 최대 = 전체 − 다른 줄 합 — 다른 줄 합이 전체보다 크면 0")
    func categoryMaximumSubtractsOtherLines() {
        var draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000), line(2, 100_000), line(3, nil)])

        #expect(draft.categoryMaximum(for: 1) == 400_000)
        #expect(draft.categoryMaximum(for: 2) == 200_000)
        #expect(draft.categoryMaximum(for: 3) == 100_000)

        draft.setDirectTotal(250_000)
        #expect(draft.categoryMaximum(for: 2) == 0)
        #expect(draft.categoryMaximum(for: 1) == 150_000)
    }

    @Test("BETR.S0-R2 짝: B·빈 화면에는 최대가 없고 전체를 넘는 개념도 없다 — 상한만 본다, A 에서 상한과 전체를 함께 넘으면 전체가 먼저")
    func categoryMaximumOnlyInDirectMode() {
        var bySum = makeDraft(lines: [line(1, 300_000), line(2, 100_000)])
        #expect(bySum.categoryMaximum(for: 1) == nil)
        #expect(bySum.setCategoryAmount(900_000, for: 2) == .accepted)
        #expect(bySum.total == 1_200_000)
        #expect(bySum.categoryExcess == nil)

        let empty = makeDraft(lines: [line(1, nil)])
        #expect(empty.categoryMaximum(for: 1) == nil)

        var nearLimit = makeDraft(lines: [line(1, 99_998_999), line(2, nil)])
        #expect(nearLimit.setCategoryAmount(1001, for: 2) == .overLimit)
        #expect(nearLimit.setCategoryAmount(1, for: 42) == .overLimit)

        var direct = makeDraft(directTotal: 99_999_999, lines: [line(1, 99_998_999), line(2, nil)])
        #expect(direct.setCategoryAmount(1001, for: 2) == .overTotal)
        #expect(direct.categoryLines.map(\.amount) == [99_998_999, nil])
    }

    @Test("BETR.S0-R3 갈래 A 의 전체는 카테고리로 늘지 않는다 — 줄이면 넘은 만큼이 생기고 저장이 꺼지며, 결제수단도 이 전체로 센다")
    func directTotalNeverFollowsSum() {
        var draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000)])
        draft.setPaymentAmount(150_000, for: .creditCard)

        #expect(draft.total == 500_000)
        #expect(draft.otherCategoriesAmount == 200_000)
        #expect(draft.categoryExcess == nil)
        #expect(draft.isSaveable)
        #expect(draft.paymentRemaining == 350_000)

        let lowered = draft.setDirectTotal(200_000)
        #expect(lowered)
        #expect(draft.total == 200_000)
        #expect(draft.directTotal == 200_000)
        #expect(draft.categoryExcess == 100_000)
        #expect(draft.otherCategoriesAmount == nil)
        #expect(!draft.isSaveable)
        #expect(draft.paymentRemaining == 50000)
        #expect(draft.paymentExcess == nil)
        #expect(draft.paymentMaximum(for: .cashAndDebit) == 50000)
        #expect(draft.paymentMaximum(for: .creditCard) == 200_000)

        draft.setPaymentAmount(250_000, for: .creditCard)
        #expect(draft.paymentExcess == 50000)

        // 합 == 전체 — 넘은 것도 남는 것도 없다.
        draft.setPaymentAmount(nil, for: .creditCard)
        let matched = draft.setDirectTotal(300_000)
        #expect(matched)
        #expect(draft.categoryExcess == nil)
        #expect(draft.otherCategoriesAmount == nil)
        #expect(draft.isSaveable)
    }

    @Test("BETR.S0-R4 갈래 A 에서 전체를 비우면 입력 중에는 A·저장 꺼짐, 벗어나면 합이 있으면 B 없으면 빈 화면")
    func clearingDirectTotalThenLeaving() {
        var draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000)])
        let cleared = draft.setDirectTotal(nil)
        #expect(cleared)
        #expect(draft.totalMode == .direct)
        #expect(draft.total == nil)
        #expect(!draft.isSaveable)
        #expect(draft.otherCategoriesAmount == nil)
        #expect(!draft.isTotalAutomatic)

        // 비우는 중에는 전체가 없어 카테고리는 상한만 본다.
        #expect(draft.setCategoryAmount(700_000, for: 1) == .accepted)

        draft.endTotalEditing()
        #expect(draft.totalMode == .categorySum)
        #expect(draft.total == 700_000)
        #expect(draft.isSaveable)

        var noLines = makeDraft(directTotal: 500_000)
        noLines.setDirectTotal(nil)
        #expect(noLines.totalMode == .direct)
        noLines.endTotalEditing()
        #expect(noLines.totalMode == .empty)
        #expect(noLines.total == nil)
    }

    @Test("BETR.S0-R4 짝: 값이 있는 채 벗어나면 합보다 작아도 값·갈래 그대로다")
    func leavingWithValueKeepsDirect() {
        var draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000)])
        draft.setDirectTotal(200_000)
        draft.endTotalEditing()

        #expect(draft.totalMode == .direct)
        #expect(draft.directTotal == 200_000)
        #expect(draft.total == 200_000)
    }

    @Test("BETR.S0-R5 갈래 B 의 전체는 합을 따르고 직접 바꿀 수 없다 — 합이 0 이 되면(비우기·줄 빼기) 다시 열린다")
    func categorySumModeLocksTotal() {
        var draft = makeDraft(lines: [line(1, 300_000), line(2, nil)])
        #expect(draft.totalMode == .categorySum)
        let before = draft
        let locked = draft.setDirectTotal(1)
        #expect(!locked)
        let emptied = draft.setDirectTotal(nil)
        #expect(!emptied)
        #expect(draft == before)

        #expect(draft.setCategoryAmount(400_000, for: 1) == .accepted)
        #expect(draft.total == 400_000)

        #expect(draft.setCategoryAmount(nil, for: 1) == .accepted)
        #expect(draft.totalMode == .empty)
        #expect(draft.total == nil)
        let reopened = draft.setDirectTotal(500_000)
        #expect(reopened)
        #expect(draft.totalMode == .direct)
        #expect(draft.total == 500_000)

        var removing = makeDraft(lines: [line(1, 300_000), line(2, 100_000)])
        removing.removeCategory(1)
        #expect(removing.totalMode == .categorySum)
        #expect(removing.total == 100_000)
        removing.removeCategory(2)
        #expect(removing.totalMode == .empty)
        let removedReopened = removing.setDirectTotal(200_000)
        #expect(removedReopened)
        #expect(removing.totalMode == .direct)
    }

    /// 2자리 통화 금액 — `cents(30025)` = 300.25.
    private func cents(_ value: Int) -> Decimal {
        Decimal(value) / 100
    }
}
