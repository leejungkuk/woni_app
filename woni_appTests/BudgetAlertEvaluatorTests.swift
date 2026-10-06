//
//  BudgetAlertEvaluatorTests.swift
//  woni_appTests
//

import Foundation
import SwiftUI
import Testing
@testable import woni_app

/// 예산 알림 판정기 — 언제 판정해 창을 내는지(스펙 §5). 창에 무엇이 들어가는지는 `BudgetAlertTests` 가 본다.
/// 따로 적지 않으면 계정 A 이고, 서버 시각과 응답의 이번 달은 2026-10,
/// 응답은 통화 KRW · 전체 예산 2,500,000 · 임박(남은 돈 500,000)이다. 기록은 실제 `BudgetAlertRecordStore`(테스트마다
/// 새 suite)다. "보낸다"는 루트가 창을 띄운 것(`showPending` — `markShown` 이 받아 줌)이다.
@Suite(.serialized)
@MainActor
struct BudgetAlertEvaluatorTests {
    // MARK: 판정을 시작할 조건

    @Test("B64N.S2-R4 신원이 없으면 서버를 부르지 않고 보내지 않으며, 신원이 생긴 뒤 판정은 처음 확인이라 창 없이 기록한다")
    func noIdentityDoesNotFetch() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.userID = nil

        await fakes.evaluateAndShow(evaluator)

        #expect(fakes.probeCount == 0)
        #expect(fakes.fetchedMonths.isEmpty)
        #expect(fakes.shown.isEmpty)

        fakes.userID = userA
        await fakes.evaluateAndShow(evaluator)
        #expect(fakes.shown.isEmpty)
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
    }

    @Test(
        "B64N.S2-R4 진행률을 받는 사이 신원이 없어지면 보내지도 기록하지도 않는다",
        arguments: [Point.probe, .firstFetch]
    )
    func identityLostWhileFetchingStops(_ point: Point) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: point) {
            fakes.userID = nil
        }

        // 그 자리에서 멈춘다 — 서버 시각을 받는 사이 없어졌으면 읽지도 않는다.
        #expect(fakes.fetchedMonths == (point == .probe ? [] : [october]))
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(makeBudget()).isEmpty)

        // 짝: 신원이 돌아오면 다음 판정이 보낸다 — 기준 아래로 확인해 둔 예산이다.
        fakes.userID = userA
        await fakes.confirmBelow(makeBudget(status: .inProgress))
        await fakes.evaluateAndShow(evaluator)
        #expect(fakes.shown.count == 1)
    }
}

// MARK: 앱 알림 설정·iOS 권한 없이 판정

extension BudgetAlertEvaluatorTests {
    @Test(
        "BAD.S0-R1 판정은 앱 알림 설정·iOS 권한 없이 서버 진행률만으로 돈다 — 이번 달 임박은 80%, 넘음은 100% 를 한 번 요청하고 기록한다",
        arguments: zip([BudgetStatus.nearLimit, .exceeded], [BudgetAlertThreshold.nearLimit, .reached])
    )
    func evaluatesFromServerProgressAlone(status: BudgetStatus, threshold: BudgetAlertThreshold) async throws {
        let fakes = try EvaluatorFakes()
        let budget = makeBudget(status: status)
        fakes.fetch.result = { _ in .success(budget) }
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))

        await evaluator.evaluate(.ledgerChange)

        // 서버 시각 한 번 · 읽기 한 번이 전부이고, 창이 하나 생긴다.
        #expect(fakes.log == [.probe, .fetch(october)])
        #expect(evaluator.pendingAlert?.threshold == threshold)
        #expect(fakes.showPending(evaluator)?.threshold == threshold)
        #expect(fakes.recorded(budget) == (threshold == .nearLimit ? [.nearLimit] : [.nearLimit, .reached]))
    }

    @Test(
        "BAD.S0-R1 짝: 이번 달 예산이 없거나 진행률을 읽지 못하면 요청도 기록도 없고, 신원이 없으면 서버를 읽지 않는다",
        arguments: NoAlert.allCases
    )
    func noProgressSendsNothing(_ noAlert: NoAlert) async throws {
        let fakes = try EvaluatorFakes()
        switch noAlert {
        case .notSet:
            fakes.fetch.result = { _ in .success(makeNotSetBudget()) }
        case .fetchFails:
            fakes.fetch.result = { _ in .failure(FakeError.offline) }
        case .noIdentity:
            fakes.userID = nil
        }
        let evaluator = fakes.makeEvaluator()

        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.probeCount == (noAlert == .noIdentity ? 0 : 1))
        #expect(fakes.fetchedMonths == (noAlert == .noIdentity ? [] : [october]))
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(makeBudget()).isEmpty)
    }

    @Test("BAD.S0-R1 원장 변경 신호 한 번에 같은 판정을 한 번 한다")
    func ledgerSignalEvaluatesOnce() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))
        let (events, continuation) = AsyncStream<Void>.makeStream()
        continuation.yield(())
        continuation.finish()

        await evaluator.observeLedgerChanges(events)

        #expect(fakes.log == [.probe, .fetch(october)])
        #expect(fakes.showPending(evaluator) == makeDefaultAlert(.nearLimit))
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
    }
}

// MARK: 진행률 받기 — 아는 달 · 받지 못함

extension BudgetAlertEvaluatorTests {
    @Test(
        "B64N.S2-R5 처음 판정은 서버 시각의 이번 달을 한 번 받아 그 달로 읽는다",
        arguments: zip([2026, 2031], [10, 3])
    )
    func firstEvaluationReadsServerMonth(year: Int, month: Int) async throws {
        let fakes = try EvaluatorFakes()
        let serverMonth = ServerMonth(year: year, month: month)
        fakes.probe.result = { _ in .success(serverMonth) }
        fakes.fetch.result = { .success(makeBudget($0, current: serverMonth)) }
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(serverMonth, current: serverMonth, status: .inProgress))

        await fakes.evaluateAndShow(evaluator)

        #expect(fakes.probeCount == 1)
        #expect(fakes.fetchedMonths == [serverMonth])
        #expect(fakes.shown.count == 1)
    }

    @Test("B64N.S2-R5 두 번째 판정은 서버 시각을 다시 묻지 않고 앞 판정 응답의 이번 달로 읽는다")
    func laterEvaluationReadsKnownMonth() async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate(.ledgerChange)
        #expect(fakes.fetchedMonths == [september, october])

        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.probeCount == 1)
        #expect(fakes.fetchedMonths == [september, october, october])
    }

    @Test("B64N.S2-R5 응답의 이번 달이 읽은 달과 다르면 그 달로 한 번 더 읽고, 다시 읽은 응답으로 판정한다")
    func rereadsResponseCurrentMonth() async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        // 첫 응답은 이번 달을 알아내는 데만 쓴다 — 계약에 어긋나도 다시 읽은 응답의 판정을 막지 않는다.
        let firstResponse = makeBudget(september, current: october, total: makeNearLimitTotalWithoutPercent())
        #expect(!BudgetTabViewModel.isWellFormed(firstResponse))
        fakes.fetch.result = { .success($0 == october ? makeBudget(october) : firstResponse) }
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(october, status: .inProgress))

        await fakes.evaluateAndShow(evaluator)

        #expect(fakes.fetchedMonths == [september, october])
        #expect(fakes.shown == [makeDefaultAlert(.nearLimit)])
        #expect(fakes.recorded(makeBudget(october)) == [.nearLimit])
    }

    @Test("B64N.S2-R5 다시 읽은 응답도 이번 달이 다르면 세 번째로 읽지 않고 보내지 않으며 아는 달도 그대로다")
    func secondMismatchStops() async throws {
        let fakes = try EvaluatorFakes()
        fakes.probe.result = { _ in .success(september) }
        fakes.fetch.result = { .success(makeBudget($0, current: september, status: .inProgress)) }
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate(.ledgerChange)
        #expect(fakes.fetchedMonths == [september])

        let november = ServerMonth(year: 2026, month: 11)
        fakes.fetch.result = { .success(makeBudget($0, current: $0 == september ? october : november)) }
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.fetchedMonths == [september, september, october])
        #expect(evaluator.pendingAlert == nil)

        // 다음 판정도 서버 시각을 묻지 않고 처음 읽은 달(9월)부터 읽는다.
        await evaluator.evaluate(.ledgerChange)
        #expect(fakes.probeCount == 1)
        #expect(fakes.fetchedMonths == [september, september, october, september, october])
    }

    @Test("B64N.S2-R5 reset() 뒤의 판정은 서버 시각의 이번 달부터 다시 받는다")
    func resetForgetsKnownMonth() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate(.ledgerChange)
        await evaluator.evaluate(.ledgerChange)
        #expect(fakes.probeCount == 1)

        evaluator.reset()
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.probeCount == 2)
    }

    @Test(
        "B64N.S2-R5 판정에 쓰지 않은 응답은 아는 달을 바꾸지 않는다 — 다음 판정이 서버 시각 없이 같은 달로 읽는다",
        arguments: Discard.allCases
    )
    func discardedEvaluationKeepsKnownMonth(_ discard: Discard) async throws {
        let fakes = try EvaluatorFakes()
        fakes.probe.result = { _ in .success(september) }
        fakes.fetch.result = { .success(makeBudget($0, current: september, status: .inProgress)) }
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate(.ledgerChange)

        // 서버의 이번 달이 10월로 넘어갔다.
        let movedOn: (ServerMonth) -> Result<MonthlyBudget, any Error> = { .success(makeBudget($0, current: october)) }
        switch discard {
        case .firstFetchFails:
            fakes.fetch.result = { _ in .failure(FakeError.offline) }
            await evaluator.evaluate(.ledgerChange)
        case .rereadFails:
            fakes.fetch.result = { $0 == october ? .failure(FakeError.offline) : movedOn($0) }
            await evaluator.evaluate(.ledgerChange)
        case .accountSwitchedDuringReread:
            fakes.fetch.result = movedOn
            await fakes.evaluate(evaluator, holding: .rereadFetch) { fakes.userID = userB }
        }
        #expect(evaluator.pendingAlert == nil)
        let readsBefore = fakes.fetchedMonths.count

        fakes.fetch.result = movedOn
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.probeCount == 1)
        #expect(fakes.fetchedMonths.dropFirst(readsBefore).first == september)
    }

    @Test("B64N.S2-R6 서버 시각을 받지 못하면 읽지도 보내지도 않는다")
    func probeFailureStops() async throws {
        let fakes = try EvaluatorFakes()
        fakes.probe.result = { _ in .failure(FakeError.offline) }
        let evaluator = fakes.makeEvaluator()

        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.probeCount == 1)
        #expect(fakes.fetchedMonths.isEmpty)
        #expect(evaluator.pendingAlert == nil)

        // 짝: 받으면 읽고 보낸다 — 기준 아래로 확인해 둔 예산이다.
        fakes.probe.result = { _ in .success(october) }
        await fakes.confirmBelow(makeBudget(status: .inProgress))
        await fakes.evaluateAndShow(evaluator)
        #expect(fakes.fetchedMonths == [october])
        #expect(fakes.shown.count == 1)
    }

    @Test(
        "B64N.S2-R6 진행률을 받지 못하면(첫 읽기·다시 읽기) 보내지도 기록하지도 않고, 다음에 받으면 보낸다",
        arguments: [Point.firstFetch, .rereadFetch]
    )
    func fetchFailureStops(_ point: Point) async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: point, failing: FakeError.offline)

        #expect(fakes.fetchedMonths == (point == .firstFetch ? [september] : [september, october]))
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(makeBudget(october)).isEmpty)

        await fakes.confirmBelow(makeBudget(october, status: .inProgress))
        await fakes.evaluateAndShow(evaluator)
        #expect(fakes.shown.count == 1)
        #expect(fakes.recorded(makeBudget(october)) == [.nearLimit])
    }

    @Test("B64N.S2-R6 계약 검사에만 걸리는 응답(임박인데 퍼센트 없음)으로는 보내지도 기록하지도 않는다")
    func malformedResponseIsNotJudged() async throws {
        let broken = makeBudget(total: makeNearLimitTotalWithoutPercent())
        // step 1 판정만으로는 보낸다 — 막는 것은 계약 검사다.
        #expect(!BudgetTabViewModel.isWellFormed(broken))
        #expect(BudgetAlertDecision.decide(broken, isSent: { _ in false }) != nil)
        let fakes = try EvaluatorFakes()
        fakes.fetch.result = { _ in .success(broken) }
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))

        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.fetchedMonths == [october])
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(broken).isEmpty)

        // 짝: 같은 응답에 퍼센트가 있으면 보낸다.
        fakes.fetch.result = { .success(makeBudget($0)) }
        await fakes.evaluateAndShow(evaluator)
        #expect(fakes.shown.count == 1)
    }
}

