//
//  BudgetTotalPresentationTests.swift
//  woni_appTests
//

import Foundation
import SwiftUI
import Testing
@testable import woni_app

/// 예산 탭 총액 카드의 표시 규칙. 표시값은 서버 값 그대로이고 막대 비율·표시선 위치만 기기에서 센다.
/// 따로 적지 않으면 응답은 2026-10(31일)이고 서버의 이번 달도 2026-10, 오늘 포함 남은 일수는 7 이다.
@MainActor
struct BudgetTotalPresentationTests {
    // MARK: 주인공 숫자

    @Test("넘지 않았으면 남은 돈을 서버 값 그대로 gray100 으로 보이고, 통화 코드는 응답 통화다")
    func heroShowsRemainingWhenUnder() throws {
        let content = makeContent(total: under(2_500_000, spent: 2_344_400, .nearLimit, percent: 93, left: 155_600))
        let ko = try present(content)
        let en = try present(content, .en)

        #expect(ko.heroLabel == "남은 돈")
        #expect(en.heroLabel == "Remaining")
        #expect(ko.heroAmount == 155_600)
        #expect(ko.heroText == "155,600")
        #expect(ko.heroColor == WoniColor.gray100)
        #expect(ko.currencyCode == "KRW")

        // 서버는 scale 10 으로 판정하고 표시값만 내림한다 — 예산 1,000·실제 999.7 이면 임박인데 남은 돈 0.
        // 기기에서 예산 − 사용(1,000 − 999)으로 다시 세면 1 이 된다.
        let nearZero = try present(total: under(1000, spent: 999, .nearLimit, percent: 99, left: 0))
        #expect(nearZero.heroAmount == 0)
        #expect(nearZero.heroText == "0")

        let usd = try present(currency: .usd, total: usdUnder)
        #expect(usd.heroAmount == Decimal(7655) / 10)
        #expect(usd.heroText == "765.50")
        #expect(usd.currencyCode == "USD")
    }

    @Test("넘었으면 넘은 돈을 서버 값 그대로 부호 없이 terracotta100 으로 보인다")
    func heroShowsOverWithoutSignWhenExceeded() throws {
        let content = makeContent(total: over(2_500_000, spent: 2_620_000, by: 120_000))
        let ko = try present(content)
        let en = try present(content, .en)

        #expect(ko.heroLabel == "넘은 돈")
        #expect(en.heroLabel == "Over by")
        #expect(ko.heroAmount == 120_000)
        #expect(ko.heroText == "120,000")
        #expect(ko.heroColor == WoniColor.terracotta100)
        #expect(ko.currencyCode == "KRW")

        // 넘은 돈은 올림이다 — 1.00 예산에 1.004 를 쓰면 사용 1.00·넘은 돈 0.01. 기기에서 사용 − 예산으로 세면 0.00.
        let usd = try present(currency: .usd, total: usdOverByCent)
        #expect(usd.heroAmount == Decimal(1) / 100)
        #expect(usd.heroText == "0.01")
        #expect(usd.currencyCode == "USD")
    }

    @Test("계약상 있어야 할 남은 돈·넘은 돈·전체 예산이 없거나 미설정 달이면 카드를 만들지 않는다")
    func brokenTotalLineYieldsNoPresentation() {
        let noRemaining = makeLine(budget: 1000, actual: 250, status: .inProgress, percent: 25)
        let noOver = makeLine(budget: 1000, actual: 1200, status: .exceeded)
        let noBudget = BudgetLine(
            budgetAmount: nil, actualAmount: 250, status: nil, percent: nil, remainingAmount: nil, overAmount: nil
        )

        for line in [noRemaining, noOver, noBudget] {
            #expect(BudgetTotalPresentation(content: makeContent(total: line), language: .ko) == nil)
        }
        #expect(BudgetTotalPresentation(content: makeNotSetContent(), language: .ko) == nil)
    }

    // MARK: 사용/예산 줄·상태 문구

