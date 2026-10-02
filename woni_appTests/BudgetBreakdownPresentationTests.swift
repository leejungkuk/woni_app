//
//  BudgetBreakdownPresentationTests.swift
//  woni_appTests
//

import Foundation
import SwiftUI
import Testing
@testable import woni_app

/// 예산 탭 카테고리·결제수단 카드의 표시 규칙. 금액·상태·넘은 돈은 서버 값 그대로이고
/// 줄 순서·색 순위·막대 비율만 기기에서 정한다. 따로 적지 않으면 응답 통화는 KRW 다.
@MainActor
struct BudgetBreakdownPresentationTests {
    // MARK: 카테고리 카드

    @Test("카테고리 줄은 쓴 돈 많은 순이고 같으면 카테고리 번호가 작은 쪽이 앞이며, 색 순위도 그 순서다")
    func categoriesSortBySpendThenID() throws {
        // 서버 배열 순서(1·7·3)도, 번호 순서(1·3·7)도, 같은 금액의 서버 순서(7·3)도 답이 아니다.
        let content = makeContent(categories: [
            categoryLine(id: 1, line: under(1000, spent: 300)),
            categoryLine(id: 7, line: under(1000, spent: 500)),
            categoryLine(id: 3, line: under(1000, spent: 500))
        ])
        let rows = try #require(present(content).categoryCard).rows

        #expect(rows.map(\.categoryID) == [3, 7, 1])
        #expect(rows.map(\.colorRank) == [0, 1, 2])
    }

    @Test("예산 막대 색은 지출 순서 색의 70 단계이고 10색마다 처음으로 돌아간다 — 100 단계가 아니다")
    func budgetBarPaletteIsSeventyStepCycle() throws {
        let middle: [UInt] = [0x82B3AD, 0xC8A069, 0x9AA8C5, 0xDA9195, 0x84AFC4, 0x79B79B, 0xC49F8A, 0xAEAB72]

        #expect(WoniColor.budgetCategoryBarColor(rank: 0) == WoniColor.terracotta70)
        for (offset, hex) in middle.enumerated() {
            #expect(WoniColor.budgetCategoryBarColor(rank: offset + 1) == Color(hex: hex))
        }
        #expect(WoniColor.budgetCategoryBarColor(rank: 9) == WoniColor.olive70)
        #expect(WoniColor.budgetCategoryBarColor(rank: 10) == WoniColor.terracotta70)
        #expect(WoniColor.budgetCategoryBarColor(rank: 11) == Color(hex: 0x82B3AD))
        #expect(WoniColor.budgetCategoryBarColor(rank: 0) != WoniColor.terracotta100)

        // 카드의 줄도 이 색으로 칠한다 — 통계 도넛의 100 단계 색을 가져오지 않는다.
        let content = makeContent(categories: [
            categoryLine(id: 1, line: under(1000, spent: 500)),
            categoryLine(id: 2, line: under(1000, spent: 300))
        ])
        let rows = try #require(present(content).categoryCard).rows
        #expect(rows[0].row.barColor == WoniColor.terracotta70)
        #expect(rows[1].row.barColor == Color(hex: 0x82B3AD))
        #expect(rows[0].row.barColor != WoniColor.categoryColor(rank: 0, type: .expense))
    }

    @Test("몫을 정한 카테고리가 없는 달은 카테고리 카드가 없고 결제수단 카드는 3줄 그대로다")
    func noAllocatedCategoryHidesCategoryCard() throws {
        let totalOnly = try present(makeContent(categories: [], other: under(500_000, spent: 120_000)))

        #expect(totalOnly.categoryCard == nil)
        #expect(totalOnly.paymentRows.map(\.paymentGroup) == [.creditCard, .cashAndDebit, .accountAndOther])

        // 몫을 정한 카테고리가 하나라도 있으면 카드가 있다.
        let oneCategory = try present(makeContent(categories: [categoryLine(id: 1, line: under(1000, spent: 0))]))
        #expect(oneCategory.categoryCard?.rows.count == 1)
    }