// MARK: 기다리는 자리 — 계정이 바뀜

extension BudgetAlertEvaluatorTests {
    @Test(
        "B64N.S2-R7 진행률을 받는 사이 아무것도 바뀌지 않으면 한 번 보낸다",
        arguments: [Point.firstFetch, .rereadFetch]
    )
    func unchangedSettingSends(_ point: Point) async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(october, status: .inProgress))

        await fakes.evaluate(evaluator, holding: point)
        fakes.showPending(evaluator)

        #expect(fakes.shown.count == 1)
        #expect(fakes.recorded(makeBudget(october)) == [.nearLimit])
    }

    @Test(
        "B64N.S2-R9 판정이 기다리는 사이 계정이 바뀌면(ID 다름·reset) 그 자리에서 멈춘다 — 보내지도 기록하지도 않는다",
        arguments: Point.allCases, [Change.switchAccount, .reset]
    )
    func accountChangedWhileWaitingStops(_ point: Point, _ change: Change) async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: point) {
            fakes.apply(change, to: evaluator)
        }

        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(makeBudget(october), user: userA).isEmpty)
        #expect(fakes.recorded(makeBudget(october), user: userB).isEmpty)
    }

    @Test(
        "B64N.S2-R9 아무것도 바뀌지 않으면 어느 자리에서 기다려도 보내고 기록한다",
        arguments: Point.allCases
    )
    func unchangedAccountSends(_ point: Point) async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(october, status: .inProgress))

        await fakes.evaluate(evaluator, holding: point)
        fakes.showPending(evaluator)

        #expect(fakes.shown.count == 1)
        #expect(fakes.recorded(makeBudget(october)) == [.nearLimit])
    }
}

// MARK: 한 번에 하나

extension BudgetAlertEvaluatorTests {
    @Test("B64N.S2-R10 판정 중에 온 요청 여럿은 앞 판정이 끝난 뒤 한 번만 더 돌고, 기다린 요청은 그 판정이 끝난 뒤 돌아온다")
    func requestsDuringEvaluationRunOnceAfter() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))
        fakes.fetch.hold()
        let first = fakes.startEvaluating(evaluator)
        await waitUntil { fakes.fetch.hasHeld }
        let second = fakes.startEvaluating(evaluator)
        let third = fakes.startEvaluating(evaluator)
        await settleMainActor()
        #expect(fakes.fetchedMonths.count == 1)

        // 뒤 판정의 읽기도 붙잡아, 그 판정이 끝나기 전에는 아무도 돌아오지 않는지 본다.
        fakes.fetch.hold()
        fakes.fetch.release()
        await waitUntil { fakes.fetch.hasHeld }
        await settleMainActor()
        #expect(fakes.fetchedMonths.count == 2)
        #expect(evaluator.pendingAlert == makeDefaultAlert(.nearLimit))
        #expect(fakes.returnedAfterFetches.isEmpty)

        fakes.fetch.release()
        await first.value
        await second.value
        await third.value

        // 뒤 판정은 같은 창으로 바꿀 뿐이라 창은 하나다.
        #expect(fakes.fetchedMonths.count == 2)
        #expect(evaluator.pendingAlert == makeDefaultAlert(.nearLimit))
        #expect(fakes.returnedAfterFetches == [2, 2, 2])
    }

    @Test("B64N.S2-R10 앞 판정이 읽기 실패로 멈춰도 기다리던 판정은 한 번 돈다")
    func waitingEvaluationRunsAfterFailedOne() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))
        fakes.fetch.hold()
        let first = fakes.startEvaluating(evaluator)
        await waitUntil { fakes.fetch.hasHeld }
        let queued = fakes.startEvaluating(evaluator)
        await settleMainActor()
        let fetchesBefore = fakes.fetchedMonths.count

        fakes.fetch.release(with: .failure(FakeError.offline))
        await first.value
        await queued.value
        fakes.showPending(evaluator)

        #expect(fakes.fetchedMonths.count - fetchesBefore == 1)
        #expect(fakes.shown.count == 1)
    }

    @Test(
        "B64N.S2-R10 앞 판정 중에 reset() 되면 앞 판정은 버리고 기다리던 판정이 서버 시각부터 다시 읽는다 — 처음 확인이라 창 없이 기록한다"
    )
    func waitingEvaluationRunsAfterReset() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))
        await fakes.evaluateAndShow(evaluator)
        #expect(fakes.shown.count == 1)
        fakes.fetch.hold()
        let first = fakes.startEvaluating(evaluator)
        await waitUntil { fakes.fetch.hasHeld }
        let queued = fakes.startEvaluating(evaluator)
        await settleMainActor()
        evaluator.reset()
        let probesBefore = fakes.probeCount
        let fetchesBefore = fakes.fetchedMonths.count
        let sentBefore = fakes.shown.count

        fakes.fetch.release()
        await first.value
        await queued.value
        fakes.showPending(evaluator)

        #expect(fakes.probeCount - probesBefore == 1)
        #expect(fakes.fetchedMonths.count - fetchesBefore == 1)
        #expect(fakes.shown.count - sentBefore == 0)
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
    }
}

// MARK: 기록

extension BudgetAlertEvaluatorTests {
    @Test("B64N.S2-R11 같은 응답으로 다시 판정해도 한 번만 보낸다")
    func sameResponseSendsOnce() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))

        await fakes.evaluateAndShow(evaluator)
        await fakes.evaluateAndShow(evaluator)

        #expect(fakes.shown.count == 1)
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
    }

    @Test("B64N.S2-R11 80% 를 보낸 뒤 넘으면 100% 를 한 번 더 보내고, 그대로면 다시 보내지 않는다")
    func hundredAfterEighty() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))
        await fakes.evaluateAndShow(evaluator)

        fakes.fetch.result = { .success(makeBudget($0, status: .exceeded)) }
        await fakes.evaluateAndShow(evaluator)
        await fakes.evaluateAndShow(evaluator)

        #expect(fakes.shown == [makeDefaultAlert(.nearLimit), makeDefaultAlert(.exceeded)])
        #expect(fakes.recorded(makeBudget()) == [.nearLimit, .reached])
    }

    @Test("B64N.S2-R11 처음 판정에서 넘었으면 창 없이 80·100 을 기록하고, 같은 예산이 임박으로 내려와도 80% 창이 없다")
    func eightyCountedWithHundred() async throws {
        let fakes = try EvaluatorFakes()
        fakes.fetch.result = { .success(makeBudget($0, status: .exceeded)) }
        let evaluator = fakes.makeEvaluator()
        await fakes.evaluateAndShow(evaluator)
        #expect(fakes.shown.isEmpty)
        #expect(fakes.recorded(makeBudget()) == [.nearLimit, .reached])

        fakes.fetch.result = { .success(makeBudget($0)) }
        await fakes.evaluateAndShow(evaluator)

        #expect(fakes.shown.isEmpty)
        #expect(fakes.recorded(makeBudget()) == [.nearLimit, .reached])
    }

    @Test("B64N.S2-R11 기준 아래로 내려갔다 다시 넘어도 같은 예산이면 다시 보내지 않는다")
    func droppingBelowAndBackDoesNotResend() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))

        for status in [BudgetStatus.nearLimit, .inProgress, .nearLimit] {
            fakes.fetch.result = { .success(makeBudget($0, status: status)) }
            await fakes.evaluateAndShow(evaluator)
        }

        #expect(fakes.shown.count == 1)
    }

    @Test(
        "B64N.S2-R11 전체 금액이나 통화가 바뀐 예산은 새 기준이다 — 처음 확인이 이미 넘었으면 창 없이 기록하고, 그 뒤 100% 를 넘으면 창",
        arguments: BudgetChange.allCases
    )
    func changedBudgetResends(_ change: BudgetChange) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))
        await fakes.evaluateAndShow(evaluator)
        func changed(_ status: BudgetStatus) -> MonthlyBudget {
            switch change {
            case .amount: makeBudget(status: status, amount: 3_000_000)
            case .currency: makeBudget(status: status, currency: .usd)
            }
        }

        fakes.fetch.result = { _ in .success(changed(.nearLimit)) }
        await fakes.evaluateAndShow(evaluator)
        #expect(fakes.shown.map(\.threshold) == [.nearLimit])
        #expect(fakes.recorded(changed(.nearLimit)) == [.nearLimit])

        fakes.fetch.result = { _ in .success(changed(.exceeded)) }
        await fakes.evaluateAndShow(evaluator)

        #expect(fakes.shown.map(\.threshold) == [.nearLimit, .reached])
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
        #expect(fakes.recorded(changed(.exceeded)) == [.nearLimit, .reached])
    }

    @Test("B64N.S2-R11 50만 → 60만 → 50만으로 돌아온 예산은 앞의 50만 기록이 남아 다시 보내지 않는다")
    func returningToEarlierAmountDoesNotResend() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        var sentCounts: [Int] = []

        for amount: Decimal in [500_000, 600_000, 500_000] {
            await fakes.confirmBelow(makeBudget(status: .inProgress, amount: amount))
            fakes.fetch.result = { .success(makeBudget($0, amount: amount)) }
            await fakes.evaluateAndShow(evaluator)
            sentCounts.append(fakes.shown.count)
        }

        #expect(sentCounts == [1, 2, 2])
        #expect(fakes.recorded(makeBudget(amount: 500_000)) == [.nearLimit])
        #expect(fakes.recorded(makeBudget(amount: 600_000)) == [.nearLimit])
    }

    @Test("B64N.S2-R13 reset() 은 기록을 비운다 — 같은 응답으로 다시 판정하면 처음 확인이라 창 없이 다시 기록한다")
    func resetClearsRecords() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))
        await fakes.evaluateAndShow(evaluator)
        await fakes.evaluateAndShow(evaluator)
        #expect(fakes.shown.count == 1)

        evaluator.reset()
        #expect(fakes.recorded(makeBudget()).isEmpty)
        #expect(!fakes.isConfirmed(makeBudget()))
        await fakes.evaluateAndShow(evaluator)

        #expect(fakes.shown.count == 1)
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
    }
}

