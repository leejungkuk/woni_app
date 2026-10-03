//
//  BudgetAlertEvaluatorTests.swift
//  woni_appTests
//

import Foundation
import Testing
import UserNotifications
@testable import woni_app

/// 예산 알림 판정기 — 언제 판정해 보내는지(스펙 §5). 무엇을 보낼지는 `BudgetAlertTests` 가 본다.
/// 따로 적지 않으면 앱 알림 켜짐 · iOS 허용 · 계정 A · 앱 언어 ko 이고, 서버 시각과 응답의 이번 달은 2026-10,
/// 응답은 통화 KRW · 전체 예산 2,500,000 · 임박(남은 돈 500,000)이다. 기록은 실제 `BudgetAlertRecordStore`(테스트마다
/// 새 suite)다.
@Suite(.serialized)
@MainActor
struct BudgetAlertEvaluatorTests {
    // MARK: 판정을 시작할 조건

    @Test("B64N.S2-R1 앱 알림이 꺼져 있으면 iOS 권한도 서버도 부르지 않고 보내지도 기록하지도 않는다")
    func disabledDoesNothing() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.isEnabled = false

        await evaluator.evaluate()

        #expect(fakes.log.isEmpty)
        #expect(fakes.recorded(makeBudget()).isEmpty)

        // 짝: 켜져 있으면 서버를 읽고 보낸다.
        fakes.isEnabled = true
        await evaluator.evaluate()
        #expect(fakes.probeCount == 1)
        #expect(fakes.scheduled.count == 1)
    }

    @Test(
        "B64N.S2-R2 시작할 때 iOS 권한이 허용이 아니면 서버를 부르지 않고 기록도 남기지 않으며, 허용되면 보낸다",
        arguments: [NotificationAuthorization.denied, .notDetermined]
    )
    func notAllowedAtStartDoesNothing(_ status: NotificationAuthorization) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.permissionStatus = status

        await evaluator.evaluate()

        #expect(fakes.log == [.permission])
        #expect(fakes.recorded(makeBudget()).isEmpty)

        fakes.permissionStatus = .allowed
        await evaluator.evaluate()
        #expect(fakes.scheduled.count == 1)
    }

    @Test("B64N.S2-R2 진행률을 받은 뒤 다시 읽은 iOS 권한이 거부면 보내지도 기록하지도 않는다")
    func deniedAfterProgressDoesNotSend() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: .permissionAfterProgress) {
            fakes.permissionStatus = .denied
        }

        #expect(fakes.log == [.permission, .probe, .fetch(october), .permission])
        #expect(fakes.recorded(makeBudget()).isEmpty)

        // 짝: 다시 허용되면 다음 판정이 보낸다.
        fakes.permissionStatus = .allowed
        await evaluator.evaluate()
        #expect(fakes.scheduled.count == 1)
    }

    @Test("B64N.S2-R3 앱 알림이 꺼진 동안 넘은 기준도 켠 뒤 첫 판정에서 보낸다")
    func sendsAfterAppSettingTurnsOn() async throws {
        let fakes = try EvaluatorFakes()
        let budget = makeBudget(status: .exceeded)
        fakes.fetch.result = { _ in .success(budget) }
        let evaluator = fakes.makeEvaluator()
        fakes.isEnabled = false
        await evaluator.evaluate()
        #expect(fakes.scheduled.isEmpty)

        fakes.isEnabled = true
        await evaluator.evaluate()

        #expect(try fakes.scheduled == [ScheduledAlert(identifier: fakes.key(budget, .reached), body: usedUpKo)])
        #expect(fakes.recorded(budget) == [.nearLimit, .reached])
    }

    @Test("B64N.S2-R3 iOS 가 막은 동안 넘은 기준도 허용된 뒤 첫 판정에서 보낸다")
    func sendsAfterIOSAllows() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.permissionStatus = .denied
        await evaluator.evaluate()
        #expect(fakes.scheduled.isEmpty)
        #expect(fakes.recorded(makeBudget()).isEmpty)

        fakes.permissionStatus = .allowed
        await evaluator.evaluate()

        #expect(try fakes.scheduled == [
            ScheduledAlert(identifier: fakes.key(makeBudget(), .nearLimit), body: nearLimitKo)
        ])
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
    }

    @Test("B64N.S2-R4 신원이 없으면 서버를 부르지 않고 보내지 않으며, 신원이 생긴 뒤 판정은 보낸다")
    func noIdentityDoesNotFetch() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.userID = nil

        await evaluator.evaluate()

        #expect(fakes.probeCount == 0)
        #expect(fakes.fetchedMonths.isEmpty)
        #expect(fakes.scheduled.isEmpty)

        fakes.userID = userA
        await evaluator.evaluate()
        #expect(fakes.scheduled.count == 1)
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
        #expect(fakes.scheduled.isEmpty)
        #expect(fakes.recorded(makeBudget()).isEmpty)

        // 짝: 신원이 돌아오면 다음 판정이 보낸다.
        fakes.userID = userA
        await evaluator.evaluate()
        #expect(fakes.scheduled.count == 1)
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

        await evaluator.evaluate()

        #expect(fakes.probeCount == 1)
        #expect(fakes.fetchedMonths == [serverMonth])
        #expect(fakes.scheduled.count == 1)
    }

    @Test("B64N.S2-R5 두 번째 판정은 서버 시각을 다시 묻지 않고 앞 판정 응답의 이번 달로 읽는다")
    func laterEvaluationReadsKnownMonth() async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate()
        #expect(fakes.fetchedMonths == [september, october])

        await evaluator.evaluate()

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

        await evaluator.evaluate()

        #expect(fakes.fetchedMonths == [september, october])
        #expect(try fakes.scheduled == [
            ScheduledAlert(identifier: fakes.key(makeBudget(october), .nearLimit), body: nearLimitKo)
        ])
    }

    @Test("B64N.S2-R5 다시 읽은 응답도 이번 달이 다르면 세 번째로 읽지 않고 보내지 않으며 아는 달도 그대로다")
    func secondMismatchStops() async throws {
        let fakes = try EvaluatorFakes()
        fakes.probe.result = { _ in .success(september) }
        fakes.fetch.result = { .success(makeBudget($0, current: september, status: .inProgress)) }
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate()
        #expect(fakes.fetchedMonths == [september])

        let november = ServerMonth(year: 2026, month: 11)
        fakes.fetch.result = { .success(makeBudget($0, current: $0 == september ? october : november)) }
        await evaluator.evaluate()

        #expect(fakes.fetchedMonths == [september, september, october])
        #expect(fakes.scheduled.isEmpty)

        // 다음 판정도 서버 시각을 묻지 않고 처음 읽은 달(9월)부터 읽는다.
        await evaluator.evaluate()
        #expect(fakes.probeCount == 1)
        #expect(fakes.fetchedMonths == [september, september, october, september, october])
    }

    @Test("B64N.S2-R5 reset() 뒤의 판정은 서버 시각의 이번 달부터 다시 받는다")
    func resetForgetsKnownMonth() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate()
        await evaluator.evaluate()
        #expect(fakes.probeCount == 1)

        evaluator.reset()
        await evaluator.evaluate()

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
        await evaluator.evaluate()

        // 서버의 이번 달이 10월로 넘어갔다.
        let movedOn: (ServerMonth) -> Result<MonthlyBudget, any Error> = { .success(makeBudget($0, current: october)) }
        switch discard {
        case .firstFetchFails:
            fakes.fetch.result = { _ in .failure(FakeError.offline) }
            await evaluator.evaluate()
        case .rereadFails:
            fakes.fetch.result = { $0 == october ? .failure(FakeError.offline) : movedOn($0) }
            await evaluator.evaluate()
        case .disabledDuringReread:
            fakes.fetch.result = movedOn
            await fakes.evaluate(evaluator, holding: .rereadFetch) { fakes.isEnabled = false }
        case .accountSwitchedDuringReread:
            fakes.fetch.result = movedOn
            await fakes.evaluate(evaluator, holding: .rereadFetch) { fakes.userID = userB }
        }
        #expect(fakes.scheduled.isEmpty)
        let readsBefore = fakes.fetchedMonths.count

        fakes.isEnabled = true
        fakes.fetch.result = movedOn
        await evaluator.evaluate()

        #expect(fakes.probeCount == 1)
        #expect(fakes.fetchedMonths.dropFirst(readsBefore).first == september)
    }

    @Test("B64N.S2-R6 서버 시각을 받지 못하면 읽지도 보내지도 않는다")
    func probeFailureStops() async throws {
        let fakes = try EvaluatorFakes()
        fakes.probe.result = { _ in .failure(FakeError.offline) }
        let evaluator = fakes.makeEvaluator()

        await evaluator.evaluate()

        #expect(fakes.probeCount == 1)
        #expect(fakes.fetchedMonths.isEmpty)
        #expect(fakes.scheduled.isEmpty)

        // 짝: 받으면 읽고 보낸다.
        fakes.probe.result = { _ in .success(october) }
        await evaluator.evaluate()
        #expect(fakes.fetchedMonths == [october])
        #expect(fakes.scheduled.count == 1)
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
        #expect(fakes.scheduled.isEmpty)
        #expect(fakes.recorded(makeBudget(october)).isEmpty)

        await evaluator.evaluate()
        #expect(fakes.scheduled.count == 1)
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

        await evaluator.evaluate()

        #expect(fakes.fetchedMonths == [october])
        #expect(fakes.scheduled.isEmpty)
        #expect(fakes.recorded(broken).isEmpty)

        // 짝: 같은 응답에 퍼센트가 있으면 보낸다.
        fakes.fetch.result = { .success(makeBudget($0)) }
        await evaluator.evaluate()
        #expect(fakes.scheduled.count == 1)
    }
}

