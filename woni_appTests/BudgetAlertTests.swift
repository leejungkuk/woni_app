//
//  BudgetAlertTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 알림 판정·기록 키·창 내용. 판정은 서버가 준 전체 줄 `status` 만 본다.
/// 따로 적지 않으면 응답은 2026-10 이고 서버의 이번 달도 2026-10, 통화 KRW, 전체 예산 2,500,000 이다.
@MainActor
struct BudgetAlertTests {
    // MARK: 판정

    @Test("임박이면 80% 알림을 남은 돈과 함께 한 번 보내고, 80% 를 보냈으면 다시 보내지 않는다")
    func nearLimitSendsEightyOnce() throws {
        let budget = makeBudget(total: makeLine(status: .nearLimit, remaining: 500_000))

        let decision = try #require(BudgetAlertDecision.decide(budget, isSent: { _ in false }))

        #expect(decision.alert == BudgetAlert(
            threshold: .nearLimit,
            year: 2026,
            month: 10,
            currency: .krw,
            remainingAmount: 500_000,
            overAmount: nil,
            remainingDaysIncludingToday: 7,
            dailyAllowance: nil
        ))
        #expect(decision.record == [.nearLimit])

        #expect(BudgetAlertDecision.decide(budget, isSent: { $0 == .nearLimit }) == nil)
    }

    @Test("100% 에 닿거나 넘으면 100% 알림만 보내고 80% 도 보낸 것으로 기록한다")
    func reachingSendsHundredAndCountsEighty() throws {
        let hundred = BudgetAlert(
            threshold: .reached,
            year: 2026,
            month: 10,
            currency: .krw,
            remainingAmount: nil,
            overAmount: nil,
            remainingDaysIncludingToday: 7,
            dailyAllowance: nil
        )

        for status in [BudgetStatus.exceeded, .reached] {
            let budget = makeBudget(total: makeLine(status: status))

            let decision = try #require(BudgetAlertDecision.decide(budget, isSent: { _ in false }))
            #expect(decision.alert == hundred)
            #expect(decision.record == [.nearLimit, .reached])

            // 80% 만 보낸 뒤 100% 에 닿아도 100% 는 나간다.
            let afterEighty = try #require(BudgetAlertDecision.decide(budget, isSent: { $0 == .nearLimit }))
            #expect(afterEighty.alert == hundred)

            #expect(BudgetAlertDecision.decide(budget, isSent: { $0 == .reached }) == nil)
        }
    }

    @Test("0원 예산을 넘으면 100% 알림을 보내고 80% 도 보낸 것으로 기록하며, 100% 를 보냈으면 다시 보내지 않는다")
    func zeroBudgetExceededSendsHundred() throws {
        let budget = makeBudget(total: BudgetLine(
            budgetAmount: 0,
            actualAmount: 12000,
            status: .exceeded,
            percent: nil,
            remainingAmount: nil,
            overAmount: 12000
        ))

        let decision = try #require(BudgetAlertDecision.decide(budget, isSent: { _ in false }))
        #expect(decision.alert == BudgetAlert(
            threshold: .reached,
            year: 2026,
            month: 10,
            currency: .krw,
            remainingAmount: nil,
            overAmount: 12000,
            remainingDaysIncludingToday: 7,
            dailyAllowance: nil
        ))
        #expect(decision.record == [.nearLimit, .reached])

        #expect(BudgetAlertDecision.decide(budget, isSent: { $0 == .reached }) == nil)
    }

    @Test("임박인데 서버가 준 남은 돈이 0 이어도 80% 알림을 남은 돈 0 과 함께 보낸다")
    func nearLimitWithZeroRemainingStillSends() throws {
        let budget = makeBudget(total: makeLine(status: .nearLimit, remaining: 0))

        let decision = try #require(BudgetAlertDecision.decide(budget, isSent: { _ in false }))

        #expect(decision.alert == BudgetAlert(
            threshold: .nearLimit,
            year: 2026,
            month: 10,
            currency: .krw,
            remainingAmount: 0,
            overAmount: nil,
            remainingDaysIncludingToday: 7,
            dailyAllowance: nil
        ))
        #expect(decision.record == [.nearLimit])
    }

    @Test("80% 아래·지출 없음·미설정이면 보내지 않는다")
    func belowThresholdSendsNothing() {
        let inProgress = makeBudget(total: makeLine(status: .inProgress, remaining: 1_000_000))
        let nothingSpent = makeBudget(total: makeLine(status: .none, remaining: 2_500_000))

        #expect(BudgetAlertDecision.decide(inProgress, isSent: { _ in false }) == nil)
        #expect(BudgetAlertDecision.decide(nothingSpent, isSent: { _ in false }) == nil)
        #expect(BudgetAlertDecision.decide(makeNotSetBudget(), isSent: { _ in false }) == nil)
    }

    @Test("응답 달이 서버의 이번 달이 아니면 넘었어도 보내지 않는다")
    func notCurrentMonthSendsNothing() {
        let september = makeBudget(year: 2026, month: 9, total: makeLine(status: .exceeded))
        let lastYearOctober = makeBudget(year: 2025, month: 10, total: makeLine(status: .exceeded))

        #expect(BudgetAlertDecision.decide(september, isSent: { _ in false }) == nil)
        #expect(BudgetAlertDecision.decide(lastYearOctober, isSent: { _ in false }) == nil)
    }

    @Test("계약상 있어야 할 남은 돈·통화·전체 예산이 없으면 기본값으로 메우지 않고 보내지 않는다")
    func malformedResponseSendsNothing() {
        let noRemaining = makeBudget(total: makeLine(status: .nearLimit, remaining: nil))
        let noCurrency = makeBudget(currency: nil, total: makeLine(status: .exceeded))
        let noBudgetAmount = makeBudget(total: BudgetLine(
            budgetAmount: nil,
            actualAmount: 2_600_000,
            status: .exceeded,
            percent: nil,
            remainingAmount: nil,
            overAmount: 100_000
        ))

        #expect(BudgetAlertDecision.decide(noRemaining, isSent: { _ in false }) == nil)
        #expect(BudgetAlertDecision.decide(noCurrency, isSent: { _ in false }) == nil)
        #expect(BudgetAlertDecision.decide(noBudgetAmount, isSent: { _ in false }) == nil)
    }

    // MARK: 기록 키

    @Test("기록 키는 계정·달·기준·예산 통화·전체 금액 중 하나만 달라도 다르다")
    func recordKeyChangesWithBudget() throws {
        let userA = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000A"))
        let userB = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000B"))
        let base = makeBudget(total: makeLine(budget: 500_000, status: .nearLimit, remaining: 50000))

        func key(_ user: UUID, _ budget: MonthlyBudget, _ threshold: BudgetAlertThreshold) throws -> String {
            try #require(BudgetAlertDecision.recordKey(userID: user, budget: budget, threshold: threshold))
        }

        let original = try key(userA, base, .nearLimit)
        #expect(try key(userA, base, .nearLimit) == original)

        let biggerTotal = makeBudget(total: makeLine(budget: 600_000, status: .nearLimit, remaining: 50000))
        let usd = makeBudget(currency: .usd, total: makeLine(budget: 500_000, status: .nearLimit, remaining: 50000))
        let november = makeBudget(
            year: 2026,
            month: 11,
            current: ServerMonth(year: 2026, month: 11),
            total: makeLine(budget: 500_000, status: .nearLimit, remaining: 50000)
        )

        #expect(try key(userA, biggerTotal, .nearLimit) != original)
        #expect(try key(userA, usd, .nearLimit) != original)
        #expect(try key(userB, base, .nearLimit) != original)
        #expect(try key(userA, base, .reached) != original)
        #expect(try key(userA, november, .nearLimit) != original)

        let fractional = try #require(Decimal(string: "1234.5"))
        let fractionalBudget = makeBudget(
            currency: .usd, total: makeLine(budget: fractional, status: .nearLimit, remaining: 100)
        )
        #expect(try key(userA, fractionalBudget, .nearLimit).contains("1234.5"))

        #expect(BudgetAlertDecision.recordKey(userID: userA, budget: makeNotSetBudget(), threshold: .reached) == nil)
    }

    @Test("같은 달이라도 해가 다르면 기록 키가 다르다")
    func recordKeyDiffersByYear() throws {
        let user = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000A"))
        let line = makeLine(budget: 500_000, status: .nearLimit, remaining: 50000)
        let november2026 = makeBudget(year: 2026, month: 11, current: ServerMonth(year: 2026, month: 11), total: line)
        let november2027 = makeBudget(year: 2027, month: 11, current: ServerMonth(year: 2027, month: 11), total: line)

        let key2026 = try #require(
            BudgetAlertDecision.recordKey(userID: user, budget: november2026, threshold: .nearLimit)
        )
        let key2027 = try #require(
            BudgetAlertDecision.recordKey(userID: user, budget: november2027, threshold: .nearLimit)
        )

        #expect(key2026 != key2027)
    }

    // MARK: 발송 기록

    @Test("넣은 기록은 남고 비우면 사라지며 다른 suite 의 저장소에는 없다")
    func recordStoreClears() throws {
        try withUserDefaultsSuite { userDefaults, suiteName in
            let store = BudgetAlertRecordStore(userDefaults: userDefaults)
            #expect(!store.contains("a"))

            store.insert(["a", "b"])
            #expect(store.contains("a"))
            #expect(store.contains("b"))

            let restoredDefaults = try #require(UserDefaults(suiteName: suiteName))
            #expect(BudgetAlertRecordStore(userDefaults: restoredDefaults).contains("a"))

            try withUserDefaultsSuite { otherDefaults, _ in
                #expect(!BudgetAlertRecordStore(userDefaults: otherDefaults).contains("a"))
            }

            store.clear()
            #expect(!store.contains("a"))
            #expect(!store.contains("b"))
            #expect(!BudgetAlertRecordStore(userDefaults: restoredDefaults).contains("a"))
        }
    }

    @Test("나중에 넣은 기록이 먼저 넣은 기록을 지우지 않는다 — 지우면 다른 달·예산에 보낸 알림이 다시 나간다")
    func insertKeepsEarlierRecords() throws {
        try withUserDefaultsSuite { userDefaults, suiteName in
            let store = BudgetAlertRecordStore(userDefaults: userDefaults)

            store.insert(["a"])
            store.insert(["b"])

            #expect(store.contains("a"))
            #expect(store.contains("b"))

            let restored = try BudgetAlertRecordStore(userDefaults: #require(UserDefaults(suiteName: suiteName)))
            #expect(restored.contains("a"))
            #expect(restored.contains("b"))
        }
    }
}