// MARK: 판정 시점

extension BudgetAlertEvaluatorTests {
    @Test("B64N.S5-R3 원장 변경 신호마다 판정한다 — 신호 2번이면 두 번 읽고, 둘째는 기록이 있어 보내지 않는다")
    func ledgerChangesEvaluateEachSignal() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.confirmBelow(makeBudget(status: .inProgress))
        let (events, continuation) = AsyncStream<Void>.makeStream()
        continuation.yield(())
        continuation.yield(())
        continuation.finish()

        await evaluator.observeLedgerChanges(events)

        // 둘째 판정은 같은 창으로 바꿀 뿐이라 창은 하나다.
        #expect(fakes.fetchedMonths == [october, october])
        #expect(fakes.showPending(evaluator) == makeDefaultAlert(.nearLimit))
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
    }

    @Test("B64N.S5-R3 원장 변경 신호 없이 스트림이 끝나면 판정하지 않는다")
    func noLedgerChangeDoesNotEvaluate() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let (events, continuation) = AsyncStream<Void>.makeStream()
        continuation.finish()

        await evaluator.observeLedgerChanges(events)

        #expect(fakes.log.isEmpty)
        #expect(fakes.recorded(makeBudget()).isEmpty)
    }
}

// MARK: 창 — 띄운 순간 기록 · 최신 것만

/// 따로 적지 않으면 전체 예산 1,000,000 KRW 이고, 창을 기대하는 판정 앞에 같은 예산의 "아래" 판정을 한 번 둔다.
extension BudgetAlertEvaluatorTests {
    @Test("BAD.S1-R1 판정은 기록하지 않고 창만 낸다 — markShown 이 기록하고 창을 비우며, 그 뒤 같은 응답에는 창이 없다")
    func markShownRecordsAndClears() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 800_000, percent: 80)
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == nil)

        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)
        let alert = try #require(evaluator.pendingAlert)
        #expect(alert.threshold == .nearLimit)
        #expect(fakes.recorded(near).isEmpty)

        #expect(evaluator.markShown(alert))
        #expect(fakes.recorded(near) == [.nearLimit])
        #expect(evaluator.pendingAlert == nil)

        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == nil)
    }

    @Test("BAD.S1-R1 띄우지 않은 창은 다시 판정해도 하나 그대로이고, 앱이 다시 켜지면(새 판정기·같은 저장소) 다시 생긴다")
    func unshownAlertSurvivesUntilShown() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 820_000, percent: 82)
        fakes.respond(makeServerBudget(.inProgress, spent: 400_000, percent: 40))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)
        let alert = try #require(evaluator.pendingAlert)

        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == alert)
        #expect(fakes.recorded(near).isEmpty)

        let relaunched = fakes.makeEvaluator()
        #expect(relaunched.pendingAlert == nil)
        await relaunched.evaluate(.ledgerChange)
        #expect(relaunched.pendingAlert == alert)
    }

    @Test("BAD.S1-R1 짝: 창이 없거나 지금 창과 다른 창(기준·금액)으로 부른 markShown 은 false 이고 기록도 창도 그대로다")
    func markShownRejectsOtherAlert() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 800_000, percent: 80)
        #expect(!evaluator.markShown(makeWindow(.nearLimit, remaining: 200_000)))

        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)
        let alert = try #require(evaluator.pendingAlert)
        #expect(alert == makeWindow(.nearLimit, remaining: 200_000))

        #expect(!evaluator.markShown(makeWindow(.reached, over: 30000)))
        #expect(!evaluator.markShown(makeWindow(.nearLimit, remaining: 150_000)))
        #expect(fakes.recorded(near).isEmpty)
        #expect(evaluator.pendingAlert == alert)
    }

    @Test("BAD.S1-R2 기다리던 80% 창은 새 임박 판정의 창으로 바뀐다 — 남은 돈이 줄면 새 남은 돈이다")
    func newerNearLimitReplacesPending() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(makeServerBudget(.nearLimit, spent: 800_000, percent: 80))
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == makeWindow(.nearLimit, remaining: 200_000))

        fakes.respond(makeServerBudget(.nearLimit, spent: 850_000, percent: 85))
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == makeWindow(.nearLimit, remaining: 150_000))
    }

    @Test("BAD.S1-R2 80% 창이 기다리는 중 넘으면 100% 창 하나로 바뀌고, 띄우면 80·100 둘 다 기록한다")
    func exceedingReplacesEightyWithHundred() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 800_000, percent: 80)
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)

        fakes.respond(makeServerBudget(.exceeded, spent: 1_030_000))
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == makeWindow(.reached, over: 30000))
        #expect(fakes.recorded(near).isEmpty)

        fakes.showPending(evaluator)
        #expect(fakes.shown == [makeWindow(.reached, over: 30000)])
        #expect(fakes.recorded(near) == [.nearLimit, .reached])
    }

    @Test(
        "BAD.S1-R2 최신 판정에 띄울 것이 없으면(기준 아래·이번 달 예산 없음) 기다리던 창을 버린다",
        arguments: Dropped.allCases
    )
    func nothingToShowDropsPending(_ dropped: Dropped) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 800_000, percent: 80)
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert != nil)

        switch dropped {
        case .below:
            fakes.respond(makeServerBudget(.inProgress, spent: 600_000, percent: 60))
        case .notSet:
            fakes.respond(makeNotSetBudget())
        }
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(near).isEmpty)
    }

    @Test("BAD.S1-R2 전체 금액만 바뀐 예산(새 기록 키)의 판정도 기다리던 창을 바꾸고, 띄우면 새 키로만 기록한다")
    func changedKeyReplacesPending() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 800_000, percent: 80)
        let raised = makeServerBudget(.nearLimit, spent: 960_000, percent: 80, amount: 1_200_000)
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)
        // 바뀐 예산도 기준 아래로 확인해 둔 예산이다 — 처음 확인이 이미 넘었으면 창이 없다(step 2). 앞 실행의 판정기라
        // 기다리던 창은 그대로다.
        await fakes.confirmBelow(makeServerBudget(.inProgress, spent: 700_000, percent: 58, amount: 1_200_000))

        fakes.respond(raised)
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == makeWindow(.nearLimit, remaining: 240_000))

        fakes.showPending(evaluator)
        #expect(fakes.shown.count == 1)
        #expect(fakes.recorded(raised) == [.nearLimit])
        #expect(fakes.recorded(near).isEmpty)
    }

    @Test(
        "BAD.S1-R2 짝: 읽지 못한 판정(읽기 실패·이번 달이 달라 다시 읽다 실패)은 기다리던 창을 그대로 둔다",
        arguments: ReadFailure.allCases
    )
    func failedReadKeepsPending(_ failure: ReadFailure) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(makeServerBudget(.nearLimit, spent: 800_000, percent: 80))
        await evaluator.evaluate(.ledgerChange)
        let alert = try #require(evaluator.pendingAlert)
        let readsBefore = fakes.fetchedMonths.count

        let november = ServerMonth(year: 2026, month: 11)
        switch failure {
        case .fetch:
            fakes.fetch.result = { _ in .failure(FakeError.offline) }
        case .reread:
            // 10월 응답이 "이번 달은 11월"이라 11월로 다시 읽는데, 그 읽기가 실패한다.
            fakes.fetch.result = {
                $0 == october ? .success(makeBudget($0, current: november)) : .failure(FakeError.offline)
            }
        }
        await evaluator.evaluate(.ledgerChange)

        let reads = Array(fakes.fetchedMonths.dropFirst(readsBefore))
        #expect(reads == (failure == .fetch ? [october] : [october, november]))
        #expect(evaluator.pendingAlert == alert)
    }

    @Test(
        "BAD.S1-R3 창이 기다리는 중 reset()·clearRecords() 면 창이 사라지고 세대가 오르며, 옛 창의 markShown 은 기록 없이 false 다",
        arguments: [Change.reset, .clearRecords]
    )
    func resetDropsPending(_ change: Change) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 800_000, percent: 80)
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)
        let alert = try #require(evaluator.pendingAlert)
        let generation = evaluator.resetGeneration

        fakes.apply(change, to: evaluator)

        #expect(evaluator.pendingAlert == nil)
        #expect(evaluator.resetGeneration == generation + 1)
        #expect(!evaluator.markShown(alert))
        #expect(fakes.recorded(near).isEmpty)
    }

    @Test("BAD.S1-R3 창이 기다리는 중 사용자 ID 만 바뀌면(세대 그대로) 옛 창의 markShown 은 기록 없이 false 이고 창을 비운다")
    func switchedAccountRejectsPending() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 800_000, percent: 80)
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)
        let alert = try #require(evaluator.pendingAlert)
        let generation = evaluator.resetGeneration

        fakes.userID = userB

        #expect(!evaluator.markShown(alert))
        #expect(evaluator.pendingAlert == nil)
        #expect(evaluator.resetGeneration == generation)
        #expect(fakes.recorded(near, user: userA).isEmpty)
        #expect(fakes.recorded(near, user: userB).isEmpty)
    }

    @Test(
        "BAD.S1-R3 서버 읽기에서 멈춘 판정은 그 사이 reset()·clearRecords() 면 재개돼도 창을 내지 않는다",
        arguments: [Change.reset, .clearRecords]
    )
    func resetWhileReadingLeavesNoAlert(_ change: Change) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 800_000, percent: 80)
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(near)

        await fakes.evaluate(evaluator, holding: .firstFetch) {
            fakes.apply(change, to: evaluator)
        }

        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(near).isEmpty)
    }

    @Test("BAD.S1-R3 짝: 아무것도 바뀌지 않으면 서버 읽기에서 멈췄다 재개해도 80% 창이 생긴다")
    func unchangedWhileReadingLeavesAlert() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(makeServerBudget(.nearLimit, spent: 800_000, percent: 80))

        await fakes.evaluate(evaluator, holding: .firstFetch)

        #expect(evaluator.pendingAlert == makeWindow(.nearLimit, remaining: 200_000))
    }

    @Test("BAD.S1-R4 창은 판정한 응답의 남은 돈·넘은 돈·남은 날·하루 권장액을 그대로 든다", arguments: WindowCase.allCases)
    func alertCarriesServerValues(_ windowCase: WindowCase) async throws {
        let scenario = makeWindowScenario(windowCase)
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(scenario.below)
        await evaluator.evaluate(.ledgerChange)

        fakes.respond(scenario.judged)
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == scenario.alert)
    }

    @Test("BAD.S1-R5 아래에서 한 번에 넘으면 창은 100% 하나이고, 띄운 뒤에는 임박으로 내려와도·다시 넘어도 그 예산에 창이 없다")
    func jumpingOverShowsHundredOnce() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let exceeded = makeServerBudget(.exceeded, spent: 1_030_000)
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(exceeded)
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == makeWindow(.reached, over: 30000))

        fakes.showPending(evaluator)
        #expect(fakes.recorded(exceeded) == [.nearLimit, .reached])

        fakes.respond(makeServerBudget(.nearLimit, spent: 900_000, percent: 90))
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == nil)
        fakes.respond(makeServerBudget(.exceeded, spent: 1_050_000))
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.shown.count == 1)
    }

    @Test("BAD.S1-R5 아래에서 딱 100% 면 넘은 돈 없는 100% 창 하나다")
    func reachingExactlyShowsHundred() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)

        fakes.respond(makeServerBudget(.reached, spent: 1_000_000, percent: 100))
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == makeWindow(.reached))
    }

    @Test("BAD.S1-R5 짝: 아래에서 임박이면 창은 100% 가 아니라 80% 다")
    func nearLimitShowsEighty() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)

        fakes.respond(makeServerBudget(.nearLimit, spent: 800_000, percent: 80))
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert?.threshold == .nearLimit)
    }
}

