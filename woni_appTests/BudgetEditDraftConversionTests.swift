//
//  BudgetEditDraftConversionTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 편집 초안 ↔ 서버 응답·저장 요청(스펙 :49-50 M1 · §2.5 V2 · :221 V10 · :225-236 불러오기).
/// 응답 픽스처는 계약 검사(`BudgetTabViewModel.isWellFormed`)를 지나는 모양만 만든다 — 운영에서 오는 응답만 연다.
@MainActor
struct BudgetEditDraftConversionTests {
    // MARK: 다시 열기

    @Test("저장된 전체가 카테고리 합과 같으면 자동, 크면 직접 입력, 카테고리 몫이 없으면 늘 직접 입력으로 연다")
    func reopeningDetectsAutomaticTotal() {
        let automatic = BudgetEditDraft(
            budget: makeBudget(total: under(400_000), categories: [
                categoryLine(1, under(300_000)),
                categoryLine(2, under(100_000))
            ]),
            baseCurrency: .krw
        )
        #expect(automatic.directTotal == nil)
        #expect(automatic.total == 400_000)
        #expect(automatic.isTotalAutomatic)

        let direct = BudgetEditDraft(
            budget: makeBudget(
                total: under(500_000),
                categories: [categoryLine(1, under(300_000)), categoryLine(2, under(100_000))],
                other: under(100_000)
            ),
            baseCurrency: .krw
        )
        #expect(direct.directTotal == 500_000)
        #expect(direct.otherCategoriesAmount == 100_000)

        // 직접 적은 0원 전체는 다시 열어도 빈칸이 아니다.
        let zero = BudgetEditDraft(budget: makeBudget(total: under(0)), baseCurrency: .krw)
        #expect(zero.directTotal == 0)
        #expect(zero.total == 0)
    }

    @Test("금액 줄은 응답 순서 그대로다(삭제된 줄 자리 포함) — 응답에 없는 카테고리는 칩에 남는다")
    func reopeningKeepsResponseOrder() {
        let draft = BudgetEditDraft(
            budget: makeBudget(total: under(600_000), categories: [
                categoryLine(5, under(100_000)),
                categoryLine(1, under(300_000)),
                categoryLine(9, under(200_000), isDeleted: true)
            ]),
            baseCurrency: .krw
        )

        #expect(draft.categoryLines.map(\.categoryID) == [5, 1, 9])
        #expect(draft.categoryLines.map(\.amount) == [100_000, 300_000, 200_000])
        #expect(draft.categoryLines.map(\.isDeleted) == [false, false, true])
        #expect(draft.chipCategoryIDs(chipOrder: [1, 3, 5, 7]) == [3, 7])
    }

    @Test("미설정 달은 기기 기준통화·빈칸·결제수단 접힘으로 열고 사용액 줄이 없다")
    func unsetMonthOpensEmptyWithBaseCurrency() {
        let draft = BudgetEditDraft(budget: makeNotSetBudget(), baseCurrency: .usd)

        #expect(draft.currency == .usd)
        #expect(draft.total == nil)
        #expect(draft.directTotal == nil)
        #expect(draft.categoryLines.isEmpty)
        #expect(draft.paymentAmounts.isEmpty)
        #expect(!draft.isPaymentExpanded)
        #expect(draft.spentTotal == nil)
        #expect(draft.spent(forPayment: .creditCard) == nil)

        // 신원 없는 비회원의 빈 초안도 같다.
        #expect(BudgetEditDraft(emptyWith: .usd) == draft)
    }

    @Test("결제수단 몫이 하나라도 있으면 펼친 채, 없으면 접힌 채 연다")
    func paymentSectionExpandsOnlyWithShares() {
        let withShare = BudgetEditDraft(
            budget: makeBudget(
                total: under(500_000),
                payments: [
                    paymentLine(.creditCard, spentOnly(0)),
                    paymentLine(.cashAndDebit, under(200_000)),
                    paymentLine(.accountAndOther, spentOnly(0))
                ],
                other: under(500_000)
            ),
            baseCurrency: .krw
        )
        #expect(withShare.isPaymentExpanded)
        #expect(withShare.paymentAmounts == [.cashAndDebit: 200_000])

        let withoutShare = BudgetEditDraft(
            budget: makeBudget(total: under(500_000), other: under(500_000)),
            baseCurrency: .krw
        )
        #expect(!withoutShare.isPaymentExpanded)
        #expect(withoutShare.paymentAmounts.isEmpty)
    }

    // MARK: 사용액 줄