    @Test("넘은 줄은 막대 아래에 통화 글자 없이 넘은 돈을 서버 값 그대로 보이고, 넘지 않은 줄은 문구가 없다")
    func overRowShowsOverTextWithoutCurrency() throws {
        let content = makeContent(categories: [
            categoryLine(id: 1, line: over(300_000, spent: 334_726, by: 34726)),
            categoryLine(id: 2, line: under(100_000, spent: 20000))
        ])
        let ko = try #require(present(content).categoryCard).rows
        let en = try #require(present(content, .en).categoryCard).rows

        #expect(ko[0].row.overText == "34,726 넘었습니다")
        #expect(en[0].row.overText == "34,726 over")
        #expect(ko[0].row.overText?.contains("KRW") == false)
        #expect(ko[0].row.bar?.isOver == true)
        #expect(ko[1].row.overText == nil)
        #expect(ko[1].row.bar?.isOver == false)

        // 넘었는데 넘은 돈이 없으면 계약이 깨진 응답이다 — 넘친 구간·문구를 지어내지 않고 카드를 만들지 않는다.
        let broken = makeContent(categories: [
            categoryLine(id: 1, line: BudgetLine(
                budgetAmount: 1000,
                actualAmount: 1200,
                status: .exceeded,
                percent: nil,
                remainingAmount: nil,
                overAmount: nil
            ))
        ])
        #expect(BudgetBreakdownPresentation(content: broken, language: .ko) == nil)
    }

    @Test("그 외 카테고리 줄: 남는 몫이 있으면 쓴 돈/남는 몫과 gray40 막대, 넘으면 넘침 표시, 없으면 쓴 돈만")
    func otherCategoriesRowVariants() throws {
        let food = categoryLine(id: 1, line: under(300_000, spent: 180_000))
        let withShare = try present(makeContent(categories: [food], other: under(100_000, spent: 15000)))
        let overShare = try present(makeContent(categories: [food], other: over(100_000, spent: 112_000, by: 12000)))
        let noShare = try present(makeContent(categories: [food], other: spentOnly(68000)))

        for presentation in [withShare, overShare, noShare] {
            let other = try #require(presentation.categoryCard).otherCategories
            #expect(other.name == "그 외 카테고리")
            #expect(other.tag == nil)
        }
        let enOther = try #require(present(makeContent(categories: [food]), .en).categoryCard).otherCategories
        #expect(enOther.name == "Other categories")

        let shared = try #require(withShare.categoryCard).otherCategories
        #expect(shared.amountText == "15,000 / 100,000")
        #expect(shared.barColor == WoniColor.gray40)
        #expect(shared.bar?.isOver == false)
        try #expect(isClose(#require(shared.bar).ratio, 0.15))
        #expect(shared.overText == nil)

        let overflown = try #require(overShare.categoryCard).otherCategories
        #expect(overflown.amountText == "112,000 / 100,000")
        #expect(overflown.barColor == WoniColor.gray40)
        #expect(overflown.bar?.isOver == true)
        #expect(overflown.overText == "12,000 넘었습니다")

        let spent = try #require(noShare.categoryCard).otherCategories
        #expect(spent.amountText == "68,000")
        #expect(spent.amountColor == WoniColor.gray60)
        #expect(spent.bar == nil)
        #expect(spent.overText == nil)
    }

    @Test("카테고리 이름: 보통·삭제 대기는 아이콘 + 이름, 서버가 삭제로 표시한 줄은 아이콘 없이 '삭제된 카테고리'가 앞선다")
    func deletedAndPendingCategoryNames() throws {
        let content = makeContent(
            categories: [
                categoryLine(id: 1, line: under(1000, spent: 500)),
                categoryLine(id: 2, line: under(1000, spent: 400)),
                categoryLine(id: 3, isDeleted: true, line: under(1000, spent: 300)),
                categoryLine(id: 4, isDeleted: true, line: under(1000, spent: 200)),
                categoryLine(id: 5, icon: nil, line: under(1000, spent: 100))
            ],
            pendingDeletionIDs: [2, 4]
        )
        let ko = try rowsByID(present(content))
        let en = try rowsByID(present(content, .en))

        #expect(ko[1]?.name == "🍽️ 식비")
        #expect(en[1]?.name == "🍽️ Food")
        #expect(ko[1]?.tag == nil)

        #expect(ko[2]?.name == "🍽️ 식비")
        #expect(ko[2]?.tag == "삭제 대기")
        #expect(en[2]?.tag == "Pending deletion")

        #expect(ko[3]?.name == "삭제된 카테고리")
        #expect(en[3]?.name == "Deleted category")
        #expect(ko[3]?.tag == nil)

        #expect(ko[4]?.name == "삭제된 카테고리")
        #expect(ko[4]?.tag == nil)

        // 아이콘이 없으면 이름만 — 앞에 공백을 두지 않는다.
        #expect(ko[5]?.name == "식비")
        #expect(en[5]?.name == "Food")
    }

    // MARK: 결제수단 카드