    @Test("사용/예산 줄은 사용 다음 예산이고 통화 글자 없이 예산 통화 자릿수를 따른다")
    func usedOverBudgetLineUsesActualThenBudget() throws {
        let krw = try present(total: under(2_500_000, spent: 2_270_000, .nearLimit, percent: 90, left: 230_000))
        let usd = try present(currency: .usd, total: usdUnder)

        #expect(krw.usedOverBudgetText == "2,270,000 / 2,500,000")
        #expect(usd.usedOverBudgetText == "1,234.50 / 2,000.00")
    }

    @Test("상태 문구는 서버 상태를 따르고 퍼센트는 서버 값 그대로다")
    func statusTextFollowsServerStatus() throws {
        let cases = [
            StatusCase(
                line: under(1000, spent: 0, .none, left: 1000),
                korean: "아직 쓰지 않았습니다",
                english: "Nothing spent yet",
                color: WoniColor.gray80
            ),
            // 73.78% — 서버는 내림해 73 을 준다. 기기에서 반올림하면 74.
            StatusCase(
                line: under(1_000_000, spent: 737_800, .inProgress, percent: 73, left: 262_200),
                korean: "73% 썼습니다",
                english: "73% used",
                color: WoniColor.terracotta100
            ),
            StatusCase(
                line: under(2_500_000, spent: 2_344_400, .nearLimit, percent: 93, left: 155_600),
                korean: "93% 썼습니다",
                english: "93% used",
                color: WoniColor.terracotta100
            ),
            StatusCase(
                line: under(1000, spent: 1000, .reached, percent: 100, left: 0),
                korean: "예산을 다 썼습니다",
                english: "Budget used up",
                color: WoniColor.terracotta100
            ),
            StatusCase(
                line: over(1000, spent: 1200, by: 200),
                korean: "예산을 넘었습니다",
                english: "Over budget",
                color: WoniColor.terracotta100
            )
        ]
        for statusCase in cases {
            let ko = try present(total: statusCase.line)
            let en = try present(makeContent(total: statusCase.line), .en)
            #expect(ko.statusText == statusCase.korean)
            #expect(en.statusText == statusCase.english)
            #expect(ko.statusColor == statusCase.color)
        }
    }

    // MARK: 막대

    @Test("넘지 않았으면 채움 = 사용 ÷ 예산이고 넘침 눈금이 없다")
    func barFillsByRatioWhenUnder() throws {
        let quarter = try present(total: under(1000, spent: 250, .inProgress, percent: 25, left: 750))
        let full = try present(total: under(1000, spent: 1000, .reached, percent: 100, left: 0))
        let nothing = try present(total: under(1000, spent: 0, .none, left: 1000))

        #expect(!quarter.bar.isOver)
        #expect(isClose(quarter.bar.ratio, 0.25))
        #expect(quarter.bar.tickX(width: 300, thickness: BudgetTotalPresentation.barThickness) == nil)
        #expect(!full.bar.isOver)
        #expect(isClose(full.bar.ratio, 1))
        #expect(isClose(nothing.bar.ratio, 0))
        #expect(BudgetTotalPresentation.barThickness == 14)
    }

    @Test("넘었으면 예산 눈금 = 예산 ÷ (예산 + 넘은 돈)이다 — 표시 사용액으로 세지 않는다")
    func barSplitsAtBudgetTickWhenOver() throws {
        // 1.00 예산에 1.004 를 쓰면 사용은 내림해 1.00 이다. 예산 ÷ 사용이면 1 이라 넘친 구간이 사라진다.
        let usd = try present(currency: .usd, total: usdOverByCent)
        let krw = try present(total: over(2_000_000, spent: 2_500_000, by: 500_000))

        #expect(usd.bar.isOver)
        #expect(isClose(usd.bar.ratio, 1 / 1.01))
        #expect(krw.bar.isOver)
        #expect(isClose(krw.bar.ratio, 0.8))
        #expect(krw.bar.tickX(width: 300, thickness: BudgetTotalPresentation.barThickness) == 240)
    }