    @Test("사용액은 서버 값 그대로이고, 편집 중 통화가 저장된 통화와 다르면 숨었다가 되돌리면 다시 보인다")
    func spentHidesWhenCurrencyDiffers() {
        var draft = BudgetEditDraft(
            budget: makeBudget(
                total: under(500_000, spent: 365_000),
                categories: [categoryLine(1, under(400_000, spent: 330_000))],
                payments: [
                    paymentLine(.creditCard, spentOnly(300_000)),
                    paymentLine(.cashAndDebit, spentOnly(65000)),
                    paymentLine(.accountAndOther, spentOnly(0))
                ],
                other: under(100_000, spent: 35000)
            ),
            baseCurrency: .krw
        )

        #expect(draft.spentTotal == 365_000)
        #expect(draft.spent(forCategory: 1) == 330_000)
        #expect(draft.spent(forPayment: .accountAndOther) == 0)

        draft.currency = .usd
        #expect(draft.spentTotal == nil)
        #expect(draft.spent(forCategory: 1) == nil)
        #expect(draft.spent(forPayment: .accountAndOther) == nil)

        draft.currency = .krw
        #expect(draft.spentTotal == 365_000)
        #expect(draft.spent(forCategory: 1) == 330_000)
        #expect(draft.spent(forPayment: .accountAndOther) == 0)

        // 편집 중 새로 넣은 줄은 서버가 사용액을 주지 않았다.
        draft.addCategory(7)
        #expect(draft.spent(forCategory: 7) == nil)
    }

    // MARK: 지난 달 불러오기

    @Test("지난 달을 불러오면 삭제된 몫을 빼고 그 수를 돌려주며, 전체·통화·결제수단은 지난 달 값이고 사용액은 이 달 값이다")
    func applyingPreviousDropsDeletedCategories() throws {
        let usd70 = try #require(Decimal(string: "70.00"))
        let usd50 = try #require(Decimal(string: "50.00"))
        let usd20 = try #require(Decimal(string: "20.00"))
        let usd999 = try #require(Decimal(string: "999.00"))
        var draft = BudgetEditDraft(
            budget: makeBudget(
                currency: .usd,
                total: under(100, spent: usd70),
                categories: [categoryLine(1, under(60, spent: usd50))],
                payments: [
                    paymentLine(.creditCard, spentOnly(usd70)),
                    paymentLine(.cashAndDebit, spentOnly(0)),
                    paymentLine(.accountAndOther, spentOnly(0))
                ],
                other: under(40, spent: usd20)
            ),
            baseCurrency: .krw
        )
        #expect(!draft.isPaymentExpanded)

        // 지난 달 전체 400,000 = 식비 300,000 + 삭제된 X 100,000 이라 그 외 카테고리는 몫 없이 쓴 돈만이다.
        let previous = makeBudget(
            year: 2026,
            month: 9,
            currency: .usd,
            total: under(400_000, spent: usd999),
            categories: [
                categoryLine(1, under(300_000, spent: 500)),
                categoryLine(8, under(100_000, spent: 400), isDeleted: true)
            ],
            payments: [
                paymentLine(.creditCard, under(200_000, spent: 900)),
                paymentLine(.cashAndDebit, spentOnly(99)),
                paymentLine(.accountAndOther, spentOnly(0))
            ],
            other: spentOnly(99)
        )
        let dropped = draft.applyPrevious(previous)

        #expect(dropped == 1)
        #expect(draft.currency == .usd)
        #expect(draft.directTotal == 400_000)
        #expect(draft.categoryLines.map(\.categoryID) == [1])
        #expect(draft.categoryLines.map(\.amount) == [300_000])
        #expect(draft.otherCategoriesAmount == 100_000)
        #expect(draft.paymentAmounts == [.creditCard: 200_000])
        #expect(draft.isPaymentExpanded)
        // 사용액은 편집 중인 달(이 달)의 값이다 — 지난 달의 999.00 · 500 · 900 이 아니다(스펙 V5).
        #expect(draft.spentTotal == usd70)
        #expect(draft.spent(forCategory: 1) == usd50)
        #expect(draft.spent(forPayment: .creditCard) == usd70)
    }

    // MARK: 저장 요청

