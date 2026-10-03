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
            makeBudget(october, status: .exceeded, total: makeLine(status: .exceeded, percent: nil))
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

private func makeLine(spent: Decimal = 100, status: BudgetStatus? = .inProgress, percent: Int? = 10) -> BudgetLine {
    BudgetLine(
        budgetAmount: 1000,
        actualAmount: spent,
        status: status,
        percent: percent,
        remainingAmount: 900,
        overAmount: nil
    )
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
        categories: [],
        otherCategories: otherCategories,
        missingRateCount: 0,
        dailyAllowance: dailyAllowance
    )
}

/// 미설정 달 — 계약상 통화·전체 줄·그 외 카테고리 줄이 null 이고 결제수단은 [] 이다.
@MainActor
private func makeNotSetBudget(_ month: ServerMonth) -> MonthlyBudget {
    makeBudget(month, status: .notSet, currency: nil, total: nil, paymentGroups: [], otherCategories: nil)
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
