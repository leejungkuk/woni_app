//
//  BudgetTabViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 탭의 상태·달 이동·다시 읽기 판정. 입력(서버·로컬 DB·신원)은 가짜이고 응답 시점은 테스트가 정한다.
/// 따로 적지 않으면 서버의 이번 달은 2026-10 이다.
@MainActor
struct BudgetTabViewModelTests {
    // MARK: 시작·헤더

    @Test("신원이 없으면 서버도 로컬 DB 도 부르지 않고 헤더 달·화살표·수정을 숨긴다")
    func startWithoutIdentityCallsNoNetwork() async {
        let fakes = BudgetTabFakes()
        fakes.hasIdentity = false
        let viewModel = fakes.makeViewModel()

        await viewModel.handle(.tabShown)

        #expect(viewModel.phase.isNoIdentity)
        #expect(fakes.probe.calls.isEmpty)
        #expect(fakes.fetch.calls.isEmpty)
        #expect(fakes.unsynced.calls.isEmpty)
        #expect(fakes.pendingIDCalls == 0)
        #expect(!viewModel.showsMonthHeader)
        #expect(!viewModel.showsEditButton)
        #expect(!viewModel.canGoPrevious)
        #expect(!viewModel.canGoNext)
    }

    @Test("처음엔 서버 시각의 이번 달을 확인하고, 그 달의 예산·동기화 전 건수·삭제 대기 ID 를 함께 읽는다")
    func startProbesServerMonthThenFetchesIt() async throws {
        let fakes = BudgetTabFakes()
        // 기기 시계의 달과 겹치지 않는 달 — 기기 달로 읽으면 여기서 어긋난다.
        let probed = yearMonth(2031, 3)
        fakes.probe.result = { _ in .success(probed) }
        fakes.fetch.result = { .success(makeBudget($0, current: probed)) }
        fakes.unsynced.result = { _ in .success(3) }
        fakes.pendingIDs = .success([4, 9])
        let viewModel = fakes.makeViewModel()

        await viewModel.handle(.tabShown)

        #expect(fakes.probe.calls.count == 1)
        #expect(fakes.fetch.calls == [probed])
        #expect(fakes.unsynced.calls == [probed])
        let content = try #require(viewModel.phase.content)
        #expect(viewModel.phase.shownMonth == probed)
        #expect(content.unsyncedExpenseCount == 3)
        #expect(content.pendingDeletionCategoryIDs == [4, 9])
        #expect(viewModel.month == probed)
        #expect(viewModel.serverMonth == probed)
    }

    @Test("서버 시각 확인이 실패하면 기기 달로 대신 읽지 않고, 헤더 달·화살표를 숨긴 채 불러올 수 없음이다")
    func startFailsAndHidesHeaderWhenProbeFails() async {
        let fakes = BudgetTabFakes()
        fakes.probe.result = { _ in .failure(BudgetTabTestError.offline) }
        let viewModel = fakes.makeViewModel()

        await viewModel.handle(.tabShown)

        #expect(viewModel.phase.isFailed)
        #expect(viewModel.serverMonth == nil)
        #expect(viewModel.month == nil)
        #expect(!viewModel.showsMonthHeader)
        #expect(!viewModel.canGoPrevious)
        #expect(!viewModel.canGoNext)
        #expect(fakes.fetch.calls.isEmpty)
        #expect(fakes.unsynced.calls.isEmpty)
    }

    @Test("서버 달을 안 뒤 예산 읽기가 실패하면 헤더는 그대로 두고 수정만 숨긴다")
    func startFailsButKeepsHeaderWhenFetchFails() async {
        let fakes = BudgetTabFakes()
        fakes.fetch.result = { _ in .failure(BudgetTabTestError.offline) }
        let viewModel = fakes.makeViewModel()

        await viewModel.handle(.tabShown)

        #expect(viewModel.phase.isFailed)
        #expect(viewModel.showsMonthHeader)
        #expect(viewModel.month == yearMonth(2026, 10))
        #expect(viewModel.canGoPrevious)
        #expect(viewModel.canGoNext)
        #expect(!viewModel.showsEditButton)
    }

    @Test("헤더 달은 서버의 이번 달을 모를 때만 숨긴다 — 확인 뒤 첫 예산을 기다리는 동안은 보인다")
    func headerHiddenOnlyUntilServerMonthKnown() async {
        let fakes = BudgetTabFakes()
        fakes.probe.holds = true
        fakes.fetch.holds = true
        let viewModel = fakes.makeViewModel()

        let start = Task { await viewModel.handle(.tabShown) }
        await waitUntil { fakes.probe.isHeld(0) }
        #expect(!viewModel.showsMonthHeader)
        #expect(viewModel.phase.isLoading)

        fakes.probe.release(0)
        await waitUntil { fakes.fetch.isHeld(0) }
        #expect(viewModel.showsMonthHeader)
        #expect(viewModel.phase.isLoading)
        #expect(viewModel.month == yearMonth(2026, 10))

        fakes.fetch.release(0)
        await start.value
        #expect(viewModel.phase.content != nil)
    }

    @Test("헤더 수정은 예산이 있는 달을 읽었을 때만 — 미설정 달·불러올 수 없음에는 없다")
    func editButtonOnlyForMonthWithBudget() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(viewModel.showsEditButton)

        fakes.fetch.result = { .success(makeNotSetBudget($0)) }
        await viewModel.go(by: -1)
        #expect(viewModel.phase.content?.budget.status == .notSet)
        #expect(!viewModel.showsEditButton)

        fakes.fetch.result = { _ in .failure(BudgetTabTestError.offline) }
        await viewModel.go(by: -1)
        #expect(viewModel.phase.isFailed)
        #expect(!viewModel.showsEditButton)
    }

    @Test("로컬 읽기(동기화 전 건수·삭제 대기 ID)가 실패하면 0·빈 집합으로 대신하지 않고 불러올 수 없음이다")
    func localReadFailureShowsFailed() async {
        let countFails = BudgetTabFakes()
        countFails.unsynced.result = { _ in .failure(BudgetTabTestError.database) }
        let countViewModel = countFails.makeViewModel()
        await countViewModel.handle(.tabShown)
        #expect(countViewModel.phase.isFailed)

        let idsFail = BudgetTabFakes()
        idsFail.pendingIDs = .failure(BudgetTabTestError.database)
        let idsViewModel = idsFail.makeViewModel()
        await idsViewModel.handle(.tabShown)
        #expect(idsFail.pendingIDCalls == 1)
        #expect(idsViewModel.phase.isFailed)
    }
}

// MARK: 달 이동

extension BudgetTabViewModelTests {
    @Test("달을 넘기면 응답 전까지 로딩이다 — 새 달 이름과 화살표는 그대로 쓸 수 있다")
    func goShowsLoadingUntilResponse() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        fakes.fetch.holds = true

        let move = Task { await viewModel.go(by: 1) }
        await waitUntil { fakes.fetch.isHeld(1) }
        #expect(viewModel.phase.isLoading)
        #expect(viewModel.month == yearMonth(2026, 11))
        #expect(viewModel.showsMonthHeader)
        #expect(viewModel.canGoPrevious)
        #expect(viewModel.canGoNext)