// MARK: 넘는 걸 본 기기만 — 처음 확인

/// 따로 적지 않으면 전체 예산 1,000,000 KRW 이고, "확인 표시"는 이 기기가 그 예산을 확인했다는 저장소 표시다.
extension BudgetAlertEvaluatorTests {
    @Test(
        "BAD.S2-R1 처음 확인한 예산이 이미 넘었으면 창 없이 넘은 기준과 확인 표시를 남긴다 — 임박은 80, 넘음·딱은 80·100",
        arguments: [BudgetStatus.nearLimit, .exceeded, .reached]
    )
    func firstConfirmationRecordsWithoutAlert(_ status: BudgetStatus) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let judged = switch status {
        case .nearLimit: makeServerBudget(.nearLimit, spent: 830_000, percent: 83)
        case .reached: makeServerBudget(.reached, spent: 1_000_000, percent: 100)
        default: makeServerBudget(.exceeded, spent: 1_045_000)
        }
        fakes.respond(judged)

        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(judged) == (status == .nearLimit ? [.nearLimit] : [.nearLimit, .reached]))
        #expect(fakes.isConfirmed(judged))
    }

    @Test(
        "BAD.S2-R1 처음 확인한 예산이 기준 아래면 창도 기준 기록도 없이 확인 표시만 남고, 다음 임박 판정은 창 80 이다",
        arguments: [BudgetStatus.inProgress, .none]
    )
    func belowConfirmationThenNearShowsEighty(_ status: BudgetStatus) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let below = status == .none
            ? makeServerBudget(.none, spent: 0)
            : makeServerBudget(.inProgress, spent: 450_000, percent: 45)
        fakes.respond(below)
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(below).isEmpty)
        #expect(fakes.isConfirmed(below))

        fakes.respond(makeServerBudget(.nearLimit, spent: 870_000, percent: 87))
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == makeWindow(.nearLimit, remaining: 130_000))
    }

    @Test(
        "BAD.S2-R1 같은 계정·달에서 전체 금액이나 통화만 바뀐 예산은 따로 확인한다 — 바뀐 예산의 처음 판정이 넘었으면 창이 없다",
        arguments: BudgetChange.allCases
    )
    func changedKeyFirstExceededHasNoAlert(_ change: BudgetChange) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 600_000, percent: 60))
        await evaluator.evaluate(.ledgerChange)
        let changed = switch change {
        case .amount: makeServerBudget(.exceeded, spent: 960_000, amount: 900_000)
        case .currency: makeServerBudget(.exceeded, spent: Decimal(102_000_050) / 100, currency: .usd)
        }
        fakes.respond(changed)

        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(changed) == [.nearLimit, .reached])
    }

    @Test("BAD.S2-R1 바뀐 예산도 기준 아래로 확인한 뒤 넘으면 창 100 이다", arguments: BudgetChange.allCases)
    func changedKeyBelowThenExceededShowsHundred(_ change: BudgetChange) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 600_000, percent: 60))
        await evaluator.evaluate(.ledgerChange)
        let changedBelow: MonthlyBudget
        let changedOver: MonthlyBudget
        switch change {
        case .amount:
            changedBelow = makeServerBudget(.inProgress, spent: 540_000, percent: 60, amount: 900_000)
            changedOver = makeServerBudget(.exceeded, spent: 925_000, amount: 900_000)
        case .currency:
            changedBelow = makeServerBudget(.inProgress, spent: Decimal(55_000_025) / 100, percent: 55, currency: .usd)
            changedOver = makeServerBudget(.exceeded, spent: Decimal(101_234_567) / 100, currency: .usd)
        }
        fakes.respond(changedBelow)
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == nil)

        fakes.respond(changedOver)
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert?.threshold == .reached)
        #expect(evaluator.pendingAlert?.overAmount == changedOver.total?.overAmount)
    }

    @Test("BAD.S2-R1 창 80 이 기다리는 중 바뀐 예산의 처음 판정이 넘었으면 창이 사라진다")
    func changedKeyFirstConfirmationDropsPending() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 810_000, percent: 81)
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)
        let alert = try #require(evaluator.pendingAlert)
        let lowered = makeServerBudget(.exceeded, spent: 860_000, amount: 700_000)
        fakes.respond(lowered)

        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == nil)
        #expect(!evaluator.markShown(alert))
        #expect(fakes.recorded(lowered) == [.nearLimit, .reached])
        #expect(fakes.recorded(near).isEmpty)
    }

    @Test(
        "BAD.S2-R1 서버 읽기에서 멈춘 판정은 그 사이 reset()·clearRecords() 면 확인 표시를 남기지 않는다 — 그 뒤 임박은 처음 확인이다",
        arguments: [Change.reset, .clearRecords]
    )
    func resetWhileReadingLeavesNoConfirmation(_ change: Change) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let below = makeServerBudget(.inProgress, spent: 350_000, percent: 35)
        fakes.respond(below)

        await fakes.evaluate(evaluator, holding: .firstFetch) {
            fakes.apply(change, to: evaluator)
        }
        #expect(!fakes.isConfirmed(below))

        let near = makeServerBudget(.nearLimit, spent: 880_000, percent: 88)
        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(near) == [.nearLimit])
    }

    @Test("BAD.S2-R1 확인은 계정마다다 — 사용자 A 가 아래로 확인한 같은 달·통화·금액 예산을 사용자 B 가 처음 넘음으로 보면 창이 없다")
    func confirmationIsPerAccount() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 420_000, percent: 42))
        await evaluator.evaluate(.ledgerChange)
        let exceeded = makeServerBudget(.exceeded, spent: 1_070_000)

        fakes.userID = userB
        fakes.respond(exceeded)
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(exceeded, user: userB) == [.nearLimit, .reached])
        #expect(fakes.isConfirmed(exceeded, user: userB))

        // 짝: 아래로 확인한 사용자 A 에게는 같은 응답이 창 100 이다.
        fakes.userID = userA
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == makeWindow(.reached, over: 70000))
    }

    @Test("BAD.S2-R1 확인은 달마다다 — 이번 달을 아래로 확인한 금액과 같은 다음 달 예산의 처음 넘음은 창이 없다")
    func confirmationIsPerMonth() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.fetch.result = { .success(makeBudget($0, status: .inProgress, amount: 1_300_000)) }
        await evaluator.evaluate(.ledgerChange)
        #expect(fakes.isConfirmed(makeBudget(status: .inProgress, amount: 1_300_000)))

        // 서버의 이번 달이 11월로 넘어갔다 — 10월 응답이 "이번 달은 11월"이라 11월로 다시 읽는다.
        let novemberOver = makeBudget(november, current: november, status: .exceeded, amount: 1_300_000)
        fakes.fetch.result = {
            .success($0 == november ? novemberOver : makeBudget($0, current: november, amount: 1_300_000))
        }
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.fetchedMonths == [october, october, november])
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(novemberOver) == [.nearLimit, .reached])
    }

    @Test("BAD.S2-R1 짝: 이번 달 예산 없음 응답은 확인 표시를 남기지 않는다 — 그 뒤 처음 온 임박 응답은 처음 확인이라 창 없이 80 을 기록한다")
    func notSetLeavesNoConfirmation() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeNotSetBudget())
        await evaluator.evaluate(.ledgerChange)

        let near = makeServerBudget(.nearLimit, spent: 840_000, percent: 84)
        fakes.respond(near)
        await evaluator.evaluate(.foreground)

        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(near) == [.nearLimit])
    }

    @Test("BAD.S2-R1 확인 표시와 기준 기록은 저장소 clear() 한 번에 함께 사라진다 — 그 뒤 같은 예산의 임박은 처음 확인이다")
    func storeClearRemovesConfirmation() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let near = makeServerBudget(.nearLimit, spent: 900_000, percent: 90)
        fakes.respond(makeServerBudget(.inProgress, spent: 550_000, percent: 55))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)
        fakes.showPending(evaluator)
        #expect(fakes.recorded(near) == [.nearLimit])
        #expect(fakes.isConfirmed(near))

        // 로그아웃 복구·purge 가 부르는 길이다 — 판정기 없이 저장소만 비운다.
        fakes.records.clear()

        #expect(fakes.recorded(near).isEmpty)
        #expect(!fakes.isConfirmed(near))
        let relaunched = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.nearLimit, spent: 920_000, percent: 92))
        await relaunched.evaluate(.ledgerChange)
        #expect(relaunched.pendingAlert == nil)
    }
}

// MARK: 이번 달 예산 없음 — 원장 변경 판정 건너뜀