// MARK: 기다리는 자리 — 설정·권한·계정이 바뀜, 요청 실패

extension BudgetAlertEvaluatorTests {
    @Test(
        "B64N.S2-R7 진행률을 받는 사이 앱 알림이 꺼지거나 iOS 가 막으면 보내지도 기록하지도 않는다",
        arguments: zip(
            [Point.firstFetch, .firstFetch, .rereadFetch, .permissionAfterProgress],
            [Change.disable, .deny, .disable, .disable]
        )
    )
    func settingChangedWhileWaitingStops(_ point: Point, _ change: Change) async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: point) {
            fakes.apply(change, to: evaluator)
        }

        #expect(fakes.fetchedMonths == [september, october])
        #expect(fakes.scheduled.isEmpty)
        #expect(fakes.recorded(makeBudget(october)).isEmpty)
    }

    @Test(
        "B64N.S2-R7 진행률을 받는 사이 아무것도 바뀌지 않으면 한 번 보낸다",
        arguments: [Point.firstFetch, .rereadFetch, .permissionAfterProgress]
    )
    func unchangedSettingSends(_ point: Point) async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: point)

        #expect(fakes.scheduled.count == 1)
        #expect(fakes.recorded(makeBudget(october)) == [.nearLimit])
    }

    @Test("B64N.S2-R8 iOS 요청이 실패하면 기록하지 않고 다음 판정에서 같은 알림을 다시 보낸다")
    func failedRequestIsRetried() async throws {
        let fakes = try EvaluatorFakes()
        fakes.scheduleCall.result = { _ in .failure(FakeError.offline) }
        let evaluator = fakes.makeEvaluator()

        await evaluator.evaluate()

        let expected = try ScheduledAlert(identifier: fakes.key(makeBudget(), .nearLimit), body: nearLimitKo)
        #expect(fakes.scheduled == [expected])
        #expect(fakes.recorded(makeBudget()).isEmpty)
        #expect(fakes.removed.isEmpty)

        fakes.scheduleCall.result = { _ in .success(()) }
        await evaluator.evaluate()

        #expect(fakes.scheduled == [expected, expected])
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
    }

    @Test(
        "B64N.S2-R9 판정이 기다리는 사이 계정이 바뀌면(ID 다름·reset) 그 자리에서 멈춘다 — 보내지도 기록하지도 않는다",
        arguments: Point.allCases.filter { $0 != .schedule }, [Change.switchAccount, .reset]
    )
    func accountChangedWhileWaitingStops(_ point: Point, _ change: Change) async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: point) {
            fakes.apply(change, to: evaluator)
        }

        #expect(fakes.scheduled.isEmpty)
        #expect(fakes.removed.isEmpty)
        #expect(fakes.recorded(makeBudget(october), user: userA).isEmpty)
        #expect(fakes.recorded(makeBudget(october), user: userB).isEmpty)
    }

    @Test(
        "B64N.S2-R9 iOS 에 요청한 직후 계정이 바뀌면(ID 다름·reset) 기록하지 않고 같은 식별자로 지운다",
        arguments: [Change.switchAccount, .reset]
    )
    func accountChangedAfterRequestRemoves(_ change: Change) async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: .schedule) {
            fakes.apply(change, to: evaluator)
        }

        let identifier = try fakes.key(makeBudget(october), .nearLimit)
        #expect(fakes.scheduled.map(\.identifier) == [identifier])
        #expect(fakes.removed == [identifier])
        #expect(fakes.recorded(makeBudget(october), user: userA).isEmpty)
        #expect(fakes.recorded(makeBudget(october), user: userB).isEmpty)
    }

    @Test(
        "B64N.S2-R9 아무것도 바뀌지 않으면 어느 자리에서 기다려도 보내고 기록하며 지우지 않는다",
        arguments: Point.allCases
    )
    func unchangedAccountSends(_ point: Point) async throws {
        let fakes = try EvaluatorFakes()
        fakes.useMonthChangeScenario()
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: point)

        #expect(fakes.scheduled.count == 1)
        #expect(fakes.removed.isEmpty)
        #expect(fakes.recorded(makeBudget(october)) == [.nearLimit])
    }
}