        fakes.fetch.release(1)
        await move.value
        #expect(fakes.fetch.calls.last == yearMonth(2026, 11))
        #expect(viewModel.phase.shownMonth == yearMonth(2026, 11))
    }

    @Test("달 범위는 2000-01 ~ 서버의 이번 달+12개월 — 끝에서는 그 방향으로 읽지 않고, 해 넘김은 맞다")
    func rangeStopsAtBothEnds() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)

        await viewModel.select(year: 2027, month: 9)
        #expect(viewModel.canGoNext)
        await viewModel.go(by: 1)
        #expect(viewModel.month == yearMonth(2027, 10))
        #expect(!viewModel.canGoNext)
        #expect(viewModel.canGoPrevious)
        let callsAtUpperEnd = fakes.fetch.calls.count
        await viewModel.go(by: 1)
        #expect(fakes.fetch.calls.count == callsAtUpperEnd)
        #expect(viewModel.month == yearMonth(2027, 10))

        await viewModel.select(year: 2000, month: 1)
        #expect(!viewModel.canGoPrevious)
        #expect(viewModel.canGoNext)
        let callsAtLowerEnd = fakes.fetch.calls.count
        await viewModel.go(by: -1)
        #expect(fakes.fetch.calls.count == callsAtLowerEnd)
        #expect(viewModel.month == yearMonth(2000, 1))

        await viewModel.select(year: 2026, month: 12)
        await viewModel.go(by: 1)
        #expect(fakes.fetch.calls.last == yearMonth(2027, 1))
        #expect(viewModel.phase.shownMonth == yearMonth(2027, 1))
        await viewModel.go(by: -1)
        #expect(fakes.fetch.calls.last == yearMonth(2026, 12))
    }

    @Test("피커 저장은 고른 달을 로딩부터 읽고, 범위 밖 달은 읽지도 옮기지도 않는다")
    func selectLoadsChosenMonthAndIgnoresOutOfRange() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        fakes.fetch.holds = true

        let pick = Task { await viewModel.select(year: 2025, month: 3) }
        await waitUntil { fakes.fetch.isHeld(1) }
        #expect(viewModel.phase.isLoading)
        #expect(viewModel.month == yearMonth(2025, 3))
        #expect(fakes.fetch.calls.last == yearMonth(2025, 3))
        fakes.fetch.release(1)
        await pick.value
        #expect(viewModel.phase.shownMonth == yearMonth(2025, 3))

        fakes.fetch.holds = false
        await viewModel.select(year: 2027, month: 11)
        await viewModel.select(year: 1999, month: 12)
        // 1~12 밖의 달은 이웃 해의 달로 넘기지 않는다 — 2026-13 이 2027-01 로 읽히면 안 된다.
        await viewModel.select(year: 2026, month: 13)
        await viewModel.select(year: 2026, month: 0)
        #expect(fakes.fetch.calls.count == 2)
        #expect(viewModel.month == yearMonth(2025, 3))
        #expect(viewModel.phase.shownMonth == yearMonth(2025, 3))
    }

    @Test("받아들인 응답의 이번 달이 서버의 이번 달이 된다 — 다음 달 상한이 함께 늘어난다")
    func serverMonthFollowsLatestResponse() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        await viewModel.select(year: 2027, month: 11)
        #expect(fakes.fetch.calls.count == 1)

        fakes.fetch.result = { .success(makeBudget($0, current: yearMonth(2026, 11))) }
        await viewModel.handle(.foreground)
        #expect(viewModel.serverMonth == yearMonth(2026, 11))
        #expect(viewModel.pickerMonths(inYear: 2027) == 1 ... 11)

        await viewModel.select(year: 2027, month: 11)
        #expect(fakes.fetch.calls.last == yearMonth(2027, 11))
        #expect(viewModel.month == yearMonth(2027, 11))
        #expect(!viewModel.canGoNext)
    }

    @Test("마지막에 시작한 읽기의 응답만 받아들인다 — 늦게 온 옛 응답은 화면도 서버의 이번 달도 바꾸지 않는다")
    func staleResponsesAreDropped() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        fakes.fetch.holds = true

        // ① 달 넘김 두 번 — 첫 응답(이번 달 12 를 담은)이 나중에 온다.
        let toNovember = Task { await viewModel.go(by: 1) }
        await waitUntil { fakes.fetch.isHeld(1) }
        let toDecember = Task { await viewModel.go(by: 1) }
        await waitUntil { fakes.fetch.isHeld(2) }
        fakes.fetch.release(2)
        await toDecember.value
        fakes.fetch.release(1, with: .success(makeBudget(yearMonth(2026, 11), current: yearMonth(2026, 12))))
        await toNovember.value
        #expect(viewModel.month == yearMonth(2026, 12))
        #expect(viewModel.phase.shownMonth == yearMonth(2026, 12))

        // ② 다시 읽기를 시작한 뒤 달 넘김 — 옛 다시 읽기의 실패가 나중에 와도 버린다.
        let refresh = Task { await viewModel.handle(.ledgerChanged) }
        await waitUntil { fakes.fetch.isHeld(3) }
        let back = Task { await viewModel.go(by: -1) }
        await waitUntil { fakes.fetch.isHeld(4) }
        fakes.fetch.release(4)
        await back.value
        fakes.fetch.release(3, with: .failure(BudgetTabTestError.offline))
        await refresh.value
        #expect(viewModel.month == yearMonth(2026, 11))
        #expect(viewModel.phase.shownMonth == yearMonth(2026, 11))

        // ③ 버린 응답의 이번 달(12)은 서버의 이번 달을 바꾸지 않는다.
        #expect(viewModel.serverMonth == yearMonth(2026, 10))
    }

    @Test("피커의 해·달 범위는 화살표 범위와 같고, 서버의 이번 달을 모르면 범위가 없다")
    func pickerRangeMatchesArrowRange() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        #expect(viewModel.pickerYears == nil)

        await viewModel.handle(.tabShown)

        #expect(viewModel.pickerYears == 2000 ... 2027)
        #expect(viewModel.pickerMonths(inYear: 2027) == 1 ... 10)
        #expect(viewModel.pickerMonths(inYear: 2026) == 1 ... 12)
        #expect(viewModel.pickerMonths(inYear: 2000) == 1 ... 12)
    }
}

// MARK: 다시 읽기

extension BudgetTabViewModelTests {
    @Test("다시 읽는 동안 보던 내용을 그대로 두고(로딩 아님), 응답이 오면 새 값으로 바꾼다")
    func refreshKeepsContentWhileReading() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        fakes.fetch.result = { .success(makeBudget($0, total: makeLine(spent: 200))) }
        fakes.fetch.holds = true

        let refresh = Task { await viewModel.handle(.ledgerChanged) }
        await waitUntil { fakes.fetch.isHeld(1) }
        #expect(!viewModel.phase.isLoading)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 100)