// MARK: 창 내용 — 판정한 응답의 서버 값 그대로

extension BudgetAlertTests {
    @Test("BAD.S1-R4 임박 창은 응답의 남은 돈·남은 날·하루 권장액을 그대로 담고 넘은 돈은 없다")
    func nearLimitAlertCarriesServerValues() throws {
        let daily = DailyAllowance(amount: 22222, isExceeded: false)
        let budget = makeBudget(
            total: makeLine(budget: 1_000_000, status: .nearLimit, remaining: 200_000),
            remainingDays: 9,
            dailyAllowance: daily
        )

        let decision = try #require(BudgetAlertDecision.decide(budget, isSent: { _ in false }))

        #expect(decision.alert == BudgetAlert(
            threshold: .nearLimit,
            year: 2026,
            month: 10,
            currency: .krw,
            remainingAmount: 200_000,
            overAmount: nil,
            remainingDaysIncludingToday: 9,
            dailyAllowance: daily
        ))
    }

    @Test("BAD.S1-R4 넘음 창은 응답 전체 줄의 넘은 돈을 담고 남은 돈은 없으며, 딱 100% 창은 넘은 돈도 없다")
    func hundredAlertCarriesOverAmountOnlyWhenExceeded() throws {
        let overDaily = DailyAllowance(amount: nil, isExceeded: true)
        let exceeded = makeBudget(
            total: BudgetLine(
                budgetAmount: 1_000_000,
                actualAmount: 1_030_000,
                status: .exceeded,
                percent: nil,
                remainingAmount: nil,
                overAmount: 30000
            ),
            remainingDays: 9,
            dailyAllowance: overDaily
        )
        let usedUpDaily = DailyAllowance(amount: 0, isExceeded: false)
        let reached = makeBudget(
            total: BudgetLine(
                budgetAmount: 1_000_000,
                actualAmount: 1_000_000,
                status: .reached,
                percent: 100,
                remainingAmount: 0,
                overAmount: nil
            ),
            remainingDays: 4,
            dailyAllowance: usedUpDaily
        )

        let overDecision = try #require(BudgetAlertDecision.decide(exceeded, isSent: { _ in false }))
        let reachedDecision = try #require(BudgetAlertDecision.decide(reached, isSent: { _ in false }))

        #expect(overDecision.alert == BudgetAlert(
            threshold: .reached,
            year: 2026,
            month: 10,
            currency: .krw,
            remainingAmount: nil,
            overAmount: 30000,
            remainingDaysIncludingToday: 9,
            dailyAllowance: overDaily
        ))
        #expect(reachedDecision.alert == BudgetAlert(
            threshold: .reached,
            year: 2026,
            month: 10,
            currency: .krw,
            remainingAmount: nil,
            overAmount: nil,
            remainingDaysIncludingToday: 4,
            dailyAllowance: usedUpDaily
        ))
    }

    @Test("BAD.S1-R4 응답에 남은 날·하루 권장액이 없으면 창에도 없다 — 기본값으로 메우지 않는다")
    func missingDaysAndAllowanceStayNil() throws {
        let budget = makeBudget(
            total: makeLine(budget: 1_000_000, status: .nearLimit, remaining: 150_000),
            remainingDays: nil,
            dailyAllowance: nil
        )

        let decision = try #require(BudgetAlertDecision.decide(budget, isSent: { _ in false }))

        #expect(decision.alert.remainingAmount == 150_000)
        #expect(decision.alert.remainingDaysIncludingToday == nil)
        #expect(decision.alert.dailyAllowance == nil)
    }

    @Test("BAD.S1-R4 USD 응답의 창은 통화 USD 이고 남은 돈·넘은 돈·하루 권장액의 소수를 그대로 담는다")
    func usdAlertKeepsFractions() throws {
        let remaining = try #require(Decimal(string: "187.66"))
        let over = try #require(Decimal(string: "0.01"))
        let daily = try DailyAllowance(amount: #require(Decimal(string: "15.64")), isExceeded: false)
        let nearLimit = makeBudget(
            currency: .usd,
            total: makeLine(budget: 1000, status: .nearLimit, remaining: remaining),
            remainingDays: 12,
            dailyAllowance: daily
        )
        let exceeded = makeBudget(
            currency: .usd,
            total: BudgetLine(
                budgetAmount: 1000,
                actualAmount: 1000 + over,
                status: .exceeded,
                percent: nil,
                remainingAmount: nil,
                overAmount: over
            ),
            remainingDays: 12
        )

        let nearDecision = try #require(BudgetAlertDecision.decide(nearLimit, isSent: { _ in false }))
        let overDecision = try #require(BudgetAlertDecision.decide(exceeded, isSent: { _ in false }))

        #expect(nearDecision.alert == BudgetAlert(
            threshold: .nearLimit,
            year: 2026,
            month: 10,
            currency: .usd,
            remainingAmount: remaining,
            overAmount: nil,
            remainingDaysIncludingToday: 12,
            dailyAllowance: daily
        ))
        #expect(overDecision.alert.currency == .usd)
        #expect(overDecision.alert.overAmount == over)
    }
}