    @Test("결제수단은 서버 순서와 상관없이 카드·현금·계좌 순 3줄이고 몫 없는 묶음은 막대 없이 사용액만이다")
    func paymentRowsAlwaysThreeInFixedOrder() throws {
        let content = makeContent(payments: [
            paymentLine(.accountAndOther, spentOnly(0)),
            paymentLine(.creditCard, under(300_000, spent: 250_000)),
            paymentLine(.cashAndDebit, under(150_000, spent: 115_000))
        ])
        let rows = try present(content).paymentRows

        #expect(rows.map(\.paymentGroup) == [.creditCard, .cashAndDebit, .accountAndOther])
        #expect(rows[0].row.bar != nil)
        #expect(rows[0].row.barColor == Color(hex: 0x9AA8C5))
        #expect(rows[0].row.amountColor == WoniColor.gray80)
        #expect(rows[1].row.bar != nil)
        #expect(rows[1].row.barColor == Color(hex: 0x9AA8C5))
        #expect(rows[2].row.bar == nil)
        #expect(rows[2].row.amountText == "0")
        #expect(rows[2].row.amountColor == WoniColor.gray60)

        // 묶음이 빠진 응답은 계약 위반이다 — 빈 줄로 메우지 않고 카드를 만들지 않는다.
        let missing = makeContent(payments: [
            paymentLine(.creditCard, spentOnly(0)),
            paymentLine(.cashAndDebit, spentOnly(0))
        ])
        #expect(BudgetBreakdownPresentation(content: missing, language: .ko) == nil)
    }

    @Test("결제수단 이름은 언어별 고정 문구이고 아이콘이 없다")
    func paymentRowNamesPerLanguage() throws {
        let content = makeContent()
        let ko = try present(content).paymentRows
        let en = try present(content, .en).paymentRows
        // 묶음 순서와 이름을 같은 자리에서 맞춘다 — 이름이 다른 묶음에 붙으면 빨갛다.
        #expect(ko.map(\.paymentGroup) == [.creditCard, .cashAndDebit, .accountAndOther])
        #expect(ko.map(\.row.name) == ["신용카드", "현금·체크카드", "계좌·수표·기타"])
        #expect(en.map(\.row.name) == ["Credit Card", "Cash · Debit Card", "Account · Check · Other"])
        #expect(ko.allSatisfy { $0.row.tag == nil })
    }

    // MARK: 막대·금액·제목

    @Test("하위 막대의 넘친 구간은 카테고리·결제수단 모두 두께(8)보다 좁아지지 않는다")
    func subBarOverflowKeepsMinimumWidthEight() throws {
        // 예산 1,000·넘은 돈 1 → 눈금 0.999. 폭 300 이면 넘친 구간이 0.3 이라 두께 8 로 넓힌다.
        let tiny = over(1000, spent: 1001, by: 1)
        let half = over(1000, spent: 2000, by: 1000)
        let content = makeContent(
            categories: [categoryLine(id: 1, line: tiny), categoryLine(id: 2, line: half)],
            payments: [
                paymentLine(.creditCard, tiny),
                paymentLine(.cashAndDebit, half),
                paymentLine(.accountAndOther, spentOnly(0))
            ]
        )
        let presentation = try present(content)
        let thickness = BudgetBreakdownPresentation.barThickness
        let categoryRows = try #require(presentation.categoryCard).rows

        #expect(thickness == 8)
        #expect(categoryRows[0].row.bar?.tickX(width: 300, thickness: thickness) == 150)
        #expect(categoryRows[1].row.bar?.tickX(width: 300, thickness: thickness) == 292)
        #expect(presentation.paymentRows[0].row.bar?.tickX(width: 300, thickness: thickness) == 292)
        #expect(presentation.paymentRows[1].row.bar?.tickX(width: 300, thickness: thickness) == 150)
    }

    @Test("카드 제목은 언어별 고정 문구다")
    func cardTitlesPerLanguage() throws {
        let ko = try present(makeContent())
        let en = try present(makeContent(), .en)

        #expect(ko.categoryTitle == "카테고리")
        #expect(ko.paymentTitle == "결제수단")
        #expect(en.categoryTitle == "Categories")
        #expect(en.paymentTitle == "Payment Methods")
    }