        fakes.fetch.release(1)
        await refresh.value
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 200)
    }

    @Test("다시 읽기가 실패하면 옛 숫자를 남기지 않고 불러올 수 없음이다")
    func refreshFailureShowsFailed() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(viewModel.phase.content != nil)

        fakes.fetch.result = { _ in .failure(BudgetTabTestError.offline) }
        await viewModel.handle(.foreground)

        #expect(viewModel.phase.isFailed)
        #expect(viewModel.phase.content == nil)
        #expect(!viewModel.showsEditButton)
        #expect(viewModel.showsMonthHeader)
    }

    @Test("서버 달 확인이 실패한 뒤 다시 읽으면 확인부터 다시 하고, 응답 전까지 불러올 수 없음을 유지한다")
    func refreshAfterProbeFailureProbesAgain() async {
        let fakes = BudgetTabFakes()
        fakes.probe.result = { _ in .failure(BudgetTabTestError.offline) }
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(viewModel.phase.isFailed)
        #expect(viewModel.serverMonth == nil)

        fakes.probe.result = { _ in .success(yearMonth(2026, 10)) }
        fakes.probe.holds = true
        fakes.fetch.holds = true
        let refresh = Task { await viewModel.handle(.foreground) }
        await waitUntil { fakes.probe.isHeld(1) }
        #expect(viewModel.phase.isFailed)
        fakes.probe.release(1)
        await waitUntil { fakes.fetch.isHeld(0) }
        #expect(viewModel.phase.isFailed)

        fakes.fetch.release(0)
        await refresh.value
        #expect(fakes.probe.calls.count == 2)
        #expect(fakes.fetch.calls == [yearMonth(2026, 10)])
        #expect(viewModel.phase.content != nil)
        #expect(viewModel.showsMonthHeader)
    }

    @Test("비회원이던 탭도 신원이 생긴 뒤 다시 읽으면 서버 달 확인부터 정상 흐름으로 읽는다")
    func identityAppearingLaterStartsNormalFlow() async {
        let fakes = BudgetTabFakes()
        fakes.hasIdentity = false
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(viewModel.phase.isNoIdentity)

        fakes.hasIdentity = true
        await viewModel.handle(.ledgerChanged)

        #expect(fakes.probe.calls.count == 1)
        #expect(fakes.fetch.calls == [yearMonth(2026, 10)])
        #expect(viewModel.phase.content != nil)
        #expect(viewModel.showsMonthHeader)
    }

    @Test("탭이 보일 때만 다시 읽는다 — 첫 표시는 시작, 그 뒤 표시·앞으로 옴·원장 변경은 다시 읽기")
    func eventsRefreshOnlyWhileVisible() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()

        await viewModel.handle(.tabShown)
        #expect(fakes.probe.calls.count == 1)
        #expect(fakes.fetch.calls.count == 1)
        await viewModel.handle(.tabShown)
        #expect(fakes.probe.calls.count == 1)
        #expect(fakes.fetch.calls.count == 2)

        await viewModel.handle(.tabHidden)
        await viewModel.handle(.ledgerChanged)
        await viewModel.handle(.foreground)
        #expect(fakes.fetch.calls.count == 2)

        await viewModel.handle(.tabShown)
        #expect(fakes.fetch.calls.count == 3)
        await viewModel.handle(.ledgerChanged)
        #expect(fakes.fetch.calls.count == 4)
        await viewModel.handle(.foreground)
        #expect(fakes.fetch.calls.count == 5)
        #expect(fakes.probe.calls.count == 1)
    }

    @Test("연결 회복은 탭이 보이고 불러올 수 없음일 때만 다시 읽는다")
    func connectivityRestoredRefreshesOnlyWhenFailed() async {
        let fakes = BudgetTabFakes()
        fakes.fetch.result = { _ in .failure(BudgetTabTestError.offline) }
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(viewModel.phase.isFailed)

        fakes.fetch.result = { .success(makeBudget($0)) }
        await viewModel.handle(.connectivityRestored)
        #expect(fakes.fetch.calls.count == 2)
        #expect(viewModel.phase.content != nil)

        await viewModel.handle(.connectivityRestored)
        #expect(fakes.fetch.calls.count == 2)

        fakes.fetch.result = { _ in .failure(BudgetTabTestError.offline) }
        await viewModel.handle(.foreground)
        #expect(viewModel.phase.isFailed)
        await viewModel.handle(.tabHidden)
        fakes.fetch.result = { .success(makeBudget($0)) }
        await viewModel.handle(.connectivityRestored)
        #expect(fakes.fetch.calls.count == 3)
        #expect(viewModel.phase.isFailed)
    }

    @Test("탭이 숨겨진 채 신원이 바뀌면 즉시 상태를 버리고, 다음 표시는 서버 달 확인부터 시작한다")
    func identityChangedWhileHiddenResets() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        await viewModel.handle(.tabHidden)

        await viewModel.handle(.identityChanged)
        #expect(viewModel.month == nil)
        #expect(viewModel.serverMonth == nil)
        #expect(viewModel.phase.content == nil)
        #expect(!viewModel.showsMonthHeader)
        #expect(fakes.probe.calls.count == 1)

        fakes.probe.holds = true
        let reshow = Task { await viewModel.handle(.tabShown) }
        await waitUntil { fakes.probe.isHeld(1) }
        #expect(viewModel.phase.isLoading)
        fakes.probe.release(1)
        await reshow.value
        #expect(viewModel.phase.content != nil)

        // 로그아웃: 신원이 없어진 뒤 다음 표시는 비회원이고 서버를 부르지 않는다.
        await viewModel.handle(.tabHidden)
        fakes.hasIdentity = false
        await viewModel.handle(.identityChanged)
        let fetchCalls = fakes.fetch.calls.count
        await viewModel.handle(.tabShown)
        #expect(viewModel.phase.isNoIdentity)
        #expect(fakes.fetch.calls.count == fetchCalls)
        #expect(fakes.probe.calls.count == 2)
    }

    @Test("탭이 보이는 채 신원이 바뀌면 상태를 버리고 바로 서버 달 확인부터 다시 시작한다")
    func identityChangedWhileVisibleRestarts() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 100)

        fakes.fetch.result = { .success(makeBudget($0, total: makeLine(spent: 200))) }
        fakes.probe.holds = true
        let change = Task { await viewModel.handle(.identityChanged) }
        await waitUntil { fakes.probe.isHeld(1) }
        #expect(viewModel.phase.isLoading)
        #expect(viewModel.serverMonth == nil)
        fakes.probe.release(1)
        await change.value
        #expect(fakes.probe.calls.count == 2)
        #expect(fakes.fetch.calls.count == 2)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 200)
        #expect(viewModel.showsMonthHeader)

        // 로그아웃: 보이는 채 신원이 없어지면 바로 비회원이고 서버를 부르지 않는다.
        fakes.hasIdentity = false
        await viewModel.handle(.identityChanged)
        #expect(viewModel.phase.isNoIdentity)
        #expect(fakes.probe.calls.count == 2)
        #expect(fakes.fetch.calls.count == 2)
        #expect(!viewModel.showsMonthHeader)
    }

    @Test("읽는 중에 신원이 바뀌면 그 응답을 버린다 — 옛 계정의 숫자·달이 새 계정 화면에 남지 않는다")
    func identityChangeDropsInFlightRead() async {
        let fakes = BudgetTabFakes()
        fakes.fetch.holds = true
        let viewModel = fakes.makeViewModel()
        let start = Task { await viewModel.handle(.tabShown) }
        await waitUntil { fakes.fetch.isHeld(0) }

        // 보이는 중이라 바로 다시 시작한다 — 새 계정의 서버 달 확인을 붙잡아 둔 채 옛 응답을 보낸다.
        fakes.probe.holds = true
        let change = Task { await viewModel.handle(.identityChanged) }
        await waitUntil { fakes.probe.isHeld(1) }
        fakes.fetch.release(0)
        await start.value
        #expect(viewModel.phase.content == nil)
        #expect(viewModel.serverMonth == nil)
        #expect(viewModel.month == nil)

        // 서버 달 확인 중에 바뀌어도 그 응답으로 달을 정하거나 예산을 읽지 않는다.
        let changeAgain = Task { await viewModel.handle(.identityChanged) }
        await waitUntil { fakes.probe.isHeld(2) }
        fakes.probe.release(1)
        await change.value
        #expect(viewModel.serverMonth == nil)
        #expect(fakes.fetch.calls.count == 1)

        fakes.fetch.holds = false
        fakes.probe.release(2)
        await changeAgain.value
        #expect(fakes.fetch.calls.count == 2)
        #expect(viewModel.phase.content != nil)
    }

    @Test("계약 불변식이 깨진 응답은 불러올 수 없음 — 미설정·초과처럼 비어도 되는 자리는 정상이다")
    func contractViolationShowsFailed() async {
        let october = yearMonth(2026, 10)
        let broken = [
            makeBudget(october, total: nil),
            makeBudget(october, currency: nil),
            makeBudget(october, total: makeLine(status: .nearLimit, percent: nil)),
            makeBudget(october, total: makeLine(status: .inProgress, percent: nil))
        ]
        for budget in broken {
            let phase = await phaseAfterStart(returning: budget)
            #expect(phase.isFailed)
        }

        let wellFormed = [
            makeNotSetBudget(october),
            makeBudget(october, status: .exceeded, total: makeOverLine())
        ]
        for budget in wellFormed {
            let phase = await phaseAfterStart(returning: budget)
            #expect(phase.content != nil)
        }
    }

    @Test("예산이 있는 달에 결제수단 세 묶음이 하나씩 없거나 그 외 카테고리 줄이 없으면 불러올 수 없음이다")
    func brokenBreakdownShowsFailed() async {
        let october = yearMonth(2026, 10)
        let broken = [
            makeBudget(october, paymentGroups: makePaymentGroups([.creditCard, .cashAndDebit])),
            makeBudget(october, paymentGroups: makePaymentGroups([.creditCard, .creditCard, .accountAndOther])),
            makeBudget(october, otherCategories: nil)
        ]
        for budget in broken {
            let phase = await phaseAfterStart(returning: budget)
            #expect(phase.isFailed)
        }

        let notSet = makeNotSetBudget(october)
        #expect(notSet.paymentGroups.isEmpty)
        #expect(notSet.otherCategories == nil)
        let withBudget = makeBudget(october)
        #expect(withBudget.paymentGroups.count == 3)
        #expect(withBudget.otherCategories != nil)
        for budget in [notSet, withBudget] {
            let phase = await phaseAfterStart(returning: budget)
            #expect(phase.content != nil)
        }
    }
}

// MARK: 하루 권장·남은 일수 불변식

extension BudgetTabViewModelTests {
    @Test("예산이 있는 달에 하루 권장의 금액 없음과 초과가 어긋나거나 남은 일수가 이번 달·그 달 일수와 어긋나면 불러올 수 없음이다")
    func brokenDailyAndDaysShowsFailed() async {
        // 인계 2026-09-29 :96 — 초과면 금액 null·초과 true, 정확히 100% 면 금액 0·초과 false.
        // v2 :46 — 남은 일수는 요청한 달이 이번 달일 때만 있다. 10월은 31일이다.
        let october = yearMonth(2026, 10)
        let broken = [
            makeBudget(october, dailyAllowance: DailyAllowance(amount: nil, isExceeded: false)),
            makeBudget(october, dailyAllowance: DailyAllowance(amount: 0, isExceeded: true)),
            makeBudget(yearMonth(2026, 9), remainingDays: 7),
            makeBudget(october, remainingDays: .some(nil)),
            makeBudget(october, remainingDays: 0),
            makeBudget(october, remainingDays: 32)
        ]
        for budget in broken {
            let phase = await phaseAfterStart(returning: budget)
            #expect(phase.isFailed)
        }

        let wellFormed = [
            makeBudget(october, dailyAllowance: DailyAllowance(amount: nil, isExceeded: true)),
            makeBudget(october, dailyAllowance: DailyAllowance(amount: 0, isExceeded: false)),
            makeBudget(october, remainingDays: 1),
            makeBudget(october, remainingDays: 31)
        ]
        for budget in wellFormed {
            let phase = await phaseAfterStart(returning: budget)
            #expect(phase.content != nil)
        }
    }
}

// MARK: 줄 계약 — 검사를 지난 응답은 카드가 늘 그려진다

extension BudgetTabViewModelTests {
    @Test("예산이 있는 달의 줄이 계약과 어긋나면(전체의 몫·상태·남은 돈·넘은 돈 없음, 몫 있는 하위 줄의 상태·넘은 돈 없음, 몫 없는 하위 줄에 상태 등이 있음) 불러올 수 없음이다")
    func malformedLinesFailRead() async {
        for budget in makeMalformedLineBudgets() {
            let phase = await phaseAfterStart(returning: budget)
            #expect(phase.isFailed)
        }

        // 짝: 깨뜨리지 않은 같은 응답은 읽힌다(그 외 카테고리는 몫 없는 줄과 몫 있는 줄 둘 다).
        for budget in [makeLinesBudget(), makeLinesBudget(otherCategories: makeOverLine())] {
            let phase = await phaseAfterStart(returning: budget)
            #expect(phase.content != nil)
        }
    }

    @Test("미설정 응답에 통화·전체·결제수단·카테고리·그 외 카테고리·하루 권장 중 하나라도 있거나 남은 일수가 이번 달과 어긋나면 불러올 수 없음이다")
    func notSetContradictionsFailRead() async {
        // v2 :49-55 — 미설정이면 통화·전체·그 외 카테고리는 null, 결제수단은 [], 하루 권장은 예산이 있을 때만이다.
        // 카테고리도 [] 다(백엔드 `MonthlyBudgetResponse.notSet`). v2 :46 — 남은 일수는 예산이 없어도 이번 달이면 준다.
        let october = yearMonth(2026, 10)
        let september = yearMonth(2026, 9)
        for budget in [makeNotSetBudget(october), makeNotSetBudget(september)] {
            let phase = await phaseAfterStart(returning: budget)
            #expect(phase.content?.budget.status == .notSet)
        }

        let deletedLine = BudgetCategoryLine(category: makeCategory(id: 1), isDeleted: true, line: makeLine())
        let contradictions = [
            makeNotSetBudget(october, currency: .krw),
            makeNotSetBudget(october, total: makeLine()),
            makeNotSetBudget(october, paymentGroups: makePaymentGroups()),
            makeNotSetBudget(october, categories: [deletedLine]),
            makeNotSetBudget(october, otherCategories: makeSpentOnlyLine(40)),
            makeNotSetBudget(october, dailyAllowance: DailyAllowance(amount: 100, isExceeded: false)),
            makeNotSetBudget(october, remainingDays: .some(nil)),
            makeNotSetBudget(september, remainingDays: 7)
        ]
        for budget in contradictions {
            let phase = await phaseAfterStart(returning: budget)
            #expect(phase.isFailed)
        }
    }