extension BudgetAlertEvaluatorTests {
    @Test("BAD.S2-R2 이번 달 예산이 없다고 확인되면 원장 변경 판정은 서버를 부르지 않는다")
    func noBudgetSkipsLedgerChanges() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeNotSetBudget())
        await evaluator.evaluate(.ledgerChange)
        #expect(fakes.log == [.probe, .fetch(october)])

        await evaluator.evaluate(.ledgerChange)
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.log == [.probe, .fetch(october)])
    }

    @Test("BAD.S2-R2 짝: 예산이 있는 응답 뒤 원장 변경 판정은 늘 읽는다")
    func budgetPresentLedgerChangesRead() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 300_000, percent: 30))

        await evaluator.evaluate(.ledgerChange)
        await evaluator.evaluate(.ledgerChange)
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.fetchedMonths == [october, october, october])
    }

    @Test("BAD.S2-R2 앱이 앞으로 오면 예산 없음을 기억하는 중에도 읽고, 예산이 있으면 그 뒤 원장 변경 판정이 다시 읽는다")
    func foregroundReadsDespiteNoBudget() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeNotSetBudget())
        await evaluator.evaluate(.ledgerChange)
        let near = makeServerBudget(.nearLimit, spent: 815_000, percent: 81)
        fakes.respond(near)

        await evaluator.evaluate(.foreground)
        #expect(fakes.fetchedMonths == [october, october])
        // 다른 기기가 만든 예산이라 처음 확인이다 — 창 없이 80 을 기록한다.
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(near) == [.nearLimit])

        await evaluator.evaluate(.ledgerChange)
        #expect(fakes.fetchedMonths == [october, october, october])
    }

    @Test("BAD.S2-R2 짝: 앱이 앞으로 와 읽기에 실패하면 예산 없음 기억은 그대로다")
    func failedForegroundKeepsNoBudget() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeNotSetBudget())
        await evaluator.evaluate(.ledgerChange)

        fakes.fetch.result = { _ in .failure(FakeError.offline) }
        await evaluator.evaluate(.foreground)
        #expect(fakes.fetchedMonths == [october, october])

        fakes.respond(makeServerBudget(.nearLimit, spent: 805_000, percent: 80))
        await evaluator.evaluate(.ledgerChange)
        #expect(fakes.fetchedMonths == [october, october])
    }

    @Test("BAD.S2-R2 예산 없음을 본 뒤 이 기기에서 예산을 저장한 응답을 받으면 원장 변경 판정이 다시 읽는다")
    func savedBudgetEndsNoBudgetSkip() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeNotSetBudget())
        await evaluator.evaluate(.ledgerChange)

        let saved = makeServerBudget(.none, spent: 0, amount: 700_000)
        evaluator.observeSavedBudget(saved, token: evaluator.savedBudgetToken())
        #expect(fakes.fetchedMonths == [october])
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.fetchedMonths == [october, october])
    }

    @Test("BAD.S2-R2 이 기기에서 이번 달 예산을 삭제한 응답(예산 없음)을 받으면 원장 변경 판정은 서버를 부르지 않는다")
    func deletedBudgetStartsNoBudgetSkip() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 250_000, percent: 25))
        await evaluator.evaluate(.ledgerChange)

        evaluator.observeSavedBudget(makeNotSetBudget(), token: evaluator.savedBudgetToken())
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.fetchedMonths == [october])
    }

    @Test(
        "BAD.S2-R2 예산 없음을 본 뒤 reset()·clearRecords() 면 원장 변경 판정이 다시 읽는다",
        arguments: [Change.reset, .clearRecords]
    )
    func resetEndsNoBudgetSkip(_ change: Change) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeNotSetBudget())
        await evaluator.evaluate(.ledgerChange)

        fakes.apply(change, to: evaluator)
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.fetchedMonths == [october, october])
    }

    @Test("BAD.S2-R2 예산 없음을 본 뒤 원장 변경 신호(구독 경로)도 서버를 부르지 않는다")
    func noBudgetSkipsLedgerSignals() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeNotSetBudget())
        await evaluator.evaluate(.ledgerChange)
        let (events, continuation) = AsyncStream<Void>.makeStream()
        continuation.yield(())
        continuation.yield(())
        continuation.finish()

        await evaluator.observeLedgerChanges(events)

        #expect(fakes.log == [.probe, .fetch(october)])
    }

    @Test(
        "BAD.S2-R2 판정 중에 기다린 요청에 앱이 앞으로 옴이 섞이면 뒤따르는 판정은 예산 없음 기억을 무시하고 읽는다",
        arguments: Queued.allCases
    )
    func queuedForegroundReadsDespiteNoBudget(_ queued: Queued) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeNotSetBudget())
        fakes.fetch.hold()
        let first = fakes.startEvaluating(evaluator)
        await waitUntil { fakes.fetch.hasHeld }
        let waiting = queued.triggers.map { fakes.startEvaluating(evaluator, $0) }
        await settleMainActor()

        fakes.fetch.release()
        await first.value
        for task in waiting {
            await task.value
        }

        // 앞 판정이 예산 없음을 본다. 기다린 요청에 foreground 가 있으면 뒤따르는 판정이 한 번 더 읽는다.
        #expect(fakes.fetchedMonths.count == (queued == .ledgerChangesOnly ? 1 : 2))
    }
}

// MARK: 이 기기의 저장 응답

extension BudgetAlertEvaluatorTests {
    @Test("BAD.S2-R3 저장 응답은 서버를 부르지 않는 확인이다 — 전체 금액을 줄여 넘은 응답은 창 없이 80·100 을 기록한다")
    func savedLoweredBudgetRecordsWithoutAlert() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 640_000, percent: 64))
        await evaluator.evaluate(.ledgerChange)
        let lowered = makeServerBudget(.exceeded, spent: 640_000, amount: 600_000)

        evaluator.observeSavedBudget(lowered, token: evaluator.savedBudgetToken())

        #expect(fakes.log == [.probe, .fetch(october)])
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(lowered) == [.nearLimit, .reached])
    }

    @Test("BAD.S2-R3 기준 아래인 저장 응답은 확인 표시만 남기고, 다음 판정이 넘으면 창 100 이다")
    func savedBelowThenExceededShowsHundred() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 640_000, percent: 64))
        await evaluator.evaluate(.ledgerChange)
        let raised = makeServerBudget(.inProgress, spent: 640_000, percent: 53, amount: 1_200_000)

        evaluator.observeSavedBudget(raised, token: evaluator.savedBudgetToken())
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(raised).isEmpty)
        #expect(fakes.isConfirmed(raised))

        fakes.respond(makeServerBudget(.exceeded, spent: 1_235_000, amount: 1_200_000))
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == makeWindow(.reached, over: 35000))
    }

    @Test("BAD.S2-R3 창 80 이 기다리는 중 바뀐 예산의 저장 응답을 받으면 창이 사라진다")
    func savedChangedBudgetDropsPending() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(makeServerBudget(.nearLimit, spent: 820_000, percent: 82))
        await evaluator.evaluate(.ledgerChange)
        let alert = try #require(evaluator.pendingAlert)
        let raised = makeServerBudget(.inProgress, spent: 820_000, percent: 54, amount: 1_500_000)

        evaluator.observeSavedBudget(raised, token: evaluator.savedBudgetToken())

        #expect(evaluator.pendingAlert == nil)
        #expect(!evaluator.markShown(alert))
        #expect(fakes.isConfirmed(raised))
    }

    @Test("BAD.S2-R3 창 80 이 기다리는 중 같은 예산의 임박 저장 응답을 받으면 창 80 은 그대로이고 값은 저장 응답 값이다")
    func savedSameBudgetKeepsPendingWithNewValues() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(makeServerBudget(.nearLimit, spent: 800_000, percent: 80))
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == makeWindow(.nearLimit, remaining: 200_000))
        let daily = DailyAllowance(amount: 15555, isExceeded: false)
        let saved = makeServerBudget(.nearLimit, spent: 860_000, percent: 86, dailyAllowance: daily)

        evaluator.observeSavedBudget(saved, token: evaluator.savedBudgetToken())

        #expect(evaluator.pendingAlert == makeWindow(.nearLimit, remaining: 140_000, dailyAllowance: daily))
        #expect(fakes.fetchedMonths == [october, october])
    }

    @Test("BAD.S2-R3 서버 읽기에서 멈춘 판정은 그 사이 저장 응답을 받으면 결과를 버린다 — 옛 예산의 창도 기록도 없다")
    func savedResponseDropsInFlightEvaluation() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let oldOver = makeServerBudget(.exceeded, spent: 1_080_000)
        fakes.respond(makeServerBudget(.inProgress, spent: 700_000, percent: 70))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(oldOver)
        let raised = makeServerBudget(.inProgress, spent: 1_080_000, percent: 72, amount: 1_500_000)

        await fakes.evaluate(evaluator, holding: .firstFetch) {
            evaluator.observeSavedBudget(raised, token: evaluator.savedBudgetToken())
        }

        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(oldOver).isEmpty)
        #expect(fakes.isConfirmed(raised))
    }

    @Test("BAD.S2-R3 짝: 그 사이 받은 저장 응답이 거절되면(다른 달) 멈췄던 판정은 그대로 창 100 을 낸다")
    func rejectedSavedResponseKeepsInFlightEvaluation() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 700_000, percent: 70))
        await evaluator.evaluate(.ledgerChange)
        fakes.respond(makeServerBudget(.exceeded, spent: 1_080_000))
        let nextMonth = makeBudget(november, current: october, status: .inProgress, amount: 1_500_000)

        await fakes.evaluate(evaluator, holding: .firstFetch) {
            evaluator.observeSavedBudget(nextMonth, token: evaluator.savedBudgetToken())
        }

        #expect(evaluator.pendingAlert == makeWindow(.reached, over: 80000))
    }

    @Test("BAD.S2-R3 서버 읽기에서 멈춘 판정(예산 없음 응답)은 그 사이 예산이 있는 저장 응답을 받으면 예산 없음을 기억하지 않는다")
    func savedResponseKeepsNoBudgetOff() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeNotSetBudget())
        let saved = makeServerBudget(.none, spent: 0, amount: 450_000)

        await fakes.evaluate(evaluator, holding: .firstFetch) {
            evaluator.observeSavedBudget(saved, token: evaluator.savedBudgetToken())
        }
        let readsBefore = fakes.fetchedMonths.count
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.fetchedMonths.count - readsBefore == 1)
    }

    @Test("BAD.S2-R3 예산 없음을 본 뒤 기준 아래인 새 예산을 저장하면 그 저장이 확인이라 다음 임박 판정은 창 80 이다")
    func savedNewBudgetCountsAsConfirmation() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeNotSetBudget())
        await evaluator.evaluate(.ledgerChange)

        let saved = makeServerBudget(.inProgress, spent: 280_000, percent: 35, amount: 800_000)
        evaluator.observeSavedBudget(saved, token: evaluator.savedBudgetToken())
        fakes.respond(makeServerBudget(.nearLimit, spent: 690_000, percent: 86, amount: 800_000))
        await evaluator.evaluate(.ledgerChange)

        #expect(evaluator.pendingAlert == makeWindow(.nearLimit, remaining: 110_000))
    }

    @Test("BAD.S2-R3 reset() 뒤 받은 표의 저장 응답은 아는 달을 맞춘다 — 다음 판정은 서버 시각을 묻지 않고 그 달로 읽는다")
    func savedResponseSetsKnownMonth() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate(.ledgerChange)
        evaluator.reset()
        let token = evaluator.savedBudgetToken()
        fakes.fetch.result = { .success(makeBudget($0, current: november, status: .inProgress, amount: 950_000)) }

        evaluator.observeSavedBudget(
            makeBudget(november, current: november, status: .inProgress, amount: 950_000),
            token: token
        )
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.log == [.probe, .fetch(october), .fetch(november)])
    }

    @Test(
        "BAD.S2-R3 짝: 거절되는 저장 응답은 기다리던 창·예산 없음 기억·아는 달을 그대로 두고 기록하지 않는다",
        arguments: Rejected.allCases, RejectionState.allCases
    )
    func rejectedSavedResponseChangesNothing(_ rejected: Rejected, _ state: RejectionState) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let token = fakes.takeToken(rejected, from: evaluator)
        let saved = makeRejectedSave(rejected)
        #expect(BudgetTabViewModel.isWellFormed(saved) == (rejected != .malformed))
        switch state {
        case .pendingAlert:
            fakes.respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
            await evaluator.evaluate(.ledgerChange)
            fakes.respond(makeServerBudget(.nearLimit, spent: 830_000, percent: 83))
            await evaluator.evaluate(.ledgerChange)
        case .noBudget:
            fakes.respond(makeNotSetBudget())
            await evaluator.evaluate(.ledgerChange)
        }
        let alert = evaluator.pendingAlert
        #expect((alert != nil) == (state == .pendingAlert))
        let logBefore = fakes.log.count

        evaluator.observeSavedBudget(saved, token: token)

        #expect(evaluator.pendingAlert == alert)
        for user in [userA, userB] {
            #expect(fakes.recorded(saved, user: user).isEmpty)
            #expect(!fakes.isConfirmed(saved, user: user))
        }
        // 예산 없음 기억이면 원장 변경 판정이 읽지 않는다. 앱이 앞으로 오면 아는 달(10월)로 서버 시각 없이 읽는다.
        await evaluator.evaluate(.ledgerChange)
        if state == .noBudget {
            #expect(fakes.log.count == logBefore)
            await evaluator.evaluate(.foreground)
        }
        #expect(Array(fakes.log.dropFirst(logBefore)) == [.fetch(october)])
        #expect(evaluator.pendingAlert == alert)
    }
}