    @Test("0원 예산이 넘으면 눈금이 왼쪽 끝이라 막대 전체가 넘친 구간이다")
    func zeroBudgetOverIsAllOverflow() throws {
        let presentation = try present(total: over(0, spent: 12000, by: 12000))

        #expect(presentation.bar.isOver)
        #expect(presentation.bar.ratio == 0)
        #expect(presentation.bar.tickX(width: 300, thickness: BudgetTotalPresentation.barThickness) == 0)
        #expect(presentation.heroAmount == 12000)
        #expect(presentation.statusText == "예산을 넘었습니다")
    }

    @Test("0원 예산에 쓴 돈도 0 이면 채움 없는 빈 막대다")
    func zeroBudgetNoSpendIsEmpty() throws {
        let presentation = try present(total: under(0, spent: 0, .none, left: 0))

        #expect(!presentation.bar.isOver)
        #expect(presentation.bar.ratio == 0)
        #expect(presentation.bar.tickX(width: 300, thickness: BudgetTotalPresentation.barThickness) == nil)
        #expect(presentation.statusText == "아직 쓰지 않았습니다")
    }

    @Test("넘친 구간은 막대 두께(14)보다 좁아지지 않는다")
    func overflowKeepsMinimumWidth() throws {
        // 예산 1,000·넘은 돈 1 → 눈금 0.999. 폭 300 이면 넘친 구간이 0.3 이라 두께 14 로 넓힌다.
        let tiny = try present(total: over(1000, spent: 1001, by: 1))
        let thickness = BudgetTotalPresentation.barThickness

        #expect(isClose(tiny.bar.ratio, 1000.0 / 1001.0))
        #expect(tiny.bar.tickX(width: 300, thickness: thickness) == 286)
        // 넘친 구간이 두께보다 넓으면 눈금은 비율 그대로다.
        let half = try present(total: over(1000, spent: 2000, by: 1000))
        #expect(half.bar.tickX(width: 300, thickness: thickness) == 150)
    }

    // MARK: 오늘 표시선

    @Test("표시선 = (그 달 일수 − 서버 남은 일수 + 1) ÷ 그 달 일수이고, 그 달 일수는 응답의 달로 센다")
    func todayMarkerUsesServerRemainingDays() throws {
        let october = try present(makeContent())
        let february = try present(makeContent(month: 2, current: ServerMonth(year: 2026, month: 2), remainingDays: 28))

        try #expect(isClose(#require(october.todayRatio), 25.0 / 31.0))
        try #expect(isClose(#require(october.todayMarkerX(barWidth: 310)), 250))
        #expect(october.showsInfo)
        try #expect(isClose(#require(february.todayRatio), 1.0 / 28.0))

        let koInfo = "▼는 이번 달 중 오늘의 자리입니다. 막대가 ▼를 넘었다면 예산을 고르게 나눠 쓸 때보다 많이 쓴 것입니다."
        let enInfo = "▼ marks today in this month. If the bar has passed ▼, you're spending faster than an even pace."
        #expect(october.infoText == koInfo)
        #expect(try present(makeContent(), .en).infoText == enInfo)
    }

    @Test("넘친 막대의 표시선은 막대 전체 폭이 아니라 예산 눈금 위치 × 날짜 비율이다")
    func todayMarkerScalesWithTickWhenOver() throws {
        let presentation = try present(total: over(2_000_000, spent: 2_500_000, by: 500_000))

        // 눈금 310 × 0.8 = 248, 표시선 248 × 25/31 = 200. 막대 전체 폭으로 세면 250.
        try #expect(isClose(#require(presentation.todayMarkerX(barWidth: 310)), 200))
        #expect(presentation.showsInfo)
    }