    @Test("계약 검사를 지난 응답은 총액·카테고리·결제수단 카드를 ko·en 모두 그릴 수 있다")
    func wellFormedResponsesAlwaysRender() {
        let wellFormed = makeWellFormedBudgets()
        for budget in wellFormed {
            #expect(BudgetTabViewModel.isWellFormed(budget))
        }

        // 깨진 응답도 넣는다 — 검사가 놓친 응답은 카드가 말없이 빈다.
        for budget in wellFormed + makeMalformedLineBudgets() where BudgetTabViewModel.isWellFormed(budget) {
            let content = BudgetTabContent(budget: budget, unsyncedExpenseCount: 1, pendingDeletionCategoryIDs: [2])
            for language in AppLanguage.allCases {
                #expect(BudgetTotalPresentation(content: content, language: language) != nil)
                #expect(BudgetBreakdownPresentation(content: content, language: language) != nil)
            }
        }
    }

    @Test("UI 테스트의 가짜 응답(-uiTestBudgetSet·NotSet)은 이번 달·다른 달 모두 계약 검사를 지난다")
    func uiTestFixturesAreWellFormed() throws {
        let catalog = CatalogProvider(
            expenseCategories: [makeCategory(id: 1), makeCategory(id: 2)],
            incomeCategories: [],
            assets: []
        )
        let months = [
            UITestSupport.BudgetScenario.serverMonth,
            yearMonth(2026, 9),
            yearMonth(2027, 10)
        ]
        for scenario in [UITestSupport.BudgetScenario.setMonth, .notSet] {
            for month in months {
                let budget = try scenario.fetch(year: month.year, month: month.month, catalog: catalog)
                #expect(BudgetTabViewModel.isWellFormed(budget))
            }
        }
        let current = try UITestSupport.BudgetScenario.setMonth.fetch(year: 2026, month: 10, catalog: catalog)
        #expect(current.categories.count == 2)
        #expect(current.categories.contains { $0.line.status == .exceeded })
    }
}

// MARK: 사건 전달 — 루트는 send·observe 만 부른다

extension BudgetTabViewModelTests {
    @Test("보임·숨김은 send 를 부른 그 자리에서 바뀐다 — 빠른 탭 전환의 결과가 작업이 도는 순서에 갈리지 않는다")
    func sendAppliesVisibilityImmediately() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        await viewModel.handle(.tabHidden)
        let fetchCount = fakes.fetch.calls.count

        let shown = viewModel.send(.tabShown)
        #expect(viewModel.isVisible)
        let hidden = viewModel.send(.tabHidden)
        #expect(!viewModel.isVisible)
        await shown.value
        await hidden.value
        // 다시 읽기는 작업이 돌 때의 상태로 판정한다 — 이미 숨겨졌으니 표시의 작업도 읽지 않는다.
        await viewModel.send(.ledgerChanged).value
        #expect(fakes.fetch.calls.count == fetchCount)

        // 표시의 작업을 기다리지 않아도 보임은 이미 반영돼, 원장 변경이 다시 읽는다.
        let reshown = viewModel.send(.tabShown)
        await viewModel.send(.ledgerChanged).value
        #expect(fakes.fetch.calls.count > fetchCount)
        await reshown.value
    }

    @Test("신원이 바뀌면 send 를 부른 그 자리에서 앞 계정의 상태를 버린다")
    func sendIdentityChangeResetsImmediately() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(viewModel.phase.content != nil)
        #expect(viewModel.month != nil)

        let change = viewModel.send(.identityChanged)
        #expect(viewModel.phase.isLoading)
        #expect(viewModel.month == nil)
        #expect(viewModel.serverMonth == nil)

        await change.value
        #expect(fakes.probe.calls.count == 2)
        #expect(viewModel.phase.content != nil)
    }

    @Test("예산으로 오면 표시, 예산에서 떠나면 숨김, 예산과 상관없는 전환은 사건이 없다")
    func tabChangeMapsToEvents() {
        #expect(BudgetTabViewModel.event(fromTab: .ledger, toTab: .budget) == .tabShown)
        #expect(BudgetTabViewModel.event(fromTab: .budget, toTab: .settings) == .tabHidden)
        #expect(BudgetTabViewModel.event(fromTab: .budget, toTab: .ledger) == .tabHidden)
        #expect(BudgetTabViewModel.event(fromTab: .ledger, toTab: .settings) == nil)
        #expect(BudgetTabViewModel.event(fromTab: .report, toTab: .budget) == .tabShown)
    }

    @Test("원장 변경 스트림의 신호는 탭이 보일 때만 다시 읽는다")
    func ledgerStreamReloadsOnlyWhileVisible() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        let fetchCount = fakes.fetch.calls.count

        await viewModel.observeLedgerChanges(finishedStream([()]))
        await waitUntil { fakes.fetch.calls.count == fetchCount + 1 }

        await viewModel.handle(.tabHidden)
        await viewModel.observeLedgerChanges(finishedStream([()]))
        await settleMainActor()
        #expect(fakes.fetch.calls.count == fetchCount + 1)
    }

    @Test("연결 스트림은 다시 연결됐을 때(true)만, 탭이 보이고 불러올 수 없음일 때만 다시 읽는다")
    func connectivityStreamReloadsOnlyOnRestoreAfterFailure() async {
        let fakes = BudgetTabFakes()
        fakes.fetch.result = { _ in .failure(BudgetTabTestError.offline) }
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(viewModel.phase.isFailed)
        let fetchCount = fakes.fetch.calls.count

        await viewModel.observeConnectivity(finishedStream([false]))
        await settleMainActor()
        #expect(fakes.fetch.calls.count == fetchCount)

        fakes.fetch.result = { .success(makeBudget($0)) }
        await viewModel.observeConnectivity(finishedStream([true]))
        await waitUntil { viewModel.phase.content != nil }
        #expect(fakes.fetch.calls.count == fetchCount + 1)

        await viewModel.observeConnectivity(finishedStream([true]))
        await settleMainActor()
        #expect(fakes.fetch.calls.count == fetchCount + 1)
    }
}

// MARK: 쓰기 응답 — 편집 화면의 저장·삭제

extension BudgetTabViewModelTests {
    @Test("쓰기 응답은 서버를 다시 부르지 않고 그 응답의 달로 옮겨 보인다 — 동기화 전 건수·삭제 대기 ID 는 그 달로 다시 센다")
    func writeResponseReplacesShownMonth() async throws {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        let november = yearMonth(2026, 11)
        fakes.unsynced.result = { _ in .success(5) }
        fakes.pendingIDs = .success([3])

        let written = makeBudget(november, total: makeLine(spent: 300))
        let applied = await viewModel.applyWrite(written, token: viewModel.beginWrite())

        #expect(applied)
        #expect(fakes.fetch.calls == [yearMonth(2026, 10)])
        #expect(fakes.unsynced.calls.last == november)
        #expect(viewModel.month == november)
        #expect(viewModel.phase.shownMonth == november)
        let content = try #require(viewModel.phase.content)
        #expect(content.budget.total?.actualAmount == 300)
        #expect(content.unsyncedExpenseCount == 5)
        #expect(content.pendingDeletionCategoryIDs == [3])
    }

    @Test("쓰기 응답 전에 시작한 읽기는 늦게 와도 버린다 — 쓰기 응답 뒤에 시작한 읽기는 이기고 쓰기는 반영된 것으로 친다")
    func writeDiscardsReadStartedBefore() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        let october = yearMonth(2026, 10)

        // 옛 값(사용액 100)을 읽는 다시 읽기를 붙잡아 둔 채 쓰기 응답(300)이 온다.
        fakes.fetch.holds = true
        let token = viewModel.beginWrite()
        let refresh = Task { await viewModel.handle(.foreground) }
        await waitUntil { fakes.fetch.isHeld(1) }
        let applied = await viewModel.applyWrite(makeBudget(october, total: makeLine(spent: 300)), token: token)
        fakes.fetch.release(1)
        await refresh.value
        #expect(applied)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 300)

