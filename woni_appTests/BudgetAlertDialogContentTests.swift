//
//  BudgetAlertDialogContentTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 알림창 제목·본문(UI_GUIDE "예산 알림창" 모양·en 표). 본문은 예산 탭 문구에 통화 코드를 앞에 붙인 금액이다.
/// 따로 적지 않으면 응답은 2026 년이고 통화 KRW 다.
@MainActor
struct BudgetAlertDialogContentTests {
    @Test("BAD.S3-R1 80% 창은 제목 + 남은 돈 줄 + 하루 줄이고, 하루 줄은 남은 날·하루 권장액이 둘 다 있을 때만이다")
    func nearLimitShowsRemainingAndDailyLines() {
        let may = makeAlert(.nearLimit, month: 5, remaining: 200_000, days: 9, daily: 22222)
        #expect(BudgetAlertDialogContent(alert: may, language: .ko) == BudgetAlertDialogContent(
            title: "5월 예산의 80%를 썼습니다",
            message: "남은 돈 KRW 200,000\n남은 9일, 하루 KRW 22,222씩 쓸 수 있습니다"
        ))

        let september = makeAlert(.nearLimit, month: 9, remaining: 200_000, days: 9, daily: 22222)
        #expect(BudgetAlertDialogContent(alert: september, language: .en) == BudgetAlertDialogContent(
            title: "You've used 80% of your September budget",
            message: "Remaining KRW 200,000\n9 days left · KRW 22,222 a day"
        ))

        let usd = makeAlert(.nearLimit, month: 12, currency: .usd, remaining: 12.5, days: 9, daily: 3.25)
        #expect(BudgetAlertDialogContent(alert: usd, language: .ko).message
            == "남은 돈 USD 12.50\n남은 9일, 하루 USD 3.25씩 쓸 수 있습니다")

        let lastDay = makeAlert(.nearLimit, month: 5, remaining: 48000, days: 1, daily: 48000)
        #expect(BudgetAlertDialogContent(alert: lastDay, language: .en).message
            == "Remaining KRW 48,000\n1 day left · KRW 48,000 a day")

        // 짝: 하루 금액이 0 이거나 없으면 쓸 돈이 없다는 줄이다.
        let zeroDaily = makeAlert(.nearLimit, month: 5, remaining: 160_000, days: 9, daily: 0)
        #expect(BudgetAlertDialogContent(alert: zeroDaily, language: .ko).message
            == "남은 돈 KRW 160,000\n남은 9일, 더 쓸 수 있는 돈이 없습니다")
        let noDailyAmount = makeAlert(
            .nearLimit,
            month: 5,
            remaining: 160_000,
            days: 9,
            allowance: DailyAllowance(amount: nil, isExceeded: false)
        )
        #expect(BudgetAlertDialogContent(alert: noDailyAmount, language: .ko).message
            == "남은 돈 KRW 160,000\n남은 9일, 더 쓸 수 있는 돈이 없습니다")

        // 짝: 남은 날이나 하루 권장액이 없으면 하루 줄이 없다 — 끝에 줄바꿈도 없다.
        let noDays = makeAlert(.nearLimit, month: 5, remaining: 150_000, days: nil, daily: 16666)
        #expect(BudgetAlertDialogContent(alert: noDays, language: .ko).message == "남은 돈 KRW 150,000")
        let noAllowance = makeAlert(.nearLimit, month: 5, remaining: 150_000, days: 9, allowance: nil)
        #expect(BudgetAlertDialogContent(alert: noAllowance, language: .ko).message == "남은 돈 KRW 150,000")
    }

    @Test("BAD.S3-R2 100% 넘음 창은 제목 + 넘은 돈 줄 + 하루 줄이다")
    func exceededShowsOverAndDailyLines() {
        let december = makeAlert(
            .reached,
            month: 12,
            over: 30000,
            days: 9,
            allowance: DailyAllowance(amount: nil, isExceeded: true)
        )
        #expect(BudgetAlertDialogContent(alert: december, language: .ko) == BudgetAlertDialogContent(
            title: "12월 예산을 다 썼습니다",
            message: "KRW 30,000 넘었습니다\n남은 9일, 더 쓸 수 있는 돈이 없습니다"
        ))
        #expect(BudgetAlertDialogContent(alert: december, language: .en) == BudgetAlertDialogContent(
            title: "You've used all of your December budget",
            message: "KRW 30,000 over\n9 days left · nothing remaining"
        ))

        let usd = makeAlert(
            .reached,
            month: 5,
            currency: .usd,
            over: 0.5,
            days: 9,
            allowance: DailyAllowance(amount: nil, isExceeded: true)
        )
        #expect(BudgetAlertDialogContent(alert: usd, language: .ko).message
            == "USD 0.50 넘었습니다\n남은 9일, 더 쓸 수 있는 돈이 없습니다")

        // 짝: 남은 날이 없으면 넘은 돈 한 줄이다.
        let noDays = makeAlert(
            .reached,
            month: 12,
            over: 41000,
            days: nil,
            allowance: DailyAllowance(amount: nil, isExceeded: true)
        )
        #expect(BudgetAlertDialogContent(alert: noDays, language: .ko).message == "KRW 41,000 넘었습니다")
    }

    @Test("BAD.S3-R3 딱 100% 창은 넘은 돈이 없어 '넘었습니다' 줄이 없다")
    func reachedExactlyHasNoOverLine() {
        let september = makeAlert(.reached, month: 9, over: nil, days: 9, daily: 0)
        #expect(BudgetAlertDialogContent(alert: september, language: .ko) == BudgetAlertDialogContent(
            title: "9월 예산을 다 썼습니다",
            message: "남은 9일, 더 쓸 수 있는 돈이 없습니다"
        ))
        #expect(BudgetAlertDialogContent(alert: september, language: .en) == BudgetAlertDialogContent(
            title: "You've used all of your September budget",
            message: "9 days left · nothing remaining"
        ))

        // 짝: 넘은 돈도 남은 날도 없으면 본문이 비어 제목만 있는 창이다.
        let titleOnly = makeAlert(.reached, month: 9, over: nil, days: nil, daily: 0)
        #expect(BudgetAlertDialogContent(alert: titleOnly, language: .ko) == BudgetAlertDialogContent(
            title: "9월 예산을 다 썼습니다",
            message: ""
        ))
    }

    @Test("BAD.S3-R4 창 하루 줄은 예산 탭 하루 줄과 같은 갈래이고 금액 앞에 통화 코드만 붙으며, 탭 글자는 코드가 없다")
    func dailyLineMatchesBudgetTab() throws {
        let tab = try #require(BudgetTotalPresentation(content: makeTabContent(daily: 22222), language: .ko))
        #expect(tab.dailyText == "남은 9일, 하루 22,222씩 쓸 수 있습니다")
        let zeroTab = try #require(BudgetTotalPresentation(content: makeTabContent(daily: 0), language: .ko))
        #expect(zeroTab.dailyText == "남은 9일, 더 쓸 수 있는 돈이 없습니다")

        let allowances: [DailyAllowance] = [
            DailyAllowance(amount: 22222, isExceeded: false),
            DailyAllowance(amount: 0, isExceeded: false),
            DailyAllowance(amount: -1, isExceeded: true),
            DailyAllowance(amount: nil, isExceeded: true)
        ]
        for allowance in allowances {
            for language in [AppLanguage.ko, .en] {
                let tab = BudgetTotalPresentation(content: makeTabContent(allowance: allowance), language: language)
                let tabText = try #require(tab?.dailyText)
                let alert = makeAlert(.nearLimit, month: 10, remaining: 200_000, days: 9, allowance: allowance)
                let alertDaily = try #require(
                    BudgetAlertDialogContent(alert: alert, language: language).message.split(separator: "\n").last
                )
                #expect(alertDaily.replacingOccurrences(of: "KRW ", with: "") == tabText)
            }
        }
        let alert = makeAlert(.nearLimit, month: 10, remaining: 200_000, days: 9, daily: 22222)
        #expect(BudgetAlertDialogContent(alert: alert, language: .ko).message
            .hasSuffix("남은 9일, 하루 KRW 22,222씩 쓸 수 있습니다"))
    }
}