    @Test("이번 달이 아니거나 남은 일수가 없거나 0원 예산·전체 예산 없음이면 표시선과 (i) 가 없다")
    func todayMarkerHiddenOutsideCurrentMonthOrZeroBudget() throws {
        let lastMonth = try present(makeContent(month: 9, remainingDays: nil))
        // 남은 일수가 있어도 응답의 달이 이번 달이 아니면 이번 달로 보지 않는다 — 남은 일수만으로 판정하지 않는다.
        let lastMonthWithDays = try present(makeContent(month: 9, remainingDays: 7))
        let otherYear = try present(makeContent(year: 2025))
        // 응답의 달이 이번 달이어도 서버가 남은 일수를 주지 않으면 이번 달로 보지 않는다.
        let noRemainingDays = try present(makeContent(remainingDays: nil))
        let zeroOver = try present(total: over(0, spent: 12000, by: 12000))
        let zeroNone = try present(total: under(0, spent: 0, .none, left: 0))

        for presentation in [lastMonth, lastMonthWithDays, otherYear, noRemainingDays, zeroOver, zeroNone] {
            #expect(presentation.todayRatio == nil)
            #expect(presentation.todayMarkerX(barWidth: 310) == nil)
            #expect(!presentation.showsInfo)
        }
        // 전체 예산이 없는 달(미설정)은 이번 달이고 남은 일수가 있어도 카드 자체가 없다.
        #expect(BudgetTotalPresentation(content: makeNotSetContent(), language: .ko) == nil)
    }

    // MARK: 하루 권장·빠진 거래

    @Test("하루 권장 줄은 이번 달에만 있고, 남은 돈이 있으면 하루 금액·0 이거나 넘었으면 쓸 돈 없음이다")
    func dailyLineVariants() throws {
        let allowance = makeContent(dailyAllowance: DailyAllowance(amount: 93657, isExceeded: false))
        let zero = makeContent(
            total: under(1000, spent: 1000, .reached, percent: 100, left: 0),
            dailyAllowance: DailyAllowance(amount: 0, isExceeded: false)
        )
        let exceeded = makeContent(
            total: over(1000, spent: 1200, by: 200),
            dailyAllowance: DailyAllowance(amount: nil, isExceeded: true)
        )
        let lastDay = makeContent(remainingDays: 1, dailyAllowance: DailyAllowance(amount: nil, isExceeded: true))
        let lastMonth = makeContent(month: 9, remainingDays: nil, dailyAllowance: nil)

        #expect(try present(allowance).dailyText == "남은 7일, 하루 93,657씩 쓸 수 있습니다")
        #expect(try present(allowance, .en).dailyText == "7 days left · 93,657 a day")
        #expect(try present(zero).dailyText == "남은 7일, 더 쓸 수 있는 돈이 없습니다")
        #expect(try present(zero, .en).dailyText == "7 days left · nothing remaining")
        #expect(try present(exceeded).dailyText == "남은 7일, 더 쓸 수 있는 돈이 없습니다")
        #expect(try present(exceeded, .en).dailyText == "7 days left · nothing remaining")
        #expect(try present(lastDay, .en).dailyText == "1 day left · nothing remaining")
        #expect(try present(lastMonth).dailyText == nil)
    }

    @Test("빠진 거래 안내는 0 이면 줄이 없고, 동기화 전 → 환율 없음 순이며 en 은 1건과 여러 건을 나눈다")
    func missingLinesPluralize() throws {
        let none = makeContent(missingRateCount: 0, unsyncedCount: 0)
        let one = makeContent(missingRateCount: 1, unsyncedCount: 1)
        let two = makeContent(missingRateCount: 2, unsyncedCount: 2)
        let unsyncedOnly = makeContent(missingRateCount: 0, unsyncedCount: 2)

        #expect(try present(none).missingLines.isEmpty)
        #expect(try present(one).missingLines == [
            "동기화 전 거래 1건은 아직 빠져 있습니다.",
            "환율이 없는 거래 1건은 빠져 있습니다."
        ])
        #expect(try present(one, .en).missingLines == [
            "1 unsynced entry isn't included yet.",
            "1 entry without an exchange rate isn't included."
        ])
        #expect(try present(two).missingLines == [
            "동기화 전 거래 2건은 아직 빠져 있습니다.",
            "환율이 없는 거래 2건은 빠져 있습니다."
        ])
        #expect(try present(two, .en).missingLines == [
            "2 unsynced entries aren't included yet.",
            "2 entries without an exchange rate aren't included."
        ])
        #expect(try present(unsyncedOnly).missingLines == ["동기화 전 거래 2건은 아직 빠져 있습니다."])
    }
}