        // 짝: 쓰기 응답을 받아 로컬을 다시 세는 사이 시작한 읽기(쓰기 뒤의 서버 값 400)가 이긴다(스펙 :279 규칙 3).
        fakes.fetch.holds = false
        fakes.fetch.result = { .success(makeBudget($0, total: makeLine(spent: 400))) }
        fakes.unsynced.holds = true
        let writeIndex = fakes.unsynced.calls.count
        let written = makeBudget(october, total: makeLine(spent: 500))
        let write = Task { await viewModel.applyWrite(written, token: viewModel.beginWrite()) }
        await waitUntil { fakes.unsynced.isHeld(writeIndex) }
        let later = Task { await viewModel.handle(.ledgerChanged) }
        await waitUntil { fakes.unsynced.isHeld(writeIndex + 1) }
        fakes.unsynced.release(writeIndex + 1)
        await later.value
        fakes.unsynced.release(writeIndex)
        let laterWon = await write.value
        #expect(laterWon)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 400)
    }

    @Test("쓰기를 시작한 뒤 신원이 바뀌었으면 그 쓰기 응답을 버리고 false — 같은 신원이면 반영하고 true")
    func writeAfterIdentityChangeIsIgnored() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        let written = makeBudget(yearMonth(2026, 11), total: makeLine(spent: 300))

        let staleToken = viewModel.beginWrite()
        await viewModel.handle(.identityChanged)
        let discarded = await viewModel.applyWrite(written, token: staleToken)
        #expect(!discarded)
        #expect(viewModel.month == yearMonth(2026, 10))
        #expect(viewModel.phase.shownMonth == yearMonth(2026, 10))
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 100)

        // 짝: 신원 변경 없이 받은 표면 반영한다.
        let applied = await viewModel.applyWrite(written, token: viewModel.beginWrite())
        #expect(applied)
        #expect(viewModel.phase.shownMonth == yearMonth(2026, 11))
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 300)

        // 응답을 받아 로컬을 다시 세는 사이 신원이 바뀌어도 버린다 — 새 계정 탭에 남의 저장을 보이지 않는다.
        fakes.unsynced.holds = true
        let heldIndex = fakes.unsynced.calls.count
        let lateToken = viewModel.beginWrite()
        let late = Task { await viewModel.applyWrite(makeBudget(yearMonth(2026, 12)), token: lateToken) }
        await waitUntil { fakes.unsynced.isHeld(heldIndex) }
        fakes.unsynced.holds = false
        await viewModel.handle(.identityChanged)
        fakes.unsynced.release(heldIndex)
        let lateApplied = await late.value
        #expect(!lateApplied)
        #expect(viewModel.month == yearMonth(2026, 10))
        #expect(viewModel.phase.shownMonth == yearMonth(2026, 10))
    }

    @Test("계약과 어긋난 쓰기 응답·로컬 읽기 실패는 불러올 수 없음이고 false — 맞는 응답은 보인다")
    func malformedWriteShowsFailed() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        let october = yearMonth(2026, 10)

        let malformed = makeBudget(october, paymentGroups: makePaymentGroups([.creditCard, .cashAndDebit]))
        let malformedApplied = await viewModel.applyWrite(malformed, token: viewModel.beginWrite())
        #expect(!malformedApplied)
        #expect(viewModel.phase.isFailed)

        let wellFormedApplied = await viewModel.applyWrite(makeBudget(october), token: viewModel.beginWrite())
        #expect(wellFormedApplied)
        #expect(viewModel.phase.shownMonth == october)

        // 다른 달의 계약 위반 응답도 그 달로 옮긴다 — 편집에서 마지막으로 보던 달이다. 서버의 이번 달은 믿을 수 없는 응답이라 두고 간다.
        let malformedNovember = makeBudget(
            yearMonth(2026, 11),
            current: yearMonth(2027, 1),
            paymentGroups: makePaymentGroups([.creditCard])
        )
        let malformedNovemberApplied = await viewModel.applyWrite(malformedNovember, token: viewModel.beginWrite())
        #expect(!malformedNovemberApplied)
        #expect(viewModel.month == yearMonth(2026, 11))
        #expect(viewModel.phase.isFailed)
        #expect(viewModel.serverMonth == october)

        fakes.unsynced.result = { _ in .failure(BudgetTabTestError.database) }
        let localFailedApplied = await viewModel.applyWrite(makeBudget(october), token: viewModel.beginWrite())
        #expect(!localFailedApplied)
        #expect(viewModel.phase.isFailed)
    }

    @Test("신원 없이 시작한 탭도 첫 저장 응답을 보인다 — 서버의 이번 달은 서버 시각 확인 없이 응답에서 얻는다")
    func memberlessFirstWriteShowsResponse() async {
        let fakes = BudgetTabFakes()
        fakes.hasIdentity = false
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(viewModel.phase.isNoIdentity)
        #expect(!viewModel.showsMonthHeader)

        // 탭의 `.identityChanged` 는 `identityResetGeneration` 이 바뀔 때만 온다(`BudgetTabEventForwarding` 의
        // `.onChange(of: identityResetGeneration)`) — 익명 신원 발급은
        // 그 값을 올리지 않는다. 저장은 발급 뒤에 표를 받는다(스펙 :281 '저장은 발급 뒤에 시작하므로 4에 걸리지 않는다').
        // 기기 시계의 달과 겹치지 않는 달 — 기기 달로 범위를 정하면 여기서 어긋난다.
        fakes.hasIdentity = true
        let token = viewModel.beginWrite()
        let month = yearMonth(2031, 3)
        let applied = await viewModel.applyWrite(makeBudget(month, current: month), token: token)

        #expect(applied)
        #expect(viewModel.phase.shownMonth == month)
        #expect(viewModel.month == month)
        #expect(viewModel.serverMonth == month)
        #expect(viewModel.showsMonthHeader)
        #expect(viewModel.canGoNext)
        #expect(viewModel.pickerYears == 2000 ... 2032)
        #expect(viewModel.pickerMonths(inYear: 2032) == 1 ... 3)
        #expect(fakes.probe.calls.isEmpty)
        #expect(fakes.fetch.calls.isEmpty)
    }
}

// MARK: 편집 열기·닫기

extension BudgetTabViewModelTests {
    @Test("편집이 닫히면 편집에서 마지막으로 보던 달을 읽는다 — 다른 달이면 달 넘김처럼 응답 전까지 로딩이다")
    func dismissMovesToEditedMonth() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        fakes.fetch.holds = true
        let november = yearMonth(2026, 11)

        let dismiss = Task { await viewModel.showAfterEdit(november) }
        await waitUntil { fakes.fetch.isHeld(1) }
        #expect(viewModel.phase.isLoading)
        #expect(viewModel.month == november)