// MARK: 루트 — 띄우기 · 닫기

/// 루트가 부르는 `BudgetAlertPresentation`(`presentLikeRoot`). 따로 적지 않으면 전체 예산 1,000,000 KRW 이고,
/// 창 80 은 같은 예산의 "아래" 판정 뒤 임박 판정이 낸 것이다(`waitNearLimit`).
extension BudgetAlertEvaluatorTests {
    @Test("BAD.S4-R2 띄울 수 있고 창 80 이 기다리면 80 을 기록하고 알림창 오버레이를 올린다")
    func presentsWaitingAlert() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let overlays = RootOverlayModel()
        let near = await fakes.waitNearLimit(evaluator)

        #expect(presentLikeRoot(evaluator, overlays))

        #expect(overlays.isPresented(.budgetAlert))
        #expect(fakes.recorded(near) == [.nearLimit])
        #expect(evaluator.pendingAlert == nil)
    }

    @Test("BAD.S4-R2 띄울 수 없으면 기록·오버레이 없이 창을 그대로 두고, 조건이 맞아진 다음 부름에서 올린다")
    func blockedGateKeepsAlertUntilClear() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let overlays = RootOverlayModel()
        let near = await fakes.waitNearLimit(evaluator)
        let alert = evaluator.pendingAlert

        #expect(!presentLikeRoot(evaluator, overlays, blocked: .entryOpen))
        #expect(overlays.presentation == nil)
        #expect(fakes.recorded(near).isEmpty)
        #expect(evaluator.pendingAlert == alert)

        #expect(presentLikeRoot(evaluator, overlays))
        #expect(overlays.isPresented(.budgetAlert))
        #expect(fakes.recorded(near) == [.nearLimit])
    }

    @Test("BAD.S4-R2 다른 오버레이(달 피커)가 떠 있으면 올리지 않고 그 오버레이·창을 그대로 둔다")
    func otherOverlayIsKept() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let overlays = RootOverlayModel()
        let near = await fakes.waitNearLimit(evaluator)
        let alert = evaluator.pendingAlert
        overlays.present(.ledgerMonthPicker, content: EmptyView())

        #expect(!presentLikeRoot(evaluator, overlays))

        #expect(overlays.isPresented(.ledgerMonthPicker))
        #expect(fakes.recorded(near).isEmpty)
        #expect(evaluator.pendingAlert == alert)
    }

    @Test("BAD.S4-R2 기다리는 창이 없으면 올리지 않는다 — 판정 전 · 짝: 판정 뒤 reset() 으로 창이 빈 때")
    func noPendingAlertPresentsNothing() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let overlays = RootOverlayModel()
        #expect(!presentLikeRoot(evaluator, overlays))
        #expect(overlays.presentation == nil)

        let near = await fakes.waitNearLimit(evaluator)
        evaluator.reset()

        #expect(!presentLikeRoot(evaluator, overlays))
        #expect(overlays.presentation == nil)
        #expect(fakes.recorded(near).isEmpty)
    }

    @Test("BAD.S4-R2 짝: 띄운 창을 닫으면 오버레이가 없고, 새 창(100)이 기다리면 다음 부름에서 올린다")
    func nextAlertIsPresentedAfterDismiss() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let overlays = RootOverlayModel()
        let near = await fakes.waitNearLimit(evaluator)
        #expect(presentLikeRoot(evaluator, overlays))

        overlays.dismiss(.budgetAlert)
        #expect(overlays.presentation == nil)
        #expect(!presentLikeRoot(evaluator, overlays))

        fakes.respond(makeServerBudget(.exceeded, spent: 1_030_000))
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == makeWindow(.reached, over: 30000))

        #expect(presentLikeRoot(evaluator, overlays))
        #expect(overlays.isPresented(.budgetAlert))
        #expect(fakes.recorded(near) == [.nearLimit, .reached])
    }

    @Test(
        "BAD.S4-R2 띄운 뒤 reset()·clearRecords() 로 세대가 바뀌면 dismissAfterReset 이 알림창을 닫는다",
        arguments: [Change.reset, .clearRecords]
    )
    func resetDismissesPresentedAlert(_ change: Change) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let overlays = RootOverlayModel()
        await fakes.waitNearLimit(evaluator)
        #expect(presentLikeRoot(evaluator, overlays))
        let generation = evaluator.resetGeneration

        fakes.apply(change, to: evaluator)
        #expect(evaluator.resetGeneration != generation)
        BudgetAlertPresentation.dismissAfterReset(overlays)

        #expect(overlays.presentation == nil)
    }

    @Test("BAD.S4-R2 짝: 달 피커가 떠 있을 때 dismissAfterReset 은 달 피커를 그대로 둔다")
    func resetKeepsOtherOverlay() {
        let overlays = RootOverlayModel()
        overlays.present(.ledgerMonthPicker, content: EmptyView())

        BudgetAlertPresentation.dismissAfterReset(overlays)

        #expect(overlays.isPresented(.ledgerMonthPicker))
    }
}

// MARK: 루트 — 저장·삭제 응답 넘기기

/// 예산 편집이 끝나면 루트가 결과를 `BudgetAlertPresentation.forward` 로 넘긴다. 표는 쓰기 직전에 받은 것이다.
extension BudgetAlertEvaluatorTests {
    @Test("BAD.S4-R3 저장 응답을 지금 표와 넘기면 판정기가 그 예산을 확인한다 — 그 뒤 임박 판정은 창 80 이다")
    func forwardsSavedResponse() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let saved = makeServerBudget(.inProgress, spent: 640_000, percent: 53, amount: 1_200_000)

        BudgetAlertPresentation.forward(
            .saved(saved, writeToken: 0),
            token: evaluator.savedBudgetToken(),
            to: evaluator
        )
        #expect(fakes.isConfirmed(saved))

        fakes.respond(makeServerBudget(.nearLimit, spent: 990_000, percent: 82, amount: 1_200_000))
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == makeWindow(.nearLimit, remaining: 210_000))
    }

    @Test("BAD.S4-R3 삭제 응답(예산 없음)을 넘기면 판정기가 예산 없음을 기억한다 — 원장 변경 판정이 읽지 않는다")
    func forwardsDeletedResponse() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.respond(makeServerBudget(.inProgress, spent: 250_000, percent: 25))
        await evaluator.evaluate(.ledgerChange)
        let logBefore = fakes.log.count

        BudgetAlertPresentation.forward(
            .deleted(makeNotSetBudget(), writeToken: 0),
            token: evaluator.savedBudgetToken(),
            to: evaluator
        )
        await evaluator.evaluate(.ledgerChange)

        #expect(fakes.log.count == logBefore)
    }

    @Test("BAD.S4-R3 짝: 닫기·다시 불러오기는 넘기지 않는다 — 기다리던 창 그대로이고 원장 변경 판정은 읽는다")
    func dismissedAndReloadAreNotForwarded() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await fakes.waitNearLimit(evaluator)
        let alert = evaluator.pendingAlert
        let token = evaluator.savedBudgetToken()
        let logBefore = fakes.log.count

        BudgetAlertPresentation.forward(.dismissed(october), token: token, to: evaluator)
        BudgetAlertPresentation.forward(.dismissed(nil), token: token, to: evaluator)
        BudgetAlertPresentation.forward(.reloadRequired(october, .categoryDeletedReloaded), token: token, to: evaluator)
        #expect(evaluator.pendingAlert == alert)
        #expect(fakes.log.count == logBefore)

        await evaluator.evaluate(.ledgerChange)
        #expect(Array(fakes.log.dropFirst(logBefore)) == [.fetch(october)])
        #expect(evaluator.pendingAlert == alert)
    }

    @Test("BAD.S4-R3 짝: 표 없이 넘긴 저장·삭제 응답은 판정기를 바꾸지 않는다 — 저장한 예산의 임박은 처음 확인이라 창이 없다")
    func responsesWithoutTokenAreIgnored() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let saved = makeServerBudget(.inProgress, spent: 640_000, percent: 53, amount: 1_200_000)
        let near = makeServerBudget(.nearLimit, spent: 990_000, percent: 82, amount: 1_200_000)

        BudgetAlertPresentation.forward(.saved(saved, writeToken: 0), token: nil, to: evaluator)
        BudgetAlertPresentation.forward(.deleted(makeNotSetBudget(), writeToken: 0), token: nil, to: evaluator)
        #expect(!fakes.isConfirmed(saved))

        fakes.respond(near)
        await evaluator.evaluate(.ledgerChange)
        #expect(fakes.log == [.probe, .fetch(october)])
        #expect(evaluator.pendingAlert == nil)
        #expect(fakes.recorded(near) == [.nearLimit])
    }

    @Test("BAD.S4-R3 짝: reset() 전에 받은 표로 넘긴 저장 응답은 버린다 — 저장한 예산의 임박은 처음 확인이라 창이 없다")
    func tokenFromBeforeResetIsIgnored() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        let saved = makeServerBudget(.inProgress, spent: 640_000, percent: 53, amount: 1_200_000)
        let token = evaluator.savedBudgetToken()
        evaluator.reset()

        BudgetAlertPresentation.forward(.saved(saved, writeToken: 0), token: token, to: evaluator)
        #expect(!fakes.isConfirmed(saved))

        fakes.respond(makeServerBudget(.nearLimit, spent: 990_000, percent: 82, amount: 1_200_000))
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == nil)
    }
}

// MARK: 인자

extension BudgetAlertEvaluatorTests {
    /// 판정이 기다리는 자리. `useMonthChangeScenario()` 의 판정에는 세 곳이 모두 있다.
    enum Point: CaseIterable {
        case probe, firstFetch, rereadFetch
    }

    /// 기다리는 사이에 바뀌는 것.
    enum Change {
        case switchAccount, reset, clearRecords
    }

    /// 아는 달을 갱신하지 않는 판정.
    enum Discard: CaseIterable {
        case firstFetchFails, rereadFails, accountSwitchedDuringReread
    }

    /// 보낼 것이 없는 판정 — 이번 달 예산 없음 · 진행률 읽기 실패 · 신원 없음.
    enum NoAlert: CaseIterable {
        case notSet, fetchFails, noIdentity
    }