// MARK: - 픽스처

private func makeLine(
    budget: Decimal = 2_500_000,
    status: BudgetStatus,
    remaining: Decimal? = nil
) -> BudgetLine {
    BudgetLine(
        budgetAmount: budget,
        actualAmount: 0,
        status: status,
        percent: nil,
        remainingAmount: remaining,
        overAmount: nil
    )
}

@MainActor
private func makeBudget(
    year: Int = 2026,
    month: Int = 10,
    current: ServerMonth = ServerMonth(year: 2026, month: 10),
    currency: CurrencyCode? = .krw,
    total: BudgetLine,
    remainingDays: Int? = 7,
    dailyAllowance: DailyAllowance? = nil
) -> MonthlyBudget {
    MonthlyBudget(
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
        missingRateCount: 0,
        dailyAllowance: dailyAllowance,
        deletedCategoriesWithSpending: []
    )
}

/// 미설정 달 — 계약상 통화·전체 줄이 null 이다.
@MainActor
private func makeNotSetBudget() -> MonthlyBudget {
    MonthlyBudget(
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
    )
}

private func withUserDefaultsSuite(_ body: (UserDefaults, String) throws -> Void) throws {
    let suiteName = "woni_appTests.BudgetAlertTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    try body(userDefaults, suiteName)
}