    @Test("저장 요청은 빈칸을 빼고 0 은 보내며 임시 번호를 서버 번호로 바꾼다 — 전체가 없으면 만들지 않는다")
    func saveRequestSkipsEmptyAndResolvesIDs() throws {
        let draft = BudgetEditDraft(
            currency: .krw,
            directTotal: 200_000,
            categoryLines: [line(-3, 50000), line(1, 0), line(2, nil)],
            paymentAmounts: [.cashAndDebit: 100_000],
            isPaymentExpanded: true
        )
        #expect(draft.isSaveable)

        let request = try #require(draft.saveRequest { $0 == -3 ? 42 : $0 })
        #expect(request.currency == .krw)
        #expect(request.totalAmount == 200_000)
        #expect(request.categoryAmounts.map(\.categoryId) == [42, 1])
        #expect(request.categoryAmounts.map(\.amount) == [50000, 0])
        #expect(request.paymentGroupAmounts.map(\.paymentGroup) == [.cashAndDebit])
        #expect(request.paymentGroupAmounts.map(\.amount) == [100_000])

        let empty = BudgetEditDraft(currency: .krw, categoryLines: [line(1, nil)])
        #expect(empty.saveRequest { $0 } == nil)
    }

    // MARK: 바뀐 입력

    @Test("통화만 바꿔 금액이 비워진 상태는 바뀐 입력이 아니다 — 금액·줄이 바뀌면 바뀐 입력이다")
    func currencyOnlyChangeIsNotAChange() {
        let opened = BudgetEditDraft(
            budget: makeBudget(
                total: under(500_000),
                categories: [categoryLine(1, under(300_000))],
                other: under(200_000)
            ),
            baseCurrency: .krw
        )
        #expect(!opened.hasChanges(from: opened))

        var cleared = opened
        cleared.clearAmounts()
        cleared.currency = .usd
        #expect(cleared.hasChanges(from: opened))
        let baseline = cleared
        #expect(!cleared.hasChanges(from: baseline))

        var typed = cleared
        typed.setDirectTotal(100)
        #expect(typed.hasChanges(from: baseline))

        var added = cleared
        added.addCategory(2)
        #expect(added.hasChanges(from: baseline))

        var otherCurrency = opened
        otherCurrency.currency = .eur
        #expect(!otherCurrency.hasChanges(from: opened))
    }

    // MARK: 도우미

    private func line(_ id: Int, _ amount: Decimal?) -> BudgetEditCategoryLine {
        BudgetEditCategoryLine(categoryID: id, isDeleted: false, amount: amount)
    }
}

// MARK: 통화 · 결제수단

extension BudgetEditDraftConversionTests {
    @Test("저장된 달은 기기 기준통화가 아니라 그 달에 저장된 통화로 연다 — 미설정 달만 기준통화다")
    func reopeningUsesSavedCurrency() throws {
        let usd70 = try #require(Decimal(string: "70.00"))
        let saved = BudgetEditDraft(
            budget: makeBudget(
                currency: .usd,
                total: under(100, spent: usd70),
                payments: [
                    paymentLine(.creditCard, spentOnly(usd70)),
                    paymentLine(.cashAndDebit, spentOnly(0)),
                    paymentLine(.accountAndOther, spentOnly(0))
                ],
                other: under(100, spent: usd70)
            ),
            baseCurrency: .krw
        )
        #expect(saved.currency == .usd)
        #expect(saved.spentTotal == usd70)

        let unset = BudgetEditDraft(budget: makeNotSetBudget(), baseCurrency: .krw)
        #expect(unset.currency == .krw)
    }

    @Test("지난 달을 불러오면 통화가 지난 달 값이 되고, 이 달에 저장된 통화와 다르면 사용액이 숨었다가 되돌리면 다시 보인다")
    func applyingPreviousSwitchesCurrency() {
        let thisMonth = makeBudget(
            total: under(500_000, spent: 365_000),
            payments: [
                paymentLine(.creditCard, spentOnly(365_000)),
                paymentLine(.cashAndDebit, spentOnly(0)),
                paymentLine(.accountAndOther, spentOnly(0))
            ],
            other: under(500_000, spent: 365_000)
        )
        var draft = BudgetEditDraft(budget: thisMonth, baseCurrency: .krw)
        _ = draft.applyPrevious(
            makeBudget(year: 2026, month: 9, currency: .usd, total: under(400), other: under(400))
        )
        #expect(draft.currency == .usd)
        #expect(draft.spentTotal == nil)
        draft.currency = .krw
        #expect(draft.spentTotal == 365_000)

        var sameCurrency = BudgetEditDraft(budget: thisMonth, baseCurrency: .krw)
        _ = sameCurrency.applyPrevious(
            makeBudget(year: 2026, month: 9, total: under(400_000), other: under(400_000))
        )
        #expect(sameCurrency.currency == .krw)
        #expect(sameCurrency.spentTotal == 365_000)
    }