    /// 기록 키가 달라지는 예산 변경.
    enum BudgetChange: CaseIterable {
        case amount, currency
    }

    /// 띄울 것이 없는 최신 판정 — 기준 아래로 내려감 · 이번 달 예산 없음.
    enum Dropped: CaseIterable {
        case below, notSet
    }

    /// 읽지 못한 판정 — 읽기 실패 · 응답의 이번 달이 달라 다시 읽다 실패.
    enum ReadFailure: CaseIterable {
        case fetch, reread
    }

    /// 창 내용 갈래(`makeWindowScenario`).
    enum WindowCase: CaseIterable {
        case nearLimit, exceeded, reached, usd, noDailyAllowance
    }

    /// 앞 판정이 도는 중에 기다리는 요청들.
    enum Queued: CaseIterable {
        case foregroundFirst, foregroundLast, ledgerChangesOnly

        var triggers: [BudgetAlertTrigger] {
            switch self {
            case .foregroundFirst: [.foreground, .ledgerChange]
            case .foregroundLast: [.ledgerChange, .foreground]
            case .ledgerChangesOnly: [.ledgerChange, .ledgerChange]
            }
        }
    }

    /// 거절되는 저장 응답 — 표(신원 없음·`reset()` 전·`clearRecords()` 전·다른 사용자) · 계약 검사 · 다른 달.
    enum Rejected: CaseIterable {
        case noIdentity, beforeReset, beforeClearRecords, otherUser, malformed, otherMonth
    }

    /// 거절된 저장 응답을 받을 때의 상태 — 창 80 기다림 · 예산 없음 기억. 둘 다 아는 달(10월)이 있다.
    enum RejectionState: CaseIterable {
        case pendingAlert, noBudget
    }
}

// MARK: 가짜

private let userA = UUID()
private let userB = UUID()

private enum FakeError: Error, Equatable {
    case offline
}

/// 응답을 붙잡을 수 있는 가짜 입력. `hold()` 는 다음 호출을, `hold(skipping: 1)` 은 그다음 호출을 붙잡고,
/// 테스트가 `release` 로 시점을 정한다.
@MainActor
private final class FakeCall<Args, Value: Sendable> {
    var result: (Args) -> Result<Value, any Error>
    private var callCount = 0
    private var holding: Set<Int> = []
    private var held: [Int: (args: Args, continuation: CheckedContinuation<Value, any Error>)] = [:]

    init(_ result: @escaping (Args) -> Result<Value, any Error>) {
        self.result = result
    }

    var hasHeld: Bool {
        !held.isEmpty
    }

    func hold(skipping count: Int = 0) {
        holding.insert(callCount + count)
    }

    func call(_ args: Args) async throws -> Value {
        let index = callCount
        callCount += 1
        guard holding.contains(index) else {
            return try result(args).get()
        }
        return try await withCheckedThrowingContinuation { held[index] = (args, $0) }
    }

    /// 붙잡은 호출에 답한다. `override` 가 없으면 지금의 `result` 로 답한다.
    func release(with override: Result<Value, any Error>? = nil) {
        let entries = held
        held = [:]
        for entry in entries.values {
            entry.continuation.resume(with: override ?? result(entry.args))
        }
    }
}

/// 판정기가 받는 입력 전부. 호출은 `log` 한 기록에 순서대로 남는다.
@MainActor
private final class EvaluatorFakes {
    enum Event: Equatable {
        case probe
        case fetch(ServerMonth)
    }

    var userID: UUID? = userA

    let probe = FakeCall<Void, ServerMonth> { _ in .success(october) }
    let fetch = FakeCall<ServerMonth, MonthlyBudget> { .success(makeBudget($0)) }
    let records: BudgetAlertRecordStore
    private(set) var log: [Event] = []
    /// `showPending` 이 띄운 창(`markShown` 이 받아 준 것만).
    private(set) var shown: [BudgetAlert] = []
    /// `startEvaluating` 으로 띄운 판정이 돌아온 순간의 읽기 횟수.
    private(set) var returnedAfterFetches: [Int] = []
    private let suiteName: String