private struct StatusCase {
    let line: BudgetLine
    let korean: String
    let english: String
    let color: Color
}

/// USD 예산 2,000 에 1,234.5 를 쓴 진행 중(61%), 남은 돈 765.5.
private let usdUnder = under(2000, spent: Decimal(12345) / 10, .inProgress, percent: 61, left: Decimal(7655) / 10)

/// USD 예산 1.00 에 1.004 를 쓴 초과 — 서버 표시값은 사용 1.00(내림)·넘은 돈 0.01(올림).
private let usdOverByCent = over(1, spent: 1, by: Decimal(1) / 100)

@MainActor
private func present(_ content: BudgetTabContent, _ language: AppLanguage = .ko) throws -> BudgetTotalPresentation {
    try #require(BudgetTotalPresentation(content: content, language: language))
}

@MainActor
private func present(currency: CurrencyCode = .krw, total: BudgetLine) throws -> BudgetTotalPresentation {
    try present(makeContent(currency: currency, total: total))
}

private func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 1e-9
}

/// 넘지 않은 전체 줄. 남은 돈은 서버 표시값이다.
private func under(
    _ budget: Decimal,
    spent: Decimal,
    _ status: BudgetStatus,
    percent: Int? = nil,
    left remaining: Decimal
) -> BudgetLine {
    makeLine(budget: budget, actual: spent, status: status, percent: percent, remaining: remaining)
}

/// 넘은 전체 줄. 계약상 퍼센트·남은 돈은 null 이고 넘은 돈은 서버 표시값(올림)이다.
private func over(_ budget: Decimal, spent: Decimal, by overAmount: Decimal) -> BudgetLine {
    makeLine(budget: budget, actual: spent, status: .exceeded, over: overAmount)
}

private func makeLine(
    budget: Decimal,
    actual: Decimal,
    status: BudgetStatus,
    percent: Int? = nil,
    remaining: Decimal? = nil,
    over: Decimal? = nil
) -> BudgetLine {
    BudgetLine(
        budgetAmount: budget,
        actualAmount: actual,
        status: status,
        percent: percent,
        remainingAmount: remaining,
        overAmount: over
    )
}

/// 예산이 있는 달. 따로 적지 않으면 전체 1,000 에 250 을 쓴 진행 중(25%)이다.
@MainActor
private func makeContent(
    year: Int = 2026,
    month: Int = 10,
    current: ServerMonth = ServerMonth(year: 2026, month: 10),
    remainingDays: Int? = 7,
    currency: CurrencyCode = .krw,
    total: BudgetLine = under(1000, spent: 250, .inProgress, percent: 25, left: 750),
    dailyAllowance: DailyAllowance? = DailyAllowance(amount: 107, isExceeded: false),
    missingRateCount: Int = 0,
    unsyncedCount: Int = 0
) -> BudgetTabContent {
    BudgetTabContent(
        budget: MonthlyBudget(
            year: year,
            month: month,
            currentYear: current.year,
            currentMonth: current.month,
            remainingDaysIncludingToday: remainingDays,
            hasAnyBudget: true,
            status: total.status ?? .notSet,
            currency: currency,
            total: total,
            paymentGroups: [],
            categories: [],
            otherCategories: nil,
            missingRateCount: missingRateCount,
            dailyAllowance: dailyAllowance,
            deletedCategoriesWithSpending: []
        ),
        unsyncedExpenseCount: unsyncedCount,
        pendingDeletionCategoryIDs: []
    )
}

/// 미설정 달 — 계약상 통화·전체 줄이 null 이다. 이번 달이라 남은 일수는 있다.
@MainActor
private func makeNotSetContent() -> BudgetTabContent {
    BudgetTabContent(
        budget: MonthlyBudget(
            year: 2026,
            month: 10,
            currentYear: 2026,
            currentMonth: 10,
            remainingDaysIncludingToday: 7,
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
        ),
        unsyncedExpenseCount: 0,
        pendingDeletionCategoryIDs: []
    )
}