// MARK: 한 번에 하나

extension BudgetAlertEvaluatorTests {
    @Test("B64N.S2-R10 판정 중에 온 요청 여럿은 앞 판정이 끝난 뒤 한 번만 더 돌고, 기다린 요청은 그 판정이 끝난 뒤 돌아온다")
    func requestsDuringEvaluationRunOnceAfter() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
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
        #expect(fakes.scheduled.count == 1)
        #expect(fakes.returnedAfterFetches.isEmpty)

        fakes.fetch.release()
        await first.value
        await second.value
        await third.value

        // 뒤 판정은 앞 판정의 기록을 보고 보내지 않는다.
        #expect(fakes.fetchedMonths.count == 2)
        #expect(fakes.scheduled.count == 1)
        #expect(fakes.returnedAfterFetches == [2, 2, 2])
    }

    @Test("B64N.S2-R10 앞 판정이 읽기 실패로 멈춰도 기다리던 판정은 한 번 돈다")
    func waitingEvaluationRunsAfterFailedOne() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        fakes.fetch.hold()
        let first = fakes.startEvaluating(evaluator)
        await waitUntil { fakes.fetch.hasHeld }
        let queued = fakes.startEvaluating(evaluator)
        await settleMainActor()
        let fetchesBefore = fakes.fetchedMonths.count

        fakes.fetch.release(with: .failure(FakeError.offline))
        await first.value
        await queued.value

        #expect(fakes.fetchedMonths.count - fetchesBefore == 1)
        #expect(fakes.scheduled.count == 1)
    }

    @Test("B64N.S2-R10 앞 판정 중에 reset() 되면 앞 판정은 버리고 기다리던 판정이 서버 시각부터 다시 읽어 보낸다")
    func waitingEvaluationRunsAfterReset() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate()
        #expect(fakes.scheduled.count == 1)
        fakes.fetch.hold()
        let first = fakes.startEvaluating(evaluator)
        await waitUntil { fakes.fetch.hasHeld }
        let queued = fakes.startEvaluating(evaluator)
        await settleMainActor()
        evaluator.reset()
        let probesBefore = fakes.probeCount
        let fetchesBefore = fakes.fetchedMonths.count
        let sentBefore = fakes.scheduled.count

        fakes.fetch.release()
        await first.value
        await queued.value

        #expect(fakes.probeCount - probesBefore == 1)
        #expect(fakes.fetchedMonths.count - fetchesBefore == 1)
        #expect(fakes.scheduled.count - sentBefore == 1)
    }
}