    init() throws {
        let suiteName = "woni_appTests.BudgetAlertEvaluatorTests.\(UUID().uuidString)"
        self.suiteName = suiteName
        records = try BudgetAlertRecordStore(userDefaults: #require(UserDefaults(suiteName: suiteName)))
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func makeEvaluator() -> BudgetAlertEvaluator {
        BudgetAlertEvaluator(
            currentUserID: { self.userID },
            probeServerMonth: {
                self.log.append(.probe)
                return try await self.probe.call(())
            },
            fetch: { year, month in
                let target = ServerMonth(year: year, month: month)
                self.log.append(.fetch(target))
                return try await self.fetch.call(target)
            },
            records: records
        )
    }

    /// 루트가 창을 띄운 것처럼 기다리던 창으로 `markShown` 을 부른다. 받아 주면 그 창을 `shown` 에 남기고 돌려준다.
    @discardableResult
    func showPending(_ evaluator: BudgetAlertEvaluator) -> BudgetAlert? {
        guard let alert = evaluator.pendingAlert, evaluator.markShown(alert) else {
            return nil
        }
        shown.append(alert)
        return alert
    }

    /// 판정한 뒤 창이 있으면 바로 띄운다 — 막는 창이 없는 루트.
    func evaluateAndShow(_ evaluator: BudgetAlertEvaluator) async {
        await evaluator.evaluate(.ledgerChange)
        showPending(evaluator)
    }

    /// 다음 판정부터 읽기가 이 응답을 준다.
    func respond(_ budget: MonthlyBudget) {
        fetch.result = { _ in .success(budget) }
    }

    /// 같은 저장소를 쓰는 앞 실행의 판정기가 `below` 를 한 번 판정해 둔다 — 이 기기가 그 예산을 기준 아래로 확인한
    /// 상태다(step 2 "넘는 걸 본 기기만"). 지금 판정기의 아는 달은 그대로이고, 서버 호출은 `log` 에 남기지 않는다.
    func confirmBelow(_ below: MonthlyBudget) async {
        let earlier = BudgetAlertEvaluator(
            currentUserID: { self.userID },
            probeServerMonth: { ServerMonth(year: below.currentYear, month: below.currentMonth) },
            fetch: { _, _ in below },
            records: records
        )
        await earlier.evaluate(.ledgerChange)
        #expect(earlier.pendingAlert == nil)
    }
}

extension EvaluatorFakes {
    var probeCount: Int {
        log.filter { $0 == .probe }.count
    }

    var fetchedMonths: [ServerMonth] {
        log.compactMap { event in
            guard case let .fetch(month) = event else {
                return nil
            }
            return month
        }
    }

    /// 그 응답·계정으로 기록된 기준들.
    func recorded(_ budget: MonthlyBudget, user: UUID = userA) -> [BudgetAlertThreshold] {
        BudgetAlertThreshold.allCases.filter { threshold in
            BudgetAlertDecision.recordKey(userID: user, budget: budget, threshold: threshold)
                .map(records.contains) ?? false
        }
    }

    /// 이 기기가 그 응답·계정의 예산을 확인했다는 표시가 저장소에 있는가.
    func isConfirmed(_ budget: MonthlyBudget, user: UUID = userA) -> Bool {
        BudgetAlertDecision.confirmationKey(userID: user, budget: budget).map(records.contains) ?? false
    }

    /// 같은 예산(1,000,000)의 "아래" 판정 뒤 임박 판정 — 창 80 이 기다린다. 임박 응답을 돌려준다.
    @discardableResult
    func waitNearLimit(_ evaluator: BudgetAlertEvaluator) async -> MonthlyBudget {
        respond(makeServerBudget(.inProgress, spent: 500_000, percent: 50))
        await evaluator.evaluate(.ledgerChange)
        let near = makeServerBudget(.nearLimit, spent: 800_000, percent: 80)
        respond(near)
        await evaluator.evaluate(.ledgerChange)
        #expect(evaluator.pendingAlert == makeWindow(.nearLimit, remaining: 200_000))
        return near
    }

    /// 서버 시각은 9월이고 9월 응답이 "이번 달은 10월"이라 10월로 한 번 더 읽는 판정 — 기다리는 자리 세 곳이 모두 있다.
    func useMonthChangeScenario() {
        probe.result = { _ in .success(september) }
        fetch.result = { .success(makeBudget($0, status: $0 == october ? .nearLimit : .inProgress)) }
    }

    /// `point` 에서 응답을 붙잡고, 판정이 거기 닿으면 `change` 를 적용한 뒤 푼다(`failure` 가 있으면 그 오류로).
    func evaluate(
        _ evaluator: BudgetAlertEvaluator,
        holding point: BudgetAlertEvaluatorTests.Point,
        failing failure: (any Error)? = nil,
        during change: () -> Void = {}
    ) async {
        let gate = gate(point)
        gate.hold()
        let task = Task { await evaluator.evaluate(.ledgerChange) }
        await waitUntil(gate.isHeld)
        change()
        gate.release(failure)
        await task.value
    }

    /// 거절될 표를 받는다 — 신원이 없을 때·다른 사용자일 때·`reset()`·`clearRecords()` 전에 받은 표. 계약 검사·다른 달
    /// 갈래는 지금 표다. 돌아올 때 사용자는 A 다.
    func takeToken(
        _ rejected: BudgetAlertEvaluatorTests.Rejected,
        from evaluator: BudgetAlertEvaluator
    ) -> BudgetAlertSaveToken {
        switch rejected {
        case .noIdentity, .otherUser:
            userID = rejected == .noIdentity ? nil : userB
            let token = evaluator.savedBudgetToken()
            userID = userA
            return token
        case .beforeReset, .beforeClearRecords:
            let token = evaluator.savedBudgetToken()
            apply(rejected == .beforeReset ? .reset : .clearRecords, to: evaluator)
            return token
        case .malformed, .otherMonth:
            return evaluator.savedBudgetToken()
        }
    }

    func apply(_ change: BudgetAlertEvaluatorTests.Change, to evaluator: BudgetAlertEvaluator) {
        switch change {
        case .switchAccount:
            userID = userB
        case .reset:
            evaluator.reset()
        case .clearRecords:
            evaluator.clearRecords()
        }
    }

    /// 판정을 띄우고, 돌아오면 그때의 읽기 횟수를 남긴다.
    func startEvaluating(
        _ evaluator: BudgetAlertEvaluator,
        _ trigger: BudgetAlertTrigger = .ledgerChange
    ) -> Task<Void, Never> {
        Task {
            await evaluator.evaluate(trigger)
            self.returnedAfterFetches.append(self.fetchedMonths.count)
        }
    }

    private func gate(_ point: BudgetAlertEvaluatorTests.Point) -> Gate {
        switch point {
        case .probe:
            Gate(probe, skipping: 0)
        case .firstFetch:
            Gate(fetch, skipping: 0)
        case .rereadFetch:
            Gate(fetch, skipping: 1)
        }
    }
}

/// 한 자리의 붙잡기·확인·풀기.
@MainActor
private struct Gate {
    let hold: () -> Void
    let isHeld: () -> Bool
    let release: ((any Error)?) -> Void

    init<Args, Value>(_ call: FakeCall<Args, Value>, skipping count: Int) {
        hold = { call.hold(skipping: count) }
        isHeld = { call.hasHeld }
        release = { failure in call.release(with: failure.map { .failure($0) }) }
    }
}

/// 루트가 부르듯 띄워 본다. 조건은 앱이 앞이고 막는 것이 없으며 오버레이 칸만 지금 상태를 본다(루트와 같다) —
/// `blocked` 가 있으면 그 조건도 어긋난다.
@MainActor
private func presentLikeRoot(
    _ evaluator: BudgetAlertEvaluator,
    _ overlays: RootOverlayModel,
    blocked: BudgetAlertGateTests.Blocker? = nil
) -> Bool {
    var gate = BudgetAlertGateTests.ready
    gate.hasRootOverlay = overlays.presentation != nil
    blocked?.apply(to: &gate)
    return BudgetAlertPresentation.presentIfPossible(gate: gate, evaluator: evaluator, overlays: overlays)
}

/// 붙잡은 자리까지 판정이 오도록 main actor 를 돌린다.
@MainActor
private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    var tries = 0
    while !condition(), tries < 1000 {
        await Task.yield()
        tries += 1
    }
    #expect(condition(), "판정이 붙잡은 자리에 닿지 않았다", sourceLocation: sourceLocation)
}

/// "아직 일어나지 않았다"를 세기 전에 main actor 에 쌓인 작업을 돌린다(선례 `BudgetTabViewModelTests`).
@MainActor
private func settleMainActor() async {
    for _ in 0 ..< 100 {
        await Task.yield()
    }
}

// MARK: 응답

@MainActor
private var october: ServerMonth {
    ServerMonth(year: 2026, month: 10)
}

@MainActor
private var september: ServerMonth {
    ServerMonth(year: 2026, month: 9)
}

@MainActor
private var november: ServerMonth {
    ServerMonth(year: 2026, month: 11)
}

/// 예산이 있는 달의 정상 응답 — `BudgetTabViewModel.isWellFormed` 를 지난다. 남은 일수는 계약대로 요청한 달이
/// 응답의 이번 달일 때만 있다(따로 적지 않으면 7). 결제수단 세 묶음과 그 외 카테고리 줄은 몫 없이 사용액만 있다.
@MainActor
private func makeBudget(
    _ month: ServerMonth = ServerMonth(year: 2026, month: 10),
    current: ServerMonth = ServerMonth(year: 2026, month: 10),
    status: BudgetStatus = .nearLimit,
    amount: Decimal = 2_500_000,
    currency: CurrencyCode = .krw,
    total: BudgetLine? = nil,
    remainingDays: Int = 7,
    dailyAllowance: DailyAllowance? = nil
) -> MonthlyBudget {
    MonthlyBudget(
        year: month.year,
        month: month.month,
        currentYear: current.year,
        currentMonth: current.month,
        remainingDaysIncludingToday: month == current ? remainingDays : nil,
        hasAnyBudget: true,
        status: status,
        currency: currency,
        total: total ?? makeTotal(status, amount: amount),
        paymentGroups: [PaymentGroup.creditCard, .cashAndDebit, .accountAndOther].map {
            BudgetPaymentGroupLine(paymentGroup: $0, line: makeSpentOnlyLine(30000))
        },
        categories: [],
        otherCategories: makeSpentOnlyLine(40000),
        missingRateCount: 0,
        dailyAllowance: dailyAllowance,
        deletedCategoriesWithSpending: []
    )
}

/// 기본 응답(`makeBudget()` — 2,500,000 · 남은 날 7)의 창. 임박은 남은 돈 500,000, 넘음은 넘은 돈 100,000 이다.
@MainActor
private func makeDefaultAlert(_ status: BudgetStatus) -> BudgetAlert {
    let isOver = status == .exceeded
    return BudgetAlert(
        threshold: isOver ? .reached : .nearLimit,
        year: 2026,
        month: 10,
        currency: .krw,
        remainingAmount: isOver ? nil : 500_000,
        overAmount: isOver ? 100_000 : nil,
        remainingDaysIncludingToday: 7,
        dailyAllowance: nil
    )
}

/// 2026-10 의 전체 예산 `amount` 에 서버가 준 사용액·퍼센트·남은 날·하루 권장액을 그대로 담은 응답. 남은 돈·넘은 돈은
/// 계약대로 넘었을 때만 넘은 돈이고 아니면 남은 돈이다(`makeTotal` 과 같다).
@MainActor
private func makeServerBudget(
    _ status: BudgetStatus,
    spent: Decimal,
    percent: Int? = nil,
    amount: Decimal = 1_000_000,
    currency: CurrencyCode = .krw,
    remainingDays: Int = 9,
    dailyAllowance: DailyAllowance? = nil
) -> MonthlyBudget {
    let isOver = status == .exceeded
    let total = BudgetLine(
        budgetAmount: amount,
        actualAmount: spent,
        status: status,
        percent: percent,
        remainingAmount: isOver ? nil : amount - spent,
        overAmount: isOver ? spent - amount : nil
    )
    return makeBudget(
        status: status,
        amount: amount,
        currency: currency,
        total: total,
        remainingDays: remainingDays,
        dailyAllowance: dailyAllowance
    )
}

/// 2026-10 창. 따로 적지 않으면 KRW · 남은 날 9 · 하루 권장액 없음.
@MainActor
private func makeWindow(
    _ threshold: BudgetAlertThreshold,
    currency: CurrencyCode = .krw,
    remaining: Decimal? = nil,
    over: Decimal? = nil,
    remainingDays: Int? = 9,
    dailyAllowance: DailyAllowance? = nil
) -> BudgetAlert {
    BudgetAlert(
        threshold: threshold,
        year: 2026,
        month: 10,
        currency: currency,
        remainingAmount: remaining,
        overAmount: over,
        remainingDaysIncludingToday: remainingDays,
        dailyAllowance: dailyAllowance
    )
}

/// 창 내용 한 갈래 — 같은 예산의 "아래" 응답 · 판정할 응답 · 기대하는 창.
private struct WindowScenario {
    let below: MonthlyBudget
    let judged: MonthlyBudget
    let alert: BudgetAlert
}

@MainActor
private func makeWindowScenario(_ windowCase: BudgetAlertEvaluatorTests.WindowCase) -> WindowScenario {
    let below = makeServerBudget(.inProgress, spent: 500_000, percent: 50)
    switch windowCase {
    case .nearLimit:
        let daily = DailyAllowance(amount: 22222, isExceeded: false)
        return WindowScenario(
            below: below,
            judged: makeServerBudget(.nearLimit, spent: 800_000, percent: 80, dailyAllowance: daily),
            alert: makeWindow(.nearLimit, remaining: 200_000, dailyAllowance: daily)
        )
    case .exceeded:
        let daily = DailyAllowance(amount: nil, isExceeded: true)
        return WindowScenario(
            below: below,
            judged: makeServerBudget(.exceeded, spent: 1_030_000, dailyAllowance: daily),
            alert: makeWindow(.reached, over: 30000, dailyAllowance: daily)
        )
    case .reached:
        let daily = DailyAllowance(amount: 0, isExceeded: false)
        return WindowScenario(
            below: below,
            judged: makeServerBudget(.reached, spent: 1_000_000, percent: 100, dailyAllowance: daily),
            alert: makeWindow(.reached, dailyAllowance: daily)
        )
    case .usd:
        // 2자리 통화 — 금액의 소수를 그대로 든다.
        let daily = DailyAllowance(amount: Decimal(1564) / 100, isExceeded: false)
        return WindowScenario(
            below: makeServerBudget(.inProgress, spent: 300, percent: 30, amount: 1000, currency: .usd),
            judged: makeServerBudget(
                .nearLimit,
                spent: Decimal(81234) / 100,
                percent: 81,
                amount: 1000,
                currency: .usd,
                remainingDays: 12,
                dailyAllowance: daily
            ),
            alert: makeWindow(
                .nearLimit,
                currency: .usd,
                remaining: Decimal(18766) / 100,
                remainingDays: 12,
                dailyAllowance: daily
            )
        )
    case .noDailyAllowance:
        return WindowScenario(
            below: below,
            judged: makeServerBudget(.nearLimit, spent: 850_000, percent: 85, remainingDays: 3),
            alert: makeWindow(.nearLimit, remaining: 150_000, remainingDays: 3)
        )
    }
}

/// 받아들였다면 상태를 바꿨을 저장 응답 — 11월이 이번 달인 넘은 예산이라 받아들이면 아는 달이 11월이 되고 창·예산 없음
/// 기억이 사라진다. 계약 검사 갈래는 퍼센트 없는 임박, 다른 달 갈래는 응답의 이번 달(11월)이 아닌 12월 예산이다.
@MainActor
private func makeRejectedSave(_ rejected: BudgetAlertEvaluatorTests.Rejected) -> MonthlyBudget {
    let december = ServerMonth(year: 2026, month: 12)
    return switch rejected {
    case .malformed: makeBudget(november, current: november, total: makeNearLimitTotalWithoutPercent())
    case .otherMonth: makeBudget(december, current: november, status: .exceeded, amount: 1_400_000)
    default: makeBudget(november, current: november, status: .exceeded, amount: 1_400_000)
    }
}

/// 미설정 달 — 계약상 통화·전체 줄이 null 이다(`BudgetTabViewModel.isWellFormed` 를 지난다).
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

/// 전체 줄. 계약대로 진행 중·임박은 퍼센트와 남은 돈, 도달은 남은 돈 0, 초과는 넘은 돈만 있다.
/// 따로 적지 않은 상태는 진행 중(40%)이다.
@MainActor
private func makeTotal(_ status: BudgetStatus, amount: Decimal) -> BudgetLine {
    let spent: Decimal
    let percent: Int?
    switch status {
    case .nearLimit:
        (spent, percent) = (amount * 4 / 5, 80)
    case .reached:
        (spent, percent) = (amount, 100)
    case .exceeded:
        (spent, percent) = (amount + 100_000, nil)
    default:
        (spent, percent) = (amount * 2 / 5, 40)
    }
    let isOver = status == .exceeded
    return BudgetLine(
        budgetAmount: amount,
        actualAmount: spent,
        status: status,
        percent: percent,
        remainingAmount: isOver ? nil : amount - spent,
        overAmount: isOver ? spent - amount : nil
    )
}

/// 임박인데 퍼센트가 없는 전체 줄 — 계약 검사(`BudgetTotalLine`)에만 걸리고 step 1 판정은 지난다.
@MainActor
private func makeNearLimitTotalWithoutPercent() -> BudgetLine {
    BudgetLine(
        budgetAmount: 2_500_000,
        actualAmount: 2_000_000,
        status: .nearLimit,
        percent: nil,
        remainingAmount: 500_000,
        overAmount: nil
    )
}

/// 몫이 없는 줄 — 사용액만 있다.
@MainActor
private func makeSpentOnlyLine(_ spent: Decimal) -> BudgetLine {
    BudgetLine(
        budgetAmount: nil,
        actualAmount: spent,
        status: nil,
        percent: nil,
        remainingAmount: nil,
        overAmount: nil
    )
}