        fakes.fetch.release(1)
        await dismiss.value
        #expect(fakes.fetch.calls == [yearMonth(2026, 10), november])
        #expect(viewModel.month == november)
        #expect(viewModel.phase.shownMonth == november)
    }

    @Test("편집이 닫힌 달이 보던 달이면 보던 내용을 둔 채(로딩 아님) 다시 읽고, 응답이 오면 새 값으로 바꾼다")
    func dismissSameMonthKeepsContentWhileReading() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        fakes.fetch.result = { .success(makeBudget($0, total: makeLine(spent: 200))) }
        fakes.fetch.holds = true

        let dismiss = Task { await viewModel.showAfterEdit(yearMonth(2026, 10)) }
        await waitUntil { fakes.fetch.isHeld(1) }
        #expect(!viewModel.phase.isLoading)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 100)

        fakes.fetch.release(1)
        await dismiss.value
        #expect(fakes.fetch.calls.last == yearMonth(2026, 10))
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 200)
    }

    @Test("신원 없는 비회원이 X 로 닫으면(달 없음) 서버를 부르지 않고 탭을 그대로 둔다")
    func memberlessDismissKeepsTab() async {
        let fakes = BudgetTabFakes()
        fakes.hasIdentity = false
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)

        await viewModel.showAfterEdit(nil)

        #expect(viewModel.phase.isNoIdentity)
        #expect(viewModel.month == nil)
        #expect(fakes.fetch.calls.isEmpty)
        #expect(fakes.probe.calls.isEmpty)

        // 짝: 신원이 생긴 뒤에도 달이 없으면 아무것도 하지 않는다.
        fakes.hasIdentity = true
        await viewModel.showAfterEdit(nil)

        #expect(viewModel.phase.isNoIdentity)
        #expect(fakes.fetch.calls.isEmpty)
        #expect(fakes.probe.calls.isEmpty)
    }

    @Test("서버의 이번 달을 모르는 탭도 신원이 생긴 뒤 다시 불러오라고 하면 범위 검사 없이 그 달을 읽는다 — 신원이 없으면 아무것도 하지 않는다")
    func memberlessReloadRequiredReadsMonth() async {
        let fakes = BudgetTabFakes()
        fakes.hasIdentity = false
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        // 기기 시계의 달과 겹치지 않는 달 — 기기 달로 범위를 정하면 여기서 어긋난다.
        let march = yearMonth(2031, 3)
        fakes.fetch.result = { .success(makeBudget($0, current: march)) }

        // 짝: 신원이 그대로 없으면 서버를 부르지 않는다.
        await viewModel.showAfterEdit(march)
        #expect(viewModel.phase.isNoIdentity)
        #expect(fakes.fetch.calls.isEmpty)
        #expect(fakes.probe.calls.isEmpty)

        fakes.hasIdentity = true
        await viewModel.showAfterEdit(march)

        #expect(fakes.fetch.calls == [march])
        #expect(viewModel.month == march)
        #expect(viewModel.phase.shownMonth == march)
        #expect(viewModel.showsMonthHeader)
        #expect(fakes.probe.calls.isEmpty)
    }

    @Test("회원은 보이는 달·범위 끝·보이던 응답으로 편집을 연다(서버를 다시 부르지 않음) — 불러올 수 없음이면 열 맥락이 없다")
    func memberEditContextCarriesShownBudget() async throws {
        let fakes = BudgetTabFakes()
        fakes.fetch.result = { .success(makeBudget($0, total: makeLine(spent: 250))) }
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)

        let context = try #require(await viewModel.editContext().context)
        #expect(context.month == yearMonth(2026, 10))
        #expect(context.lastMonth == yearMonth(2027, 10))
        let initial = try #require(context.initialBudget)
        #expect(yearMonth(initial.year, initial.month) == yearMonth(2026, 10))
        #expect(initial.total?.actualAmount == 250)
        #expect(fakes.probe.calls.count == 1)
        #expect(fakes.fetch.calls.count == 1)

        // 짝: 불러올 수 없음에는 `수정`·`예산 정하기` 가 없다.
        fakes.fetch.result = { _ in .failure(BudgetTabTestError.offline) }
        await viewModel.handle(.foreground)
        #expect(viewModel.phase.isFailed)
        let failedResult = await viewModel.editContext()
        #expect(failedResult.isUnavailable)
        #expect(fakes.probe.calls.count == 1)
    }

    @Test("신원 없는 비회원은 서버 시각을 한 번 확인해 그 달로 연다(범위 끝·응답 없음) — 확인이 실패하면 열지 않는다")
    func memberlessEditContextUsesServerMonth() async throws {
        let fakes = BudgetTabFakes()
        fakes.hasIdentity = false
        // 기기 시계의 달과 겹치지 않는 달 — 기기 달로 열면 여기서 어긋난다.
        let probed = yearMonth(2031, 3)
        fakes.probe.result = { _ in .success(probed) }
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(fakes.probe.calls.isEmpty)

        let context = try #require(await viewModel.editContext().context)
        #expect(context.month == probed)
        #expect(context.lastMonth == nil)
        #expect(context.initialBudget == nil)
        #expect(fakes.probe.calls.count == 1)
        #expect(fakes.fetch.calls.isEmpty)

        // 짝: 확인이 실패하면 기기 달로 대신 열지 않는다.
        fakes.probe.result = { _ in .failure(BudgetTabTestError.offline) }
        let failedResult = await viewModel.editContext()
        #expect(failedResult.isServerMonthFailed)
        #expect(viewModel.phase.isNoIdentity)
    }

    @Test("신원 없는 비회원의 서버 시각 확인 중 신원이 생기거나 바뀌면 열지 않는다 — 빈 초안 편집이 회원의 그 달 예산을 덮지 않게")
    func memberlessEditContextDroppedWhenIdentityAppears() async {
        let fakes = BudgetTabFakes()
        fakes.hasIdentity = false
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        fakes.probe.holds = true

        // 확인을 붙잡은 사이 로그인으로 신원이 생긴다 — 루트의 신원 변경 사건은 아직 오지 않았다.
        let appeared = Task { await viewModel.editContext() }
        await waitUntil { fakes.probe.isHeld(0) }
        fakes.hasIdentity = true
        fakes.probe.release(0)
        #expect(await appeared.value.isUnavailable)

        // 신원 변경 사건만 오고 신원은 여전히 없음으로 읽혀도 열지 않는다.
        fakes.hasIdentity = false
        let changed = Task { await viewModel.editContext() }
        await waitUntil { fakes.probe.isHeld(1) }
        await viewModel.handle(.identityChanged)
        #expect(viewModel.phase.isNoIdentity)
        fakes.probe.release(1)
        #expect(await changed.value.isUnavailable)

        // 확인이 실패해도 신원부터 다시 본다 — 새 계정 화면에 실패 토스트를 띄우지 않는다(스펙 :280 규칙 4).
        let failedAfterSignIn = Task { await viewModel.editContext() }
        await waitUntil { fakes.probe.isHeld(2) }
        fakes.hasIdentity = true
        fakes.probe.release(2, with: .failure(BudgetTabTestError.offline))
        #expect(await failedAfterSignIn.value.isUnavailable)

        // 짝: 신원이 그대로면 같은 실패가 확인 실패다.
        fakes.hasIdentity = false
        let failed = Task { await viewModel.editContext() }
        await waitUntil { fakes.probe.isHeld(3) }
        fakes.probe.release(3, with: .failure(BudgetTabTestError.offline))
        #expect(await failed.value.isServerMonthFailed)
    }
}

// MARK: 편집 회차 — 루트는 열고 닫는 일만, 반영과 토스트는 탭이 정한다

extension BudgetTabViewModelTests {
    @Test("편집 끝을 탭 토스트로 바꾼다 — 저장·삭제는 반영됐을 때만 토스트, 닫기는 없음, 다시 불러오기는 이유별")
    func finishEditMapsOutcomeToToast() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        let october = yearMonth(2026, 10)

        let saved = await viewModel.finishEdit(
            .saved(makeBudget(october, total: makeLine(spent: 300)), writeToken: viewModel.beginWrite()),
            session: viewModel.beginEdit()
        )
        #expect(saved == .saved)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 300)

        let deleted = await viewModel.finishEdit(
            .deleted(makeNotSetBudget(october), writeToken: viewModel.beginWrite()),
            session: viewModel.beginEdit()
        )
        #expect(deleted == .deleted)
        #expect(viewModel.phase.content?.budget.status == .notSet)

        // 쓰기를 시작한 뒤 신원이 바뀌었다 — 새 계정 탭에 남의 저장을 보이지도 알리지도 않는다.
        let staleToken = viewModel.beginWrite()
        await viewModel.handle(.identityChanged)
        let stale = await viewModel.finishEdit(
            .saved(makeBudget(october, total: makeLine(spent: 300)), writeToken: staleToken),
            session: viewModel.beginEdit()
        )
        #expect(stale == nil)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 100)

        let november = yearMonth(2026, 11)
        let dismissed = await viewModel.finishEdit(.dismissed(november), session: viewModel.beginEdit())
        #expect(dismissed == nil)
        #expect(fakes.fetch.calls.last == november)
        #expect(viewModel.phase.shownMonth == november)

        let december = yearMonth(2026, 12)
        let reloaded = await viewModel.finishEdit(
            .reloadRequired(december, .monthNotAllowed),
            session: viewModel.beginEdit()
        )
        #expect(reloaded == .reloaded(.monthNotAllowed))
        #expect(fakes.fetch.calls.last == december)
        #expect(viewModel.phase.shownMonth == december)
    }

    @Test("강제로 닫힌 편집의 늦은 끝은 반영도 다시 읽기도 토스트도 없다 — 닫히지 않은 편집의 끝은 반영한다")
    func finishAfterCancelIsIgnored() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        let fetchCount = fakes.fetch.calls.count
        let written = makeBudget(yearMonth(2026, 10), total: makeLine(spent: 300))

        let cancelled = viewModel.beginEdit()
        viewModel.cancelEdit()
        let ignored = await viewModel.finishEdit(
            .saved(written, writeToken: viewModel.beginWrite()),
            session: cancelled
        )
        #expect(ignored == nil)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 100)
        let ignoredReload = await viewModel.finishEdit(
            .reloadRequired(yearMonth(2026, 11), .categoryDeletedReloaded),
            session: cancelled
        )
        #expect(ignoredReload == nil)
        #expect(fakes.fetch.calls.count == fetchCount)
        #expect(viewModel.month == yearMonth(2026, 10))

        // 짝: 새로 띄운 편집의 끝은 반영한다 — 앞 회차의 늦은 끝은 새 편집을 닫지 않는다.
        let current = viewModel.beginEdit()
        let lateOld = await viewModel.finishEdit(.dismissed(yearMonth(2026, 11)), session: cancelled)
        #expect(lateOld == nil)
        let applied = await viewModel.finishEdit(.saved(written, writeToken: viewModel.beginWrite()), session: current)
        #expect(applied == .saved)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 300)

        // 끝을 반영하는 사이 강제로 닫혀도 토스트를 돌려주지 않는다 — 로그아웃 뒤 새 화면에 옛 편집의 안내가 뜨지 않게.
        fakes.fetch.holds = true
        let heldIndex = fakes.fetch.calls.count
        let midway = viewModel.beginEdit()
        let finishing = Task {
            await viewModel.finishEdit(.reloadRequired(yearMonth(2026, 11), .categoryDeletedReloaded), session: midway)
        }
        await waitUntil { fakes.fetch.isHeld(heldIndex) }
        viewModel.cancelEdit()
        fakes.fetch.release(heldIndex)
        #expect(await finishing.value == nil)
    }

    @Test("끝을 반영하는 사이 예산 탭을 떠나거나 신원이 바뀌면 토스트를 돌려주지 않는다 — 반영은 그대로 한다")
    func finishEditDropsToastWhenLeftOrIdentityChanged() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        let october = yearMonth(2026, 10)
        fakes.fetch.holds = true

        // 짝: 붙잡았다 놓아도 그 사이 아무 일이 없으면 토스트를 돌려준다.
        let keptIndex = fakes.fetch.calls.count
        let keptSession = viewModel.beginEdit()
        let kept = Task { await viewModel.finishEdit(.reloadRequired(october, .monthNotAllowed), session: keptSession) }
        await waitUntil { fakes.fetch.isHeld(keptIndex) }
        fakes.fetch.release(keptIndex)
        #expect(await kept.value == .reloaded(.monthNotAllowed))

        // 탭을 떠났다 — 읽은 값은 반영하지만 다른 탭 위에 토스트를 띄우지 않는다.
        fakes.fetch.result = { .success(makeBudget($0, total: makeLine(spent: 400))) }
        let leftIndex = fakes.fetch.calls.count
        let leftSession = viewModel.beginEdit()
        let left = Task { await viewModel.finishEdit(.reloadRequired(october, .monthNotAllowed), session: leftSession) }
        await waitUntil { fakes.fetch.isHeld(leftIndex) }
        await viewModel.handle(.tabHidden)
        fakes.fetch.release(leftIndex)
        #expect(await left.value == nil)
        #expect(viewModel.phase.content?.budget.total?.actualAmount == 400)

        // 신원이 바뀌었다 — 새 계정 탭에 옛 편집의 안내를 띄우지 않는다.
        fakes.fetch.holds = false
        await viewModel.handle(.tabShown)
        fakes.fetch.holds = true
        let changedIndex = fakes.fetch.calls.count
        let changedSession = viewModel.beginEdit()
        let changed = Task {
            await viewModel.finishEdit(.reloadRequired(october, .monthNotAllowed), session: changedSession)
        }
        await waitUntil { fakes.fetch.isHeld(changedIndex) }
        let restart = viewModel.send(.identityChanged)
        await waitUntil { fakes.fetch.isHeld(changedIndex + 1) }
        fakes.fetch.release(changedIndex)
        fakes.fetch.release(changedIndex + 1)
        await restart.value
        #expect(await changed.value == nil)
    }

    @Test("회원도 예산 탭이 숨겨져 있으면 열 맥락이 없다 — 다른 탭 위에 편집이 뜨지 않게")
    func memberEditContextUnavailableWhenHidden() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        await viewModel.handle(.tabHidden)
        #expect(viewModel.phase.content != nil)

        #expect(await viewModel.editContext().isUnavailable)

        // 짝: 다시 보이면 연다.
        await viewModel.handle(.tabShown)
        #expect(await viewModel.editContext().context != nil)
    }

    @Test("서버 시각을 확인하는 동안 다시 눌러도 바로 열 맥락이 없다(확인 1회) — 앞 확인이 끝난 뒤에는 다시 확인한다")
    func editContextIgnoresSecondTapWhileProbing() async {
        let fakes = BudgetTabFakes()
        fakes.hasIdentity = false
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        fakes.probe.holds = true

        let first = Task { await viewModel.editContext() }
        await waitUntil { fakes.probe.isHeld(0) }
        let second = await viewModel.editContext()
        #expect(second.isUnavailable)
        #expect(fakes.probe.calls.count == 1)
        fakes.probe.release(0)
        #expect(await first.value.context != nil)

        // 짝: 회차를 열지 않고 끝났으면 다시 눌렀을 때 다시 확인한다.
        fakes.probe.holds = false
        #expect(await viewModel.editContext().context != nil)
        #expect(fakes.probe.calls.count == 2)
    }

    @Test("편집이 떠 있는 동안에는 열 맥락이 없다 — 그 편집이 끝나면 다시 연다")
    func editContextUnavailableWhileEditOpen() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)

        let session = viewModel.beginEdit()
        #expect(await viewModel.editContext().isUnavailable)

        _ = await viewModel.finishEdit(.dismissed(nil), session: session)
        #expect(await viewModel.editContext().context != nil)
    }

    @Test("서버 시각을 확인하는 사이 예산 탭이 숨겨지면 열지 않는다 — 다른 탭 위에 편집이 뜨지 않게")
    func editContextDroppedWhenTabHidden() async {
        let fakes = BudgetTabFakes()
        fakes.hasIdentity = false
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        fakes.probe.holds = true

        let hidden = Task { await viewModel.editContext() }
        await waitUntil { fakes.probe.isHeld(0) }
        await viewModel.handle(.tabHidden)
        fakes.probe.release(0)
        #expect(await hidden.value.isUnavailable)

        // 짝: 다시 보이는 채 확인이 끝나면 연다.
        await viewModel.handle(.tabShown)
        let shown = Task { await viewModel.editContext() }
        await waitUntil { fakes.probe.isHeld(1) }
        fakes.probe.release(1)
        #expect(await shown.value.context != nil)
    }
}