// MARK: 기록

extension BudgetAlertEvaluatorTests {
    @Test("B64N.S2-R11 같은 응답으로 다시 판정해도 한 번만 보낸다")
    func sameResponseSendsOnce() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()

        await evaluator.evaluate()
        await evaluator.evaluate()

        #expect(fakes.scheduled.count == 1)
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
    }

    @Test("B64N.S2-R11 80% 를 보낸 뒤 넘으면 100% 를 한 번 더 보내고, 그대로면 다시 보내지 않는다")
    func hundredAfterEighty() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate()

        fakes.fetch.result = { .success(makeBudget($0, status: .exceeded)) }
        await evaluator.evaluate()
        await evaluator.evaluate()

        #expect(try fakes.scheduled == [
            ScheduledAlert(identifier: fakes.key(makeBudget(), .nearLimit), body: nearLimitKo),
            ScheduledAlert(identifier: fakes.key(makeBudget(status: .exceeded), .reached), body: usedUpKo)
        ])
    }

    @Test("B64N.S2-R11 처음 판정에서 넘었으면 100% 만 보내고, 같은 예산이 임박으로 내려와도 80% 를 보내지 않는다")
    func eightyCountedWithHundred() async throws {
        let fakes = try EvaluatorFakes()
        fakes.fetch.result = { .success(makeBudget($0, status: .exceeded)) }
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate()
        #expect(fakes.scheduled.map(\.body) == [usedUpKo])

        fakes.fetch.result = { .success(makeBudget($0)) }
        await evaluator.evaluate()

        #expect(fakes.scheduled.count == 1)
        #expect(fakes.recorded(makeBudget()) == [.nearLimit, .reached])
    }

    @Test("B64N.S2-R11 기준 아래로 내려갔다 다시 넘어도 같은 예산이면 다시 보내지 않는다")
    func droppingBelowAndBackDoesNotResend() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()

        for status in [BudgetStatus.nearLimit, .inProgress, .nearLimit] {
            fakes.fetch.result = { .success(makeBudget($0, status: status)) }
            await evaluator.evaluate()
        }

        #expect(fakes.scheduled.count == 1)
    }

    @Test("B64N.S2-R11 전체 금액이나 통화가 바뀐 예산은 새 기준으로 다시 보낸다", arguments: BudgetChange.allCases)
    func changedBudgetResends(_ change: BudgetChange) async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate()
        let changed = switch change {
        case .amount: makeBudget(amount: 3_000_000)
        case .currency: makeBudget(currency: .usd)
        }

        fakes.fetch.result = { _ in .success(changed) }
        await evaluator.evaluate()

        #expect(try fakes.scheduled.map(\.identifier) == [
            fakes.key(makeBudget(), .nearLimit),
            fakes.key(changed, .nearLimit)
        ])
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
        #expect(fakes.recorded(changed) == [.nearLimit])
    }

    @Test("B64N.S2-R11 50만 → 60만 → 50만으로 돌아온 예산은 앞의 50만 기록이 남아 다시 보내지 않는다")
    func returningToEarlierAmountDoesNotResend() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        var sentCounts: [Int] = []

        for amount: Decimal in [500_000, 600_000, 500_000] {
            fakes.fetch.result = { .success(makeBudget($0, amount: amount)) }
            await evaluator.evaluate()
            sentCounts.append(fakes.scheduled.count)
        }

        #expect(sentCounts == [1, 2, 2])
        #expect(fakes.recorded(makeBudget(amount: 500_000)) == [.nearLimit])
        #expect(fakes.recorded(makeBudget(amount: 600_000)) == [.nearLimit])
    }

    @Test("B64N.S2-R12 알림 식별자는 보낸 기준의 기록 키다 — 기준·계정마다 다르다")
    func identifierIsRecordKey() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate()
        fakes.fetch.result = { .success(makeBudget($0, status: .exceeded)) }
        await evaluator.evaluate()

        fakes.userID = userB
        fakes.fetch.result = { .success(makeBudget($0)) }
        await evaluator.evaluate()

        let identifiers = fakes.scheduled.map(\.identifier)
        #expect(try identifiers == [
            fakes.key(makeBudget(), .nearLimit),
            fakes.key(makeBudget(), .reached),
            fakes.key(makeBudget(), .nearLimit, user: userB)
        ])
        #expect(Set(identifiers).count == 3)
    }

    @Test("B64N.S2-R12 요청한 직후 계정이 바뀌어 지울 때도 요청한 식별자(앞 계정의 기록 키)로 지운다")
    func removeUsesRequestedRecordKey() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: .schedule) {
            fakes.userID = userB
        }

        let identifier = try fakes.key(makeBudget(), .nearLimit)
        #expect(fakes.scheduled.map(\.identifier) == [identifier])
        #expect(fakes.removed == [identifier])
        #expect(try fakes.removed != [fakes.key(makeBudget(), .nearLimit, user: userB)])
    }

    @Test("B64N.S2-R13 reset() 은 기록을 비운다 — 같은 응답으로 다시 판정하면 다시 보낸다")
    func resetClearsRecords() async throws {
        let fakes = try EvaluatorFakes()
        let evaluator = fakes.makeEvaluator()
        await evaluator.evaluate()
        await evaluator.evaluate()
        #expect(fakes.scheduled.count == 1)

        evaluator.reset()
        #expect(fakes.recorded(makeBudget()).isEmpty)
        await evaluator.evaluate()

        #expect(fakes.scheduled.count == 2)
        #expect(fakes.recorded(makeBudget()) == [.nearLimit])
    }
}