    @Test("몫이 있는 줄은 '사용 / 예산', 몫 없는 결제수단은 사용액만이고 통화 글자 없이 예산 통화 자릿수를 따른다")
    func rowAmountsShowActualOverBudget() throws {
        let content = makeContent(
            categories: [categoryLine(id: 1, line: under(50000, spent: 34000))],
            payments: [
                paymentLine(.creditCard, under(300_000, spent: 250_000)),
                paymentLine(.cashAndDebit, spentOnly(12000)),
                paymentLine(.accountAndOther, spentOnly(0))
            ]
        )
        let presentation = try present(content)

        #expect(try #require(presentation.categoryCard).rows[0].row.amountText == "34,000 / 50,000")
        #expect(presentation.paymentRows[0].row.amountText == "250,000 / 300,000")
        #expect(presentation.paymentRows[1].row.amountText == "12,000")

        let usd = try present(makeContent(
            currency: .usd,
            categories: [categoryLine(id: 1, line: under(2000, spent: Decimal(12345) / 10))]
        ))
        #expect(try #require(usd.categoryCard).rows[0].row.amountText == "1,234.50 / 2,000.00")
    }
}

@MainActor
private func present(
    _ content: BudgetTabContent,
    _ language: AppLanguage = .ko
) throws -> BudgetBreakdownPresentation {
    try #require(BudgetBreakdownPresentation(content: content, language: language))
}

@MainActor
private func rowsByID(_ presentation: BudgetBreakdownPresentation) throws -> [Int: BudgetBreakdownPresentation.Row] {
    let rows = try #require(presentation.categoryCard).rows
    return Dictionary(uniqueKeysWithValues: rows.map { ($0.categoryID, $0.row) })
}

private func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 1e-9
}

/// 넘지 않은 줄. 상태·퍼센트·남은 돈은 서버 표시값 모양만 맞춘다(이 카드는 그대로 옮기기만 한다).
private func under(_ budget: Decimal, spent: Decimal) -> BudgetLine {
    BudgetLine(
        budgetAmount: budget,
        actualAmount: spent,
        status: spent == 0 ? BudgetStatus.none : .inProgress,
        percent: spent == 0 ? nil : 1,
        remainingAmount: budget - spent,
        overAmount: nil
    )
}

/// 넘은 줄. 계약상 퍼센트·남은 돈은 null 이고 넘은 돈은 서버 표시값(올림)이다.
private func over(_ budget: Decimal, spent: Decimal, by overAmount: Decimal) -> BudgetLine {
    BudgetLine(
        budgetAmount: budget,
        actualAmount: spent,
        status: .exceeded,
        percent: nil,
        remainingAmount: nil,
        overAmount: overAmount
    )
}

/// 몫이 없는 줄 — 사용액만 있다.
private func spentOnly(_ spent: Decimal) -> BudgetLine {
    BudgetLine(budgetAmount: nil, actualAmount: spent, status: nil, percent: nil, remainingAmount: nil, overAmount: nil)
}

/// 아이콘 🍽️·이름 식비/Food 인 카테고리 줄. 번호만 다르게 준다.
private func categoryLine(
    id: Int,
    icon: String? = "🍽️",
    isDeleted: Bool = false,
    line: BudgetLine
) -> BudgetCategoryLine {
    BudgetCategoryLine(
        category: Category(id: id, code: "FOOD", displayNameKo: "식비", displayNameEn: "Food", icon: icon, sortOrder: id),
        isDeleted: isDeleted,
        line: line
    )
}

private func paymentLine(_ group: PaymentGroup, _ line: BudgetLine) -> BudgetPaymentGroupLine {
    BudgetPaymentGroupLine(paymentGroup: group, line: line)
}

/// 예산이 있는 달. 따로 적지 않으면 전체 1,000,000 에 300,000 을 쓴 진행 중이고,
/// 결제수단 세 묶음은 몫 없이 사용액 0, 그 외 카테고리는 쓴 돈 0 만이다.
@MainActor
private func makeContent(
    currency: CurrencyCode = .krw,
    categories: [BudgetCategoryLine] = [],
    other: BudgetLine = spentOnly(0),
    payments: [BudgetPaymentGroupLine] = [
        paymentLine(.creditCard, spentOnly(0)),
        paymentLine(.cashAndDebit, spentOnly(0)),
        paymentLine(.accountAndOther, spentOnly(0))
    ],
    pendingDeletionIDs: Set<Int> = []
) -> BudgetTabContent {
    BudgetTabContent(
        budget: MonthlyBudget(
            year: 2026,
            month: 10,
            currentYear: 2026,
            currentMonth: 10,
            remainingDaysIncludingToday: 7,
            hasAnyBudget: true,
            status: .inProgress,
            currency: currency,
            total: under(1_000_000, spent: 300_000),
            paymentGroups: payments,
            categories: categories,
            otherCategories: other,
            missingRateCount: 0,
            dailyAllowance: DailyAllowance(amount: 100_000, isExceeded: false)
        ),
        unsyncedExpenseCount: 0,
        pendingDeletionCategoryIDs: pendingDeletionIDs
    )
}