    @Test("결제수단 몫이 있어 펼친 채 연 초안은 결제수단 몫 없는 지난 달을 불러와도 펼친 채다")
    func applyingPreviousKeepsExpandedPayment() {
        var draft = BudgetEditDraft(
            budget: makeBudget(
                total: under(500_000),
                payments: [
                    paymentLine(.creditCard, spentOnly(0)),
                    paymentLine(.cashAndDebit, under(200_000)),
                    paymentLine(.accountAndOther, spentOnly(0))
                ],
                other: under(500_000)
            ),
            baseCurrency: .krw
        )
        #expect(draft.isPaymentExpanded)

        _ = draft.applyPrevious(
            makeBudget(year: 2026, month: 9, total: under(300_000), other: under(300_000))
        )
        #expect(draft.paymentAmounts.isEmpty)
        #expect(draft.isPaymentExpanded)
    }

    @Test("삭제된 몫이 없고 전체가 카테고리 합과 같은 지난 달은 자동으로 불러오고, 결제수단 몫이 없으면 접힌 채다")
    func applyingPreviousWithoutDeletedOpensAutomatic() {
        var automatic = BudgetEditDraft(
            budget: makeBudget(total: under(100), other: under(100)),
            baseCurrency: .krw
        )
        let none = automatic.applyPrevious(
            makeBudget(year: 2026, month: 9, total: under(400_000), categories: [
                categoryLine(2, under(100_000)),
                categoryLine(1, under(300_000))
            ])
        )
        #expect(none == 0)
        #expect(automatic.directTotal == nil)
        #expect(automatic.total == 400_000)
        // 지난 달 응답 순서 그대로다 — 칩 순서([1, 2])로 다시 세우지 않는다.
        #expect(automatic.categoryLines.map(\.categoryID) == [2, 1])
        // 지난 달에 결제수단 몫이 없으면 펼침은 그대로다.
        #expect(!automatic.isPaymentExpanded)
    }

    @Test("지난 달이 미설정이면 아무것도 빼지 않고 칸을 그대로 둔다")
    func applyingPreviousFromUnsetMonthKeepsDraft() {
        var draft = BudgetEditDraft(
            budget: makeBudget(
                total: under(500_000),
                categories: [categoryLine(1, under(300_000))],
                payments: [
                    paymentLine(.creditCard, under(100_000)),
                    paymentLine(.cashAndDebit, spentOnly(0)),
                    paymentLine(.accountAndOther, spentOnly(0))
                ],
                other: under(200_000)
            ),
            baseCurrency: .krw
        )
        let before = draft
        #expect(before.directTotal == 500_000)
        #expect(before.categoryLines.map(\.categoryID) == [1])
        #expect(before.paymentAmounts == [.creditCard: 100_000])

        let dropped = draft.applyPrevious(makeNotSetBudget(year: 2026, month: 9))
        #expect(dropped == 0)
        #expect(draft == before)
    }

    @Test("저장 요청의 결제수단은 적은 순서와 상관없이 신용카드 → 현금·체크카드 → 계좌·수표·기타 순이다")
    func saveRequestOrdersPaymentGroups() throws {
        var draft = BudgetEditDraft(currency: .krw, directTotal: 600_000, isPaymentExpanded: true)
        draft.setPaymentAmount(100_000, for: .accountAndOther)
        draft.setPaymentAmount(100_000, for: .cashAndDebit)
        draft.setPaymentAmount(100_000, for: .creditCard)

        let request = try #require(draft.saveRequest { $0 })
        #expect(request.paymentGroupAmounts.map(\.paymentGroup) == [.creditCard, .cashAndDebit, .accountAndOther])
    }
}

// MARK: 응답 픽스처

/// 넘지 않은 줄. 상태·퍼센트·남은 돈은 서버 규칙 그대로다(계약 2026-09-29 :110·:116-124 · 백엔드 `BudgetLine.of`):
/// 쓴 돈 0 → NONE · 80% 미만 → IN_PROGRESS · 80% 이상 → NEAR_LIMIT · 같으면 REACHED. 퍼센트는 내림, 0원 예산이면 nil.
private func under(_ budget: Decimal, spent: Decimal = 0) -> BudgetLine {
    #expect(spent <= budget, "넘은 줄은 under 로 만들지 않는다")
    return BudgetLine(
        budgetAmount: budget,
        actualAmount: spent,
        status: underStatus(budget, spent: spent),
        percent: budget == 0 ? nil : floorPercent(spent * 100 / budget),
        remainingAmount: budget - spent,
        overAmount: nil
    )
}

private func underStatus(_ budget: Decimal, spent: Decimal) -> BudgetStatus {
    if spent == 0 {
        return .none
    }
    if spent == budget {
        return .reached
    }
    return spent * 100 >= budget * 80 ? .nearLimit : .inProgress
}