// MARK: iOS 요청 · 문구

extension BudgetAlertEvaluatorTests {
    @Test(
        "B64N.S2-R14 iOS 요청은 받은 식별자·본문 그대로 바로 띄우고, 제목 없이 기본 소리다",
        arguments: zip(["a|2026-10|80", "b|2026-11|100"], ["본문 하나", "Body two"])
    )
    func systemSchedulerBuildsRequest(identifier: String, body: String) async throws {
        let center = FakeAlertCenter()
        let scheduler = SystemBudgetAlertScheduler(center: center)

        try await scheduler.schedule(identifier: identifier, body: body)

        #expect(center.added.count == 1)
        let request = try #require(center.added.first)
        #expect(request.identifier == identifier)
        #expect(request.trigger == nil)
        #expect(request.content.body == body)
        #expect(request.content.title.isEmpty)
        #expect(request.content.sound == UNNotificationSound.default)
        #expect(center.removedPending.isEmpty)
        #expect(center.removedDelivered.isEmpty)
    }

    @Test("B64N.S2-R14 iOS 가 요청을 거부하면 schedule 도 던진다")
    func systemSchedulerRethrows() async {
        let center = FakeAlertCenter()
        center.addError = FakeError.offline
        let scheduler = SystemBudgetAlertScheduler(center: center)

        await #expect(throws: FakeError.offline) {
            try await scheduler.schedule(identifier: "a", body: "b")
        }
        #expect(center.added.count == 1)
    }

    @Test(
        "B64N.S2-R14 지우기는 대기 중 요청과 알림 센터에 남은 알림을 같은 식별자로 지운다",
        arguments: ["a|2026-10|80", "b|2026-11|100"]
    )
    func systemSchedulerRemovesBoth(identifier: String) {
        let center = FakeAlertCenter()

        SystemBudgetAlertScheduler(center: center).remove(identifier: identifier)

        #expect(center.removedPending == [[identifier]])
        #expect(center.removedDelivered == [[identifier]])
        #expect(center.added.isEmpty)
    }

    @Test("B64N.S2-R15 본문은 판정할 때의 앱 언어로 쓴다(80%·100% × ko·en)", arguments: BodyCase.all)
    func bodyFollowsLanguage(_ bodyCase: BodyCase) async throws {
        let fakes = try EvaluatorFakes()
        fakes.language = bodyCase.language
        fakes.fetch.result = { .success(makeBudget($0, status: bodyCase.status)) }
        let evaluator = fakes.makeEvaluator()

        await evaluator.evaluate()

        #expect(fakes.scheduled.map(\.body) == [bodyCase.body])
    }

    @Test(
        "B64N.S2-R15 진행률을 받는 사이 앱 언어가 바뀌면 바뀐 언어로 쓴다",
        arguments: zip([AppLanguage.en, .ko], [AppLanguage.ko, .en])
    )
    func bodyUsesLanguageAtJudgment(start: AppLanguage, changed: AppLanguage) async throws {
        let fakes = try EvaluatorFakes()
        fakes.language = start
        let evaluator = fakes.makeEvaluator()

        await fakes.evaluate(evaluator, holding: .firstFetch) {
            fakes.language = changed
        }

        #expect(fakes.scheduled.map(\.body) == [changed == .ko ? nearLimitKo : nearLimitEn])
    }
}