// MARK: 편집 회차가 열려 있는지(알림 창 가림)

extension BudgetTabViewModelTests {
    @Test("B64N.S4-R3 편집 회차는 띄울 때 열리고, 닫힌 뒤 그 달을 다시 읽는 동안에도 열려 있다가 끝나면 닫힌다")
    func editSessionStaysOpenUntilFinishEnds() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        #expect(!viewModel.isEditSessionOpen)

        let session = viewModel.beginEdit()
        #expect(viewModel.isEditSessionOpen)

        fakes.fetch.holds = true
        let heldIndex = fakes.fetch.calls.count
        let finishing = Task { await viewModel.finishEdit(.dismissed(yearMonth(2026, 10)), session: session) }
        await waitUntil { fakes.fetch.isHeld(heldIndex) }
        // 모달은 이미 닫혔지만 결과 반영·토스트가 아직 정해지지 않았다.
        #expect(viewModel.isEditSessionOpen)

        fakes.fetch.release(heldIndex)
        _ = await finishing.value
        #expect(!viewModel.isEditSessionOpen)
    }

    @Test("B64N.S4-R3 강제로 닫힌 편집(신원 리셋)은 회차를 바로 닫는다")
    func cancelEditClosesEditSession() async {
        let fakes = BudgetTabFakes()
        let viewModel = fakes.makeViewModel()
        await viewModel.handle(.tabShown)
        _ = viewModel.beginEdit()
        #expect(viewModel.isEditSessionOpen)

        viewModel.cancelEdit()

        #expect(!viewModel.isEditSessionOpen)
    }
}

// MARK: 가짜 입력

private enum BudgetTabTestError: Error {
    case offline
    case database
}

/// 호출(인자 포함)을 기록하는 가짜 입력. `holds` 를 켜면 응답을 붙잡아 두고, 테스트가 `release` 로 시점을 정한다.
@MainActor
private final class FakeCall<Args, Value: Sendable> {
    var result: (Args) -> Result<Value, any Error>
    var holds = false
    private(set) var calls: [Args] = []
    private var held: [Int: CheckedContinuation<Value, any Error>] = [:]

    init(_ result: @escaping (Args) -> Result<Value, any Error>) {
        self.result = result
    }

    func call(_ args: Args) async throws -> Value {
        calls.append(args)
        guard holds else {
            return try result(args).get()
        }
        let index = calls.count - 1
        return try await withCheckedThrowingContinuation { held[index] = $0 }
    }

    func isHeld(_ index: Int) -> Bool {
        held[index] != nil
    }

    /// 붙잡은 `index` 번째 호출에 응답한다. `override` 가 없으면 지금의 `result` 로 답한다.
    func release(_ index: Int, with override: Result<Value, any Error>? = nil) {
        held.removeValue(forKey: index)?.resume(with: override ?? result(calls[index]))
    }
}

@MainActor
private final class BudgetTabFakes {
    let probe = FakeCall<Void, ServerMonth> { _ in .success(yearMonth(2026, 10)) }
    let fetch = FakeCall<ServerMonth, MonthlyBudget> { .success(makeBudget($0)) }
    let unsynced = FakeCall<ServerMonth, Int> { _ in .success(2) }
    var pendingIDs: Result<Set<Int>, any Error> = .success([7])
    var hasIdentity = true
    private(set) var pendingIDCalls = 0

    func makeViewModel() -> BudgetTabViewModel {
        BudgetTabViewModel(
            probeServerMonth: { try await self.probe.call(()) },
            fetch: { year, month in try await self.fetch.call(yearMonth(year, month)) },
            unsyncedExpenseCount: { year, month in try await self.unsynced.call(yearMonth(year, month)) },
            pendingDeletionCategoryIDs: {
                self.pendingIDCalls += 1
                return try self.pendingIDs.get()
            },
            hasIdentity: { self.hasIdentity }
        )
    }
}

@MainActor
private func phaseAfterStart(returning budget: MonthlyBudget) async -> BudgetTabViewModel.Phase {
    let fakes = BudgetTabFakes()
    fakes.fetch.result = { _ in .success(budget) }
    let viewModel = fakes.makeViewModel()
    await viewModel.handle(.tabShown)
    return viewModel.phase
}

/// 값을 모두 넣고 끝낸 스트림. 구독은 이것을 끝까지 읽고 돌아온다.
private func finishedStream<Element>(_ values: [Element]) -> AsyncStream<Element> {
    let (stream, continuation) = AsyncStream<Element>.makeStream()
    for value in values {
        continuation.yield(value)
    }
    continuation.finish()
    return stream
}

/// 구독은 사건이 시작한 다시 읽기를 기다리지 않는다. "읽지 않았다"를 세기 전에 main actor 에 쌓인 작업을 돌린다
/// (선례 `AppCompositionTests`).
@MainActor
private func settleMainActor() async {
    for _ in 0 ..< 100 {
        await Task.yield()
    }
}

@MainActor
private func yearMonth(_ year: Int, _ month: Int) -> ServerMonth {
    ServerMonth(year: year, month: month)
}

private func makeLine(
    budget: Decimal? = 1000,
    spent: Decimal = 100,
    status: BudgetStatus? = .inProgress,
    percent: Int? = 10,
    remaining: Decimal? = 900,
    over: Decimal? = nil
) -> BudgetLine {
    BudgetLine(
        budgetAmount: budget,
        actualAmount: spent,
        status: status,
        percent: percent,
        remainingAmount: remaining,
        overAmount: over
    )
}

/// 넘은 줄. 계약상 퍼센트·남은 돈은 null 이고 넘은 돈이 있다.
private func makeOverLine(over: Decimal? = 50) -> BudgetLine {
    makeLine(spent: 1050, status: .exceeded, percent: nil, remaining: nil, over: over)
}