private func makeAlert(
    _ threshold: BudgetAlertThreshold,
    month: Int,
    currency: CurrencyCode = .krw,
    remaining: Decimal? = nil,
    over: Decimal? = nil,
    days: Int?,
    daily: Decimal
) -> BudgetAlert {
    makeAlert(
        threshold,
        month: month,
        currency: currency,
        remaining: remaining,
        over: over,
        days: days,
        allowance: DailyAllowance(amount: daily, isExceeded: daily <= 0)
    )
}

private func makeAlert(
    _ threshold: BudgetAlertThreshold,
    month: Int,
    currency: CurrencyCode = .krw,
    remaining: Decimal? = nil,
    over: Decimal? = nil,
    days: Int?,
    allowance: DailyAllowance?
) -> BudgetAlert {
    BudgetAlert(
        threshold: threshold,
        year: 2026,
        month: month,
        currency: currency,
        remainingAmount: remaining,
        overAmount: over,
        remainingDaysIncludingToday: days,
        dailyAllowance: allowance
    )
}

private func makeTabContent(daily: Decimal) -> BudgetTabContent {
    makeTabContent(allowance: DailyAllowance(amount: daily, isExceeded: daily <= 0))
}

/// 예산 탭 이번 달(2026-10) 임박 카드 — 전체 1,000,000 에 800,000 을 썼고 서버 남은 일수는 9 다.
private func makeTabContent(allowance: DailyAllowance) -> BudgetTabContent {
    BudgetTabContent(
        budget: MonthlyBudget(
            year: 2026,
            month: 10,
            currentYear: 2026,
            currentMonth: 10,
            remainingDaysIncludingToday: 9,
            hasAnyBudget: true,
            status: .nearLimit,
            currency: .krw,
            total: BudgetLine(
                budgetAmount: 1_000_000,
                actualAmount: 800_000,
                status: .nearLimit,
                percent: 80,
                remainingAmount: 200_000,
                overAmount: nil
            ),
            paymentGroups: [],
            categories: [],
            otherCategories: nil,
            missingRateCount: 0,
            dailyAllowance: allowance,
            deletedCategoriesWithSpending: []
        ),
        unsyncedExpenseCount: 0,
        pendingDeletionCategoryIDs: []
    )
}