// MARK: 인자

extension BudgetAlertEvaluatorTests {
    /// 판정이 기다리는 자리. `useMonthChangeScenario()` 의 판정에는 여섯 곳이 모두 있다.
    enum Point: CaseIterable {
        case startPermission, probe, firstFetch, rereadFetch, permissionAfterProgress, schedule
    }

    /// 기다리는 사이에 바뀌는 것.
    enum Change {
        case disable, deny, switchAccount, reset
    }

    /// 아는 달을 갱신하지 않는 판정.
    enum Discard: CaseIterable {
        case firstFetchFails, rereadFails, disabledDuringReread, accountSwitchedDuringReread
    }

    /// 기록 키가 달라지는 예산 변경.
    enum BudgetChange: CaseIterable {
        case amount, currency
    }

    struct BodyCase {
        let status: BudgetStatus
        let language: AppLanguage
        let body: String

        static let all = [
            BodyCase(status: .nearLimit, language: .ko, body: nearLimitKo),
            BodyCase(status: .nearLimit, language: .en, body: nearLimitEn),
            BodyCase(status: .exceeded, language: .ko, body: usedUpKo),
            BodyCase(status: .exceeded, language: .en, body: usedUpEn)
        ]
    }
}

// MARK: 가짜

private let userA = UUID()
private let userB = UUID()