private func floorPercent(_ value: Decimal) -> Int {
    var value = value
    var floored = Decimal()
    NSDecimalRound(&floored, &value, 0, .down)
    return NSDecimalNumber(decimal: floored).intValue
}

/// 몫이 없는 줄 — 계약상 사용액만 있고 상태·퍼센트·남은 돈·넘은 돈은 nil 이다.
/// 결제수단·그 외 카테고리에만 쓴다 — 카테고리 줄은 몫이 있는 것만 온다(계약 v2 :52).
private func spentOnly(_ spent: Decimal) -> BudgetLine {
    BudgetLine(budgetAmount: nil, actualAmount: spent, status: nil, percent: nil, remainingAmount: nil, overAmount: nil)
}

private func categoryLine(_ id: Int, _ line: BudgetLine, isDeleted: Bool = false) -> BudgetCategoryLine {
    BudgetCategoryLine(
        category: Category(id: id, code: "FOOD", displayNameKo: "식비", displayNameEn: "Food", icon: "🍽️", sortOrder: id),
        isDeleted: isDeleted,
        line: line
    )
}

private func paymentLine(_ group: PaymentGroup, _ line: BudgetLine) -> BudgetPaymentGroupLine {
    BudgetPaymentGroupLine(paymentGroup: group, line: line)
}

/// 예산이 있는 달. 응답의 이번 달은 2026-10 이고 남은 일수는 요청한 달이 이번 달일 때만 7 이다.
/// 결제수단은 따로 적지 않으면 세 묶음 모두 몫 없이 사용액 0 이다.
/// 합계는 서버 규칙 그대로다(백엔드 `BudgetEvaluation.evaluate` · 계약 v2 :87-89): 결제수단 쓴 돈 합 = 전체 쓴 돈,
/// 카테고리 쓴 돈 합 + 그 외 쓴 돈 = 전체 쓴 돈, 그 외 몫 = 전체 몫 − 카테고리 몫 합(삭제된 몫 포함) — 0 이면 쓴 돈만.
@MainActor
private func makeBudget(
    year: Int = 2026,
    month: Int = 10,
    currency: CurrencyCode = .krw,
    total: BudgetLine,
    categories: [BudgetCategoryLine] = [],
    payments: [BudgetPaymentGroupLine] = [
        paymentLine(.creditCard, spentOnly(0)),
        paymentLine(.cashAndDebit, spentOnly(0)),
        paymentLine(.accountAndOther, spentOnly(0))
    ],
    other: BudgetLine = spentOnly(0)
) -> MonthlyBudget {
    let budget = MonthlyBudget(
        year: year,
        month: month,
        currentYear: 2026,
        currentMonth: 10,
        remainingDaysIncludingToday: year == 2026 && month == 10 ? 7 : nil,
        hasAnyBudget: true,
        status: total.status ?? .notSet,
        currency: currency,
        total: total,
        paymentGroups: payments,
        categories: categories,
        otherCategories: other,
        missingRateCount: 0,
        dailyAllowance: nil,
        deletedCategoriesWithSpending: []
    )
    #expect(BudgetTabViewModel.isWellFormed(budget))
    let spent = total.actualAmount
    let categorySpent = categories.map(\.line.actualAmount).reduce(0, +)
    let otherShare = (total.budgetAmount ?? 0) - categories.compactMap(\.line.budgetAmount).reduce(0, +)
    #expect(payments.map(\.line.actualAmount).reduce(0, +) == spent, "결제수단 쓴 돈 합 = 전체 쓴 돈")
    #expect(categorySpent + other.actualAmount == spent, "카테고리 + 그 외 쓴 돈 = 전체 쓴 돈")
    #expect(other.budgetAmount == (otherShare > 0 ? otherShare : nil), "그 외 몫 = 전체 몫 − 카테고리 몫 합")
    return budget
}

/// 미설정 달 — 계약상 통화·전체·그 외 카테고리·하루 권장이 nil 이고 결제수단·카테고리는 [] 이다.
@MainActor
private func makeNotSetBudget(year: Int = 2026, month: Int = 10) -> MonthlyBudget {
    let budget = MonthlyBudget(
        year: year,
        month: month,
        currentYear: 2026,
        currentMonth: 10,
        remainingDaysIncludingToday: year == 2026 && month == 10 ? 7 : nil,
        hasAnyBudget: false,
        status: .notSet,
        currency: nil,
        total: nil,
        paymentGroups: [],
        categories: [],
        otherCategories: nil,
        missingRateCount: 0,
        dailyAllowance: nil,
        deletedCategoriesWithSpending: []
    )
    #expect(BudgetTabViewModel.isWellFormed(budget))
    return budget
}
