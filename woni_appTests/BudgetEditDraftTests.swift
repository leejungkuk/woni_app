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
        #expect(cleared)
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

    @Test("T 를 S 보다 작게 적고 끝내면 T 를 S 로 맞추고 알린다 — 입력 중에는 맞추지 않는다")
    func committingTotalBelowSumClampsToSum() {
        var below = makeDraft(lines: [line(1, 300_000), line(2, 100_000)])
        below.setDirectTotal(300_000)

        #expect(below.directTotal == 300_000)
        #expect(below.total == 400_000)
        let clamped = below.commitDirectTotal()
        #expect(clamped)
        #expect(below.directTotal == 400_000)
        #expect(below.total == 400_000)

        var above = makeDraft(directTotal: 500_000, lines: [line(1, 300_000), line(2, 100_000)])
        let aboveClamped = above.commitDirectTotal()
        #expect(!aboveClamped)
        #expect(above.directTotal == 500_000)

        // T 가 없으면 맞출 것이 없다.
        var automatic = makeDraft(lines: [line(1, 300_000)])
        let automaticClamped = automatic.commitDirectTotal()
        #expect(!automaticClamped)
        #expect(automatic.directTotal == nil)
    }

    @Test("카테고리 입력으로 S 가 99,999,999 를 넘으면 거절하고 아무것도 바꾸지 않는다 — 검사는 바꾼 뒤의 S 로 한다")
    func categoryInputBeyondLimitIsRejected() {
        var draft = makeDraft(lines: [line(1, 99_998_999), line(2, nil)])

        let atLimit = draft.setCategoryAmount(1000, for: 2)
        #expect(atLimit)
        #expect(draft.categorySum == 99_999_999)
        #expect(draft.total == 99_999_999)

        let overLimit = draft.setCategoryAmount(1001, for: 2)
        #expect(!overLimit)
        #expect(draft.categoryLines.map(\.amount) == [99_998_999, 1000])
        #expect(draft.categorySum == 99_999_999)

        // 그 줄의 옛 값을 빼고 센다 — 지금 S 에 새 값을 더하면 999 로 줄이는 입력까지 막힌다.
        let lowered = draft.setCategoryAmount(999, for: 2)
        #expect(lowered)
        #expect(draft.categorySum == 99_999_998)
    }

    @Test("S 가 T 를 넘으면 전체는 S 를 따르고 T 는 그대로 남아, S 가 다시 내려가면 T 로 돌아간다")
    func totalFollowsSumWhenSumOutgrowsTyped() {
        var draft = makeDraft(directTotal: 500_000, lines: [line(1, 300_000), line(2, 100_000)])

        #expect(draft.total == 500_000)
        #expect(draft.otherCategoriesAmount == 100_000)

        let raised = draft.setCategoryAmount(300_000, for: 2)
        #expect(raised)
        #expect(draft.total == 600_000)
        #expect(draft.directTotal == 500_000)
        #expect(draft.otherCategoriesAmount == nil)

        let lowered = draft.setCategoryAmount(100_000, for: 2)
        #expect(lowered)
        #expect(draft.total == 500_000)
        #expect(draft.otherCategoriesAmount == 100_000)
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

    @Test("칸을 비우면 빈칸으로 돌아간다 — 결제수단은 몫이 없어지고(0 이 아니다), 전체는 카테고리 합을 따른다")
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

        // T 를 지우면 전체는 S 다.
        draft.setDirectTotal(nil)
        #expect(draft.directTotal == nil)
        #expect(draft.total == 300_000)
        #expect(draft.isTotalAutomatic)

        // 카테고리가 없으면 전체도 없다.
        var noLines = makeDraft(directTotal: 500_000)
        noLines.setDirectTotal(nil)
        #expect(noLines.directTotal == nil)
        #expect(noLines.total == nil)
    }

    // MARK: 카테고리 줄

    @Test("칩으로 넣은 줄은 칩 순서를 따르고 칩 묶음에서 빠진다 — 칩 순서에 없는 줄은 뒤에 남는다")
    func addCategoryFollowsChipOrder() {
        let chipOrder = [-3, 1, 2, 5]
        var draft = makeDraft()

        draft.addCategory(5, chipOrder: chipOrder)
        draft.addCategory(1, chipOrder: chipOrder)
        draft.addCategory(-3, chipOrder: chipOrder)

        #expect(draft.categoryLines.map(\.categoryID) == [-3, 1, 5])
        #expect(draft.categoryLines.allSatisfy { $0.amount == nil && !$0.isDeleted })
        #expect(draft.chipCategoryIDs(chipOrder: chipOrder) == [2])

        // 이미 줄이 있으면 무시한다 — 적어 둔 금액도 그대로다.
        let filled = draft.setCategoryAmount(10000, for: 1)
        #expect(filled)
        draft.addCategory(1, chipOrder: chipOrder)
        #expect(draft.categoryLines.map(\.categoryID) == [-3, 1, 5])
        #expect(draft.categoryLines[1].amount == 10000)

        // 서버가 준 삭제된 카테고리 줄(칩 순서에 없음)은 새 줄들 뒤에 남는다.
        var withDeleted = makeDraft(lines: [BudgetEditCategoryLine(categoryID: 9, isDeleted: true, amount: 20000)])
        withDeleted.addCategory(5, chipOrder: chipOrder)
        withDeleted.addCategory(1, chipOrder: chipOrder)
        #expect(withDeleted.categoryLines.map(\.categoryID) == [1, 5, 9])
        #expect(withDeleted.categoryLines.last?.isDeleted == true)
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
        #expect(filled)
        #expect(draft.categoryLines.map(\.amount) == [200_000])

        let cleared = draft.setCategoryAmount(nil, for: 1)
        #expect(cleared)
        #expect(draft.categoryLines.map(\.categoryID) == [1])
        #expect(draft.categoryLines.map(\.amount) == [nil])

        let zeroed = draft.setCategoryAmount(0, for: 1)
        #expect(zeroed)
        #expect(draft.categoryLines.map(\.amount) == [0])
    }

    @Test("T 가 S 와 같으면 작은 것이 아니다 — 맞추지 않고 알리지 않는다")
    func commitDirectTotalEqualToSumKeepsValue() {
        var equal = makeDraft(lines: [line(1, 200_000), line(2, 100_000)])
        equal.setDirectTotal(300_000)
        let equalClamped = equal.commitDirectTotal()
        #expect(!equalClamped)
        #expect(equal.directTotal == 300_000)

        var below = makeDraft(lines: [line(1, 200_000), line(2, 100_000)])
        below.setDirectTotal(299_999)
        let belowClamped = below.commitDirectTotal()
        #expect(belowClamped)
        #expect(below.directTotal == 300_000)
    }

    @Test("칩 순서에 없는 줄이 여럿이면 칩으로 넣은 줄 뒤에 원래 순서 그대로 남는다")
    func addCategoryKeepsUnlistedLinesInOrder() {
        // 서버가 준 순서: 삭제된 9 다음 8.
        var draft = makeDraft(lines: [
            BudgetEditCategoryLine(categoryID: 9, isDeleted: true, amount: 20000),
            BudgetEditCategoryLine(categoryID: 8, isDeleted: true, amount: 10000)
        ])

        draft.addCategory(3, chipOrder: [1, 3, 5])

        #expect(draft.categoryLines.map(\.categoryID) == [3, 9, 8])
        #expect(draft.categoryLines.map(\.amount) == [nil, 20000, 10000])
    }
}