private let nearLimitKo = "10월 예산의 80%를 썼습니다. 남은 돈 KRW 500,000"
private let nearLimitEn = "You've used 80% of your October budget. KRW 500,000 left"
private let usedUpKo = "10월 예산을 다 썼습니다."
private let usedUpEn = "You've used all of your October budget."

private enum FakeError: Error, Equatable {
    case offline
}

private struct ScheduledAlert: Equatable {
    let identifier: String
    let body: String
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
private final class EvaluatorFakes: NotificationPermissionProviding, BudgetAlertScheduling {
    enum Event: Equatable {
        case permission
        case probe
        case fetch(ServerMonth)
        case schedule(ScheduledAlert)
        case remove(String)
    }

    var isEnabled = true
    var userID: UUID? = userA
    var language = AppLanguage.ko
    var permissionStatus = NotificationAuthorization.allowed {
        didSet {
            let status = permissionStatus
            permission.result = { _ in .success(status) }
        }
    }

    let permission = FakeCall<Void, NotificationAuthorization> { _ in .success(.allowed) }
    let probe = FakeCall<Void, ServerMonth> { _ in .success(october) }
    let fetch = FakeCall<ServerMonth, MonthlyBudget> { .success(makeBudget($0)) }
    let scheduleCall = FakeCall<ScheduledAlert, Void> { _ in .success(()) }
    let records: BudgetAlertRecordStore
    private(set) var log: [Event] = []
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
            isEnabled: { self.isEnabled },
            permission: self,
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
            scheduler: self,
            records: records,
            language: { self.language }
        )
    }

    // MARK: NotificationPermissionProviding · BudgetAlertScheduling

    func authorization() async -> NotificationAuthorization {
        log.append(.permission)
        do {
            return try await permission.call(())
        } catch {
            Issue.record(error)
            return .denied
        }
    }

    func requestAuthorization() async -> NotificationAuthorization {
        Issue.record("판정기는 iOS 권한 창을 띄우지 않는다")
        return permissionStatus
    }

    func schedule(identifier: String, body: String) async throws {
        let alert = ScheduledAlert(identifier: identifier, body: body)
        log.append(.schedule(alert))
        try await scheduleCall.call(alert)
    }

    func remove(identifier: String) {
        log.append(.remove(identifier))
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

    /// iOS 에 요청한 알림(실패한 요청 포함).
    var scheduled: [ScheduledAlert] {
        log.compactMap { event in
            guard case let .schedule(alert) = event else {
                return nil
            }
            return alert
        }
    }

    var removed: [String] {
        log.compactMap { event in
            guard case let .remove(identifier) = event else {
                return nil
            }
            return identifier
        }
    }

    func key(_ budget: MonthlyBudget, _ threshold: BudgetAlertThreshold, user: UUID = userA) throws -> String {
        try #require(BudgetAlertDecision.recordKey(userID: user, budget: budget, threshold: threshold))
    }

    /// 그 응답·계정으로 기록된 기준들.
    func recorded(_ budget: MonthlyBudget, user: UUID = userA) -> [BudgetAlertThreshold] {
        BudgetAlertThreshold.allCases.filter { threshold in
            BudgetAlertDecision.recordKey(userID: user, budget: budget, threshold: threshold)
                .map(records.contains) ?? false
        }
    }

    /// 서버 시각은 9월이고 9월 응답이 "이번 달은 10월"이라 10월로 한 번 더 읽는 판정 — 기다리는 자리 여섯 곳이 모두 있다.
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
        let task = Task { await evaluator.evaluate() }
        await waitUntil(gate.isHeld)
        change()
        gate.release(failure)
        await task.value
    }

    func apply(_ change: BudgetAlertEvaluatorTests.Change, to evaluator: BudgetAlertEvaluator) {
        switch change {
        case .disable:
            isEnabled = false
        case .deny:
            permissionStatus = .denied
        case .switchAccount:
            userID = userB
        case .reset:
            evaluator.reset()
        }
    }

    /// 판정을 띄우고, 돌아오면 그때의 읽기 횟수를 남긴다.
    func startEvaluating(_ evaluator: BudgetAlertEvaluator) -> Task<Void, Never> {
        Task {
            await evaluator.evaluate()
            self.returnedAfterFetches.append(self.fetchedMonths.count)
        }
    }

    private func gate(_ point: BudgetAlertEvaluatorTests.Point) -> Gate {
        switch point {
        case .startPermission:
            Gate(permission, skipping: 0)
        case .probe:
            Gate(probe, skipping: 0)
        case .firstFetch:
            Gate(fetch, skipping: 0)
        case .rereadFetch:
            Gate(fetch, skipping: 1)
        case .permissionAfterProgress:
            Gate(permission, skipping: 1)
        case .schedule:
            Gate(scheduleCall, skipping: 0)
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

@MainActor
private final class FakeAlertCenter: BudgetAlertCenterClient {
    var addError: (any Error)?
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removedPending: [[String]] = []
    private(set) var removedDelivered: [[String]] = []

    func add(_ request: UNNotificationRequest) async throws {
        added.append(request)
        if let addError {
            throw addError
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPending.append(identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDelivered.append(identifiers)
    }
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

/// 예산이 있는 달의 정상 응답 — `BudgetTabViewModel.isWellFormed` 를 지난다. 남은 일수는 계약대로 요청한 달이
/// 응답의 이번 달일 때만 7 이다. 결제수단 세 묶음과 그 외 카테고리 줄은 몫 없이 사용액만 있다.
@MainActor
private func makeBudget(
    _ month: ServerMonth = ServerMonth(year: 2026, month: 10),
    current: ServerMonth = ServerMonth(year: 2026, month: 10),
    status: BudgetStatus = .nearLimit,
    amount: Decimal = 2_500_000,
    currency: CurrencyCode = .krw,
    total: BudgetLine? = nil
) -> MonthlyBudget {
    MonthlyBudget(
        year: month.year,
        month: month.month,
        currentYear: current.year,
        currentMonth: current.month,
        remainingDaysIncludingToday: month == current ? 7 : nil,
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
        dailyAllowance: nil
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