/// 몫이 없는 줄 — 사용액만 있다.
private func makeSpentOnlyLine(_ spent: Decimal) -> BudgetLine {
    makeLine(budget: nil, spent: spent, status: nil, percent: nil, remaining: nil)
}

private func makeCategory(id: Int) -> woni_app.Category {
    Category(id: id, code: "FOOD", displayNameKo: "식비", displayNameEn: "Food", icon: "🍽️", sortOrder: id)
}

/// 결제수단 줄. 따로 적지 않으면 계약대로 세 묶음이 하나씩이다.
private func makePaymentGroups(
    _ groups: [PaymentGroup] = [.creditCard, .cashAndDebit, .accountAndOther]
) -> [BudgetPaymentGroupLine] {
    groups.map { BudgetPaymentGroupLine(paymentGroup: $0, line: makeLine()) }
}

/// 예산이 있는 달. 따로 적지 않으면 응답의 이번 달은 2026-10 이고, 결제수단 세 묶음과 그 외 카테고리 줄이 있다.
/// 남은 일수를 적지 않으면 계약대로 요청한 달이 응답의 이번 달일 때만 7, 아니면 nil 이다(`.some(nil)` 은 nil 그대로).
@MainActor
private func makeBudget(
    _ month: ServerMonth,
    current: ServerMonth = ServerMonth(year: 2026, month: 10),
    remainingDays: Int?? = nil,
    status: BudgetStatus = .inProgress,
    currency: CurrencyCode? = .krw,
    total: BudgetLine? = makeLine(),
    paymentGroups: [BudgetPaymentGroupLine] = makePaymentGroups(),
    categories: [BudgetCategoryLine] = [],
    otherCategories: BudgetLine? = makeLine(),
    dailyAllowance: DailyAllowance? = nil
) -> MonthlyBudget {
    MonthlyBudget(
        year: month.year,
        month: month.month,
        currentYear: current.year,
        currentMonth: current.month,
        remainingDaysIncludingToday: remainingDays ?? (month == current ? 7 : nil),
        hasAnyBudget: status != .notSet,
        status: status,
        currency: currency,
        total: total,
        paymentGroups: paymentGroups,
        categories: categories,
        otherCategories: otherCategories,
        missingRateCount: 0,
        dailyAllowance: dailyAllowance
    )
}

/// 미설정 달 — 계약상 통화·전체 줄·그 외 카테고리 줄·하루 권장이 null 이고 결제수단·카테고리는 [] 이다.
/// 남은 일수는 `makeBudget` 과 같다(이번 달만 7). 인자는 계약을 어긋나게 할 때만 준다.
@MainActor
private func makeNotSetBudget(
    _ month: ServerMonth,
    remainingDays: Int?? = nil,
    currency: CurrencyCode? = nil,
    total: BudgetLine? = nil,
    paymentGroups: [BudgetPaymentGroupLine] = [],
    categories: [BudgetCategoryLine] = [],
    otherCategories: BudgetLine? = nil,
    dailyAllowance: DailyAllowance? = nil
) -> MonthlyBudget {
    makeBudget(
        month,
        remainingDays: remainingDays,
        status: .notSet,
        currency: currency,
        total: total,
        paymentGroups: paymentGroups,
        categories: categories,
        otherCategories: otherCategories,
        dailyAllowance: dailyAllowance
    )
}

/// 2026-10 의 예산이 있는 달. 하위 줄은 몫 있는 줄(따로 적지 않으면 넘음)과 몫 없는 줄이 섞여 있다 —
/// 카테고리는 몫 있는 것 하나·없는 것 하나, 결제수단은 신용카드만 몫이 있고, 그 외 카테고리는 따로 적지 않으면 몫이 없다.
@MainActor
private func makeLinesBudget(
    total: BudgetLine = makeLine(),
    budgetedCategory: BudgetLine = makeOverLine(),
    creditCard: BudgetLine = makeOverLine(),
    otherCategories: BudgetLine = makeSpentOnlyLine(40)
) -> MonthlyBudget {
    makeBudget(
        yearMonth(2026, 10),
        status: total.status ?? .inProgress,
        total: total,
        paymentGroups: [
            BudgetPaymentGroupLine(paymentGroup: .creditCard, line: creditCard),
            BudgetPaymentGroupLine(paymentGroup: .cashAndDebit, line: makeSpentOnlyLine(30)),
            BudgetPaymentGroupLine(paymentGroup: .accountAndOther, line: makeSpentOnlyLine(0))
        ],
        categories: [
            BudgetCategoryLine(category: makeCategory(id: 1), isDeleted: false, line: budgetedCategory),
            BudgetCategoryLine(category: makeCategory(id: 2), isDeleted: false, line: makeSpentOnlyLine(20))
        ],
        otherCategories: otherCategories
    )
}

/// 예산이 있는 달의 정상 응답 — 전체 상태마다(진행 중·임박·도달·초과·지출 없음)와 0원 예산(지출 없음·넘음),
/// 지난 달(남은 일수 없음), 하루 권장이 있는 달.
@MainActor
private func makeWellFormedBudgets() -> [MonthlyBudget] {
    let october = yearMonth(2026, 10)
    return [
        makeBudget(october),
        makeBudget(yearMonth(2026, 9)),
        makeBudget(october, dailyAllowance: DailyAllowance(amount: 128, isExceeded: false)),
        makeLinesBudget(),
        makeLinesBudget(total: makeLine(spent: 850, status: .nearLimit, percent: 85, remaining: 150)),
        makeLinesBudget(total: makeLine(spent: 1000, status: .reached, percent: 100, remaining: 0)),
        makeLinesBudget(total: makeOverLine()),
        // `BudgetStatus?` 자리라 `.none` 은 nil 로 읽힌다 — 타입을 적는다.
        makeLinesBudget(total: makeLine(spent: 0, status: BudgetStatus.none, percent: 0, remaining: 1000)),
        makeLinesBudget(total: makeLine(budget: 0, spent: 0, status: BudgetStatus.none, percent: nil, remaining: 0)),
        makeLinesBudget(
            total: makeLine(budget: 0, spent: 100, status: .exceeded, percent: nil, remaining: nil, over: 100)
        )
    ]
}

/// `makeLinesBudget()` 에서 줄 하나씩 깨뜨린 응답 — ① 전체 몫 없음 ② 전체 상태 없음 ③ 전체가 넘었는데 넘은 돈 없음
/// ④ 전체가 진행 중인데 남은 돈 없음 ⑤ 몫 있는 카테고리가 넘었는데 넘은 돈 없음 ⑥ 몫 있는 결제수단이 넘었는데 넘은 돈 없음
/// ⑦ 몫 있는 그 외 카테고리가 넘었는데 넘은 돈 없음 ⑧ 몫 있는 카테고리의 상태 없음 ⑨ 몫 있는 결제수단의 상태 없음
/// ⑩ 몫 있는 그 외 카테고리의 상태 없음(인계 2026-09-29 :107·:109 — 상태가 null 인 것은 몫이 null 일 때뿐이다)
/// ⑪ 몫 없는 결제수단이 넘음·넘은 돈을 가짐, 이어서 몫 없는 결제수단이 상태·퍼센트·남은 돈·넘은 돈 중 하나만 가짐
/// (인계 :107 — 몫이 null 이면 넷 다 null, 백엔드 `BudgetLine.actualOnly`).
@MainActor
private func makeMalformedLineBudgets() -> [MonthlyBudget] {
    [
        makeLinesBudget(
            creditCard: makeLine(budget: nil, spent: 1050, status: .exceeded, percent: nil, remaining: nil, over: 50)
        ),
        makeLinesBudget(creditCard: makeLine(budget: nil, status: .inProgress, percent: nil, remaining: nil)),
        makeLinesBudget(creditCard: makeLine(budget: nil, status: nil, percent: 10, remaining: nil)),
        makeLinesBudget(creditCard: makeLine(budget: nil, status: nil, percent: nil, remaining: 900)),
        makeLinesBudget(creditCard: makeLine(budget: nil, status: nil, percent: nil, remaining: nil, over: 50)),
        makeLinesBudget(total: makeLine(budget: nil)),
        makeLinesBudget(total: makeLine(status: nil)),
        makeLinesBudget(total: makeOverLine(over: nil)),
        makeLinesBudget(total: makeLine(remaining: nil)),
        makeLinesBudget(budgetedCategory: makeOverLine(over: nil)),
        makeLinesBudget(creditCard: makeOverLine(over: nil)),
        makeLinesBudget(otherCategories: makeOverLine(over: nil)),
        makeLinesBudget(budgetedCategory: makeLine(status: nil)),
        makeLinesBudget(creditCard: makeLine(status: nil)),
        makeLinesBudget(otherCategories: makeLine(status: nil))
    ]
}

private extension BudgetTabViewModel.Phase {
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    var isNoIdentity: Bool {
        if case .noIdentity = self {
            return true
        }
        return false
    }

    var content: BudgetTabContent? {
        if case let .loaded(content) = self {
            return content
        }
        return nil
    }

    var shownMonth: ServerMonth? {
        content.map { ServerMonth(year: $0.budget.year, month: $0.budget.month) }
    }
}

private extension BudgetTabViewModel.EditContextResult {
    var context: BudgetEditViewModel.Context? {
        if case let .open(context) = self {
            return context
        }
        return nil
    }

    var isUnavailable: Bool {
        if case .unavailable = self {
            return true
        }
        return false
    }

    var isServerMonthFailed: Bool {
        if case .serverMonthFailed = self {
            return true
        }
        return false
    }
}
