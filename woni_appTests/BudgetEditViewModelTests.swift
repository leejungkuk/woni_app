//
//  BudgetEditViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 편집 화면의 상태·판정 — 열기·달 옮기기·통화 바꾸기·지난 달 불러오기·닫기(스펙 :218-236 · :261-281).
/// 서버 읽기는 가짜이고 응답 시점은 테스트가 정한다. 따로 적지 않으면 회원이 탭에서 2026-10 을 열고(전체 500,000 ·
/// 카테고리 1 몫 400,000), 범위 끝은 2027-10 이며, 읽어 오는 달의 전체는 `달 × 10,000`(11월 110,000)이다.
@MainActor
struct BudgetEditViewModelTests {
    // MARK: 열기

    @Test("회원은 탭이 보이던 그 달 응답으로 열고 다시 읽지 않는다 — 응답이 없으면 빈 칸 대신 불러올 수 없음")
    func opensFromTabBudgetWithoutFetching() {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()

        #expect(viewModel.phase == .editing)
        #expect(fakes.fetch.calls.isEmpty)
        #expect(viewModel.month == yearMonth(2026, 10))
        #expect(viewModel.draft.directTotal == 500_000)
        #expect(viewModel.draft.categoryLines.map(\.amount) == [400_000])
        #expect(viewModel.showsDeleteButton)
        #expect(viewModel.showsMonthArrows)
        #expect(viewModel.showsLoadPrevious)
        #expect(!viewModel.hasChanges)

        // 미설정 달 — 삭제할 예산이 없다.
        fakes.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let unset = fakes.makeViewModel()
        #expect(unset.phase == .editing)
        #expect(unset.draft.total == nil)
        #expect(!unset.showsDeleteButton)

        // 빈 칸을 보이면 저장이 그 달 예산을 덮어쓴다.
        fakes.initialBudget = nil
        let missing = fakes.makeViewModel()
        #expect(missing.phase == .loadFailed)
        #expect(!missing.canLoadPrevious)
        #expect(!missing.showsDeleteButton)
    }

    @Test("신원 없는 비회원은 넘겨받은 달로 고정되고 화살표·불러오기·삭제가 없으며 기기 기준통화 빈칸이다")
    func memberlessOpensFixedEmptyMonth() async {
        let fakes = BudgetEditFakes()
        fakes.lastMonth = nil
        fakes.initialBudget = nil
        fakes.baseCurrency = .usd
        let viewModel = fakes.makeViewModel()

        #expect(viewModel.phase == .editing)
        #expect(!viewModel.showsMonthArrows)
        #expect(!viewModel.canGoPrevious)
        #expect(!viewModel.canGoNext)
        #expect(!viewModel.showsLoadPrevious)
        #expect(!viewModel.canLoadPrevious)
        #expect(!viewModel.showsDeleteButton)
        #expect(viewModel.draft.currency == .usd)
        #expect(viewModel.draft.total == nil)
        #expect(viewModel.draft.spentTotal == nil)

        await viewModel.go(by: -1)
        await viewModel.loadPrevious()
        #expect(fakes.fetch.calls.isEmpty)
        #expect(viewModel.month == yearMonth(2026, 10))
    }

    // MARK: 달 이동

    @Test("바뀐 입력이 없으면 바로 옮기고 그 달을 읽어 초안을 연다")
    func movingWithoutChangesReadsNextMonth() async {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()

        await viewModel.go(by: 1)

        #expect(viewModel.dialog == nil)
        #expect(fakes.fetch.calls == [yearMonth(2026, 11)])
        #expect(viewModel.month == yearMonth(2026, 11))
        #expect(viewModel.phase == .editing)
        #expect(viewModel.draft.directTotal == 110_000)
        #expect(viewModel.draft.categoryLines.isEmpty)
        #expect(viewModel.showsDeleteButton)
        #expect(!viewModel.hasChanges)
    }

    @Test("바뀐 입력이 있으면 나갈까요를 묻고, 취소면 그대로·나가기면 옮겨 읽는다")
    func movingWithChangesAsksToLeave() async {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()
        viewModel.setDirectTotal(600_000)
        #expect(viewModel.hasChanges)

        await viewModel.go(by: 1)
        #expect(viewModel.dialog == .leave)
        #expect(fakes.fetch.calls.isEmpty)
        #expect(viewModel.month == yearMonth(2026, 10))

        viewModel.cancelDialog()
        #expect(viewModel.dialog == nil)
        #expect(viewModel.draft.directTotal == 600_000)
        #expect(viewModel.month == yearMonth(2026, 10))
        #expect(fakes.fetch.calls.isEmpty)

        await viewModel.go(by: 1)
        #expect(viewModel.dialog == .leave)
        await viewModel.confirmDialog()
        #expect(viewModel.dialog == nil)
        #expect(fakes.fetch.calls == [yearMonth(2026, 11)])
        #expect(viewModel.month == yearMonth(2026, 11))
        #expect(viewModel.phase == .editing)
        #expect(viewModel.draft.directTotal == 110_000)
    }

    @Test("옮긴 달을 못 읽으면 불러올 수 없음 — 불러오기·삭제를 막고 화살표는 다시 읽는다")
    func failedMonthReadBlocksEditing() async {
        let fakes = BudgetEditFakes()
        fakes.fetch.result = { _ in .failure(BudgetEditTestError.offline) }
        let viewModel = fakes.makeViewModel()

        await viewModel.go(by: 1)

        #expect(viewModel.phase == .loadFailed)
        #expect(viewModel.month == yearMonth(2026, 11))
        #expect(!viewModel.canLoadPrevious)
        #expect(!viewModel.showsDeleteButton)
        #expect(viewModel.canGoPrevious)
        #expect(viewModel.canGoNext)
        #expect(!viewModel.hasChanges)

        await viewModel.loadPrevious()
        #expect(fakes.fetch.calls == [yearMonth(2026, 11)])

        await viewModel.go(by: 1)
        #expect(fakes.fetch.calls == [yearMonth(2026, 11), yearMonth(2026, 12)])
        #expect(viewModel.month == yearMonth(2026, 12))
    }

    @Test("나가기로 옮기기 시작하면 옛 초안을 버린다 — 읽는 동안·읽기 실패 뒤 다시 묻지 않고, 읽으면 새 기준선")
    func leavingThenFailedReadClearsChanges() async {
        let held = BudgetEditFakes()
        let closing = held.makeViewModel()
        closing.setDirectTotal(600_000)
        await closing.go(by: 1)
        held.fetch.holds = true
        let moving = Task { await closing.confirmDialog() }
        await waitUntil { held.fetch.isHeld(0) }
        #expect(closing.phase == .loading)
        #expect(!closing.hasChanges)
        closing.requestClose()
        #expect(closing.dialog == nil)
        #expect(held.dismissedMonths == [yearMonth(2026, 11)])
        held.fetch.release(0)
        await moving.value

        let failing = BudgetEditFakes()
        let failed = failing.makeViewModel()
        failed.setDirectTotal(600_000)
        await failed.go(by: 1)
        failing.fetch.result = { _ in .failure(BudgetEditTestError.offline) }
        await failed.confirmDialog()
        #expect(failed.phase == .loadFailed)
        #expect(!failed.hasChanges)
        await failed.go(by: 1)
        #expect(failed.dialog == nil)
        #expect(failing.fetch.calls == [yearMonth(2026, 11), yearMonth(2026, 12)])

        let succeeding = BudgetEditFakes()
        let moved = succeeding.makeViewModel()
        moved.setDirectTotal(600_000)
        await moved.go(by: 1)
        await moved.confirmDialog()
        #expect(moved.phase == .editing)
        #expect(!moved.hasChanges)
    }

    @Test("계약을 어긴 응답은 읽기 실패와 같다 — 기준통화·빈칸으로 메우지 않는다")
    func malformedResponseIsTreatedAsFailure() async {
        let fakes = BudgetEditFakes()
        fakes.fetch.result = { month in
            let budget = makeBudget(month, total: 110_000)
            return .success(breaking(budget, status: .inProgress, currency: nil, paymentGroups: budget.paymentGroups))
        }
        let viewModel = fakes.makeViewModel()

        await viewModel.go(by: 1)
        #expect(viewModel.phase == .loadFailed)
        #expect(!viewModel.showsDeleteButton)

        let previousFakes = BudgetEditFakes()
        previousFakes.fetch.result = { month in
            let budget = makeBudget(month, total: 90000)
            let twoGroups = Array(budget.paymentGroups.prefix(2))
            let broken = breaking(budget, status: budget.status, currency: budget.currency, paymentGroups: twoGroups)
            return .success(broken)
        }
        let opened = previousFakes.makeViewModel()
        let before = opened.draft

        await opened.loadPrevious()
        #expect(previousFakes.fetch.calls == [yearMonth(2026, 9)])
        #expect(opened.toast == .previousLoadFailed)
        #expect(opened.dialog == nil)
        #expect(opened.draft == before)
        #expect(!opened.isPreviousApplied)
    }

    @Test("가장 나중에 시작한 읽기만 반영한다 — 늦게 온 옛 달 응답이 초안을 덮지 않는다")
    func staleMonthReadIsDiscarded() async {
        let fakes = BudgetEditFakes()
        fakes.fetch.holds = true
        let viewModel = fakes.makeViewModel()

        let toNovember = Task { await viewModel.go(by: 1) }
        await waitUntil { fakes.fetch.isHeld(0) }
        let toDecember = Task { await viewModel.go(by: 1) }
        await waitUntil { fakes.fetch.isHeld(1) }
        #expect(fakes.fetch.calls == [yearMonth(2026, 11), yearMonth(2026, 12)])

        fakes.fetch.release(1)
        await toDecember.value
        #expect(viewModel.draft.directTotal == 120_000)

        fakes.fetch.release(0)
        await toNovember.value
        #expect(viewModel.month == yearMonth(2026, 12))
        #expect(viewModel.phase == .editing)
        #expect(viewModel.draft.directTotal == 120_000)
    }

    @Test("범위 끝(2000-01 · 서버 이번 달 + 12)에서는 화살표가 꺼지고 읽지 않는다")
    func arrowsStopAtRangeEnds() async {
        let last = BudgetEditFakes()
        last.month = yearMonth(2027, 10)
        last.initialBudget = makeBudget(yearMonth(2027, 10), total: 500_000)
        let atLast = last.makeViewModel()
        #expect(!atLast.canGoNext)
        #expect(atLast.canGoPrevious)
        await atLast.go(by: 1)
        #expect(last.fetch.calls.isEmpty)
        #expect(atLast.month == yearMonth(2027, 10))

        let first = BudgetEditFakes()
        first.month = yearMonth(2000, 1)
        first.initialBudget = makeBudget(yearMonth(2000, 1), total: 500_000)
        let atFirst = first.makeViewModel()
        #expect(!atFirst.canGoPrevious)
        #expect(atFirst.canGoNext)
        await atFirst.go(by: -1)
        #expect(first.fetch.calls.isEmpty)
        #expect(atFirst.month == yearMonth(2000, 1))
    }
}

// MARK: 통화

extension BudgetEditViewModelTests {
    @Test("금액이 있으면 통화를 바꿀까요를 묻고, 바꾸면 금액만 비우고 줄은 남기며 바뀐 입력이 아니다")
    func currencyChangeWithAmountsAsksThenClears() async {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()

        viewModel.selectCurrency(.usd)
        #expect(viewModel.dialog == .changeCurrency(.usd))
        viewModel.cancelDialog()
        #expect(viewModel.dialog == nil)
        #expect(viewModel.draft.currency == .krw)
        #expect(viewModel.draft.directTotal == 500_000)

        viewModel.selectCurrency(.usd)
        await viewModel.confirmDialog()
        #expect(viewModel.dialog == nil)
        #expect(viewModel.draft.currency == .usd)
        #expect(viewModel.draft.directTotal == nil)
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [1])
        #expect(viewModel.draft.categoryLines.map(\.amount) == [nil])
        #expect(viewModel.draft.paymentAmounts.isEmpty)
        #expect(!viewModel.hasChanges)

        // 금액 없이 줄만 더한 상태 — 묻지 않고 바꾸고, 바꾼 뒤가 새 기준선이다.
        fakes.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let empty = fakes.makeViewModel()
        empty.addCategory(2)
        #expect(empty.hasChanges)
        empty.selectCurrency(.eur)
        #expect(empty.dialog == nil)
        #expect(empty.draft.currency == .eur)
        #expect(empty.draft.categoryLines.map(\.categoryID) == [2])
        #expect(!empty.hasChanges)
    }

    @Test("지금 통화와 같은 통화를 고르면 아무것도 하지 않는다")
    func sameCurrencyIsNoOp() {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()
        let before = viewModel.draft

        viewModel.selectCurrency(.krw)

        #expect(viewModel.dialog == nil)
        #expect(viewModel.draft == before)
    }
}

// MARK: 지난 달 불러오기

extension BudgetEditViewModelTests {
    @Test("직전 달을 그때 읽는다 — 미설정이면 없음 토스트, 실패면 실패 토스트이고 칸은 그대로")
    func loadPreviousNotSetOrFailedShowsToast() async {
        let fakes = BudgetEditFakes()
        fakes.fetch.result = { .success(makeNotSetBudget($0)) }
        let viewModel = fakes.makeViewModel()
        let before = viewModel.draft

        await viewModel.loadPrevious()
        #expect(fakes.fetch.calls == [yearMonth(2026, 9)])
        #expect(viewModel.toast == .noPreviousBudget)
        #expect(viewModel.dialog == nil)
        #expect(viewModel.draft == before)
        #expect(!viewModel.isPreviousApplied)

        viewModel.toast = nil
        fakes.fetch.result = { _ in .failure(BudgetEditTestError.offline) }
        await viewModel.loadPrevious()
        #expect(fakes.fetch.calls == [yearMonth(2026, 9), yearMonth(2026, 9)])
        #expect(viewModel.toast == .previousLoadFailed)
        #expect(viewModel.draft == before)
        #expect(!viewModel.isPreviousApplied)
    }

    @Test("칸에 금액이 있으면 바꿀까요를 묻고 덮는다 — 칩이 켜지고 고치면 꺼지며, 통화만 달라도 바뀐 입력이다")
    func loadPreviousWithAmountsAsksBeforeReplacing() async {
        let fakes = BudgetEditFakes()
        fakes.fetch.result = { .success(makeBudget($0, total: 90000, categories: [categoryLine(2, 60000)])) }
        let viewModel = fakes.makeViewModel()
        let before = viewModel.draft

        await viewModel.loadPrevious()
        #expect(viewModel.dialog == .replaceWithPrevious)
        #expect(viewModel.draft == before)
        #expect(!viewModel.isPreviousApplied)

        await viewModel.confirmDialog()
        #expect(viewModel.dialog == nil)
        #expect(viewModel.draft.directTotal == 90000)
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [2])
        #expect(viewModel.draft.categoryLines.map(\.amount) == [60000])
        #expect(viewModel.isPreviousApplied)
        #expect(viewModel.hasChanges)
        #expect(viewModel.toast == nil)

        viewModel.setCategoryAmount(70000, for: 2)
        #expect(!viewModel.isPreviousApplied)
        #expect(viewModel.hasChanges)

        // 지난 달 금액·줄이 지금과 같고 통화만 다르다 — 불러온 값이므로 확인 없이 닫히지 않는다.
        let sameAmounts = BudgetEditFakes()
        sameAmounts.fetch.result = {
            .success(makeBudget($0, currency: .usd, total: 500_000, categories: [categoryLine(1, 400_000)]))
        }
        let same = sameAmounts.makeViewModel()
        await same.loadPrevious()
        await same.confirmDialog()
        #expect(same.draft.currency == .usd)
        #expect(same.hasChanges)
        same.requestClose()
        #expect(same.dialog == .leave)
        #expect(sameAmounts.outcomes.isEmpty)

        // 빈 칸이면 묻지 않고 바로 채운다.
        fakes.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let empty = fakes.makeViewModel()
        await empty.loadPrevious()
        #expect(empty.dialog == nil)
        #expect(empty.draft.directTotal == 90000)
        #expect(empty.isPreviousApplied)
    }

    @Test("삭제된 카테고리를 빼고 불러오면 뺀 수를 토스트로 알린다")
    func loadPreviousReportsDroppedDeleted() async {
        let fakes = BudgetEditFakes()
        fakes.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        fakes.fetch.result = {
            .success(makeBudget($0, total: 500_000, categories: [
                categoryLine(1, 300_000),
                categoryLine(9, 100_000, isDeleted: true)
            ]))
        }
        let viewModel = fakes.makeViewModel()

        await viewModel.loadPrevious()

        #expect(viewModel.toast == .droppedDeletedCategories(1))
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [1])
        #expect(viewModel.draft.directTotal == 500_000)
        #expect(viewModel.isPreviousApplied)
    }

    @Test("2000-01 에서는 불러오기를 누를 수 없고 읽지 않는다")
    func loadPreviousUnavailableAtFirstMonth() async {
        let fakes = BudgetEditFakes()
        fakes.month = yearMonth(2000, 1)
        fakes.initialBudget = makeBudget(yearMonth(2000, 1), total: 500_000)
        let viewModel = fakes.makeViewModel()

        #expect(viewModel.showsLoadPrevious)
        #expect(!viewModel.canLoadPrevious)
        await viewModel.loadPrevious()
        #expect(fakes.fetch.calls.isEmpty)
        #expect(viewModel.toast == nil)
    }
}

// MARK: 지난 달 불러오기 — 늦은 응답·칩

extension BudgetEditViewModelTests {
    @Test("확인 창이 떠 있는 사이 온 지난 달 응답은 버린다 — 창·초안·토스트 그대로, 창이 없으면 바꿀까요를 띄운다")
    func latePreviousKeepsOpenDialog() async {
        // 나갈까요 — 응답 뒤에도 같은 자리 버튼이 닫는다.
        let leaving = BudgetEditFakes()
        let closing = leaving.makeViewModel()
        closing.setDirectTotal(600_000)
        let edited = closing.draft
        await leaving.loadPrevious(on: closing) {
            closing.requestClose()
            #expect(closing.dialog == .leave)
        }
        #expect(closing.dialog == .leave)
        #expect(closing.draft == edited)
        #expect(!closing.isPreviousApplied)
        #expect(closing.toast == nil)
        await closing.confirmDialog()
        #expect(leaving.dismissedMonths == [yearMonth(2026, 10)])

        // 통화를 바꿀까요 — 응답 뒤에도 바꾸기는 통화를 바꾼다.
        let switching = BudgetEditFakes()
        let changing = switching.makeViewModel()
        let opened = changing.draft
        await switching.loadPrevious(on: changing) {
            changing.selectCurrency(.usd)
        }
        #expect(changing.dialog == .changeCurrency(.usd))
        #expect(changing.draft == opened)
        await changing.confirmDialog()
        #expect(changing.draft.currency == .usd)
        #expect(changing.draft.directTotal == nil)
        #expect(!changing.isPreviousApplied)

        // 실패 응답도 버린다 — 창 위에 토스트를 띄우지 않는다.
        let failing = BudgetEditFakes()
        let failed = failing.makeViewModel()
        await failing.loadPrevious(on: failed) {
            failed.selectCurrency(.usd)
            failing.fetch.result = { _ in .failure(BudgetEditTestError.offline) }
        }
        #expect(failed.dialog == .changeCurrency(.usd))
        #expect(failed.toast == nil)

        // 짝: 창이 없으면 같은 응답이 바꿀까요를 띄운다.
        let idleFakes = BudgetEditFakes()
        let idle = idleFakes.makeViewModel()
        await idleFakes.loadPrevious(on: idle) {}
        #expect(idle.dialog == .replaceWithPrevious)
    }

    @Test("불러오기 읽기 중 달을 옮기면 늦게 온 지난 달 응답을 버린다 — 옮긴 달 초안 그대로")
    func previousReadIgnoredAfterMonthMove() async {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()

        await fakes.loadPrevious(on: viewModel) {
            fakes.fetch.holds = false
            await viewModel.go(by: 1)
            #expect(viewModel.phase == .editing)
            #expect(viewModel.draft.directTotal == 110_000)
        }

        #expect(fakes.fetch.calls == [yearMonth(2026, 9), yearMonth(2026, 11)])
        #expect(viewModel.month == yearMonth(2026, 11))
        #expect(viewModel.draft.directTotal == 110_000)
        #expect(!viewModel.isPreviousApplied)
        #expect(viewModel.dialog == nil)
        #expect(viewModel.toast == nil)
    }

    @Test("불러온 뒤 칸을 하나라도 고치면 칩이 꺼진다 — 결제수단 섹션을 펼치기만 하면 켜진 채")
    func previousChipTurnsOffOnEveryEdit() async {
        let edits: [(String, @MainActor (BudgetEditViewModel) async -> Void)] = [
            ("전체", { $0.setDirectTotal(100_000) }),
            ("결제수단", { $0.setPaymentAmount(10000, for: .creditCard) }),
            ("카테고리 추가", { $0.addCategory(3) }),
            ("통화", { viewModel in
                viewModel.selectCurrency(.usd)
                await viewModel.confirmDialog()
            })
        ]
        for (name, edit) in edits {
            let viewModel = await makePreviousApplied()
            await edit(viewModel)
            #expect(!viewModel.isPreviousApplied, "\(name)")
        }

        // 펼치기만은 칸을 고친 것이 아니다(임시 결정 #29).
        let expanded = await makePreviousApplied()
        expanded.togglePaymentSection()
        #expect(expanded.draft.isPaymentExpanded)
        #expect(expanded.isPreviousApplied)
    }

    /// 빈 달에서 지난 달(전체 90,000 · 카테고리 2 몫 60,000)을 불러와 칩이 켜진 편집 화면.
    private func makePreviousApplied() async -> BudgetEditViewModel {
        let fakes = BudgetEditFakes()
        fakes.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        fakes.fetch.result = { .success(makeBudget($0, total: 90000, categories: [categoryLine(2, 60000)])) }
        let viewModel = fakes.makeViewModel()
        await viewModel.loadPrevious()
        #expect(viewModel.isPreviousApplied)
        return viewModel
    }
}

// MARK: 응답의 달 · 통화를 바꾼 뒤 온 응답

extension BudgetEditViewModelTests {
    @Test("응답의 달이 요청한 달과 다르면 읽기 실패와 같다 — 다른 달 금액을 이 달 칸에 열지 않는다")
    func mismatchedMonthResponseFailsRead() async {
        // 탭이 넘긴 응답이 9월 — 10월 칸에 열면 저장이 10월 예산을 덮어쓴다.
        let opening = BudgetEditFakes()
        opening.initialBudget = makeBudget(yearMonth(2026, 9), total: 90000)
        let wrongOpen = opening.makeViewModel()
        #expect(wrongOpen.phase == .loadFailed)
        #expect(wrongOpen.draft.total == nil)
        #expect(!wrongOpen.canLoadPrevious)
        #expect(!wrongOpen.showsDeleteButton)
        #expect(!wrongOpen.hasChanges)
        opening.initialBudget = makeBudget(yearMonth(2026, 10), total: 90000)
        let rightOpen = opening.makeViewModel()
        #expect(rightOpen.phase == .editing)
        #expect(rightOpen.draft.directTotal == 90000)

        // 11월을 읽었는데 10월 응답 — 다시 옮겨 맞는 응답이 오면 연다.
        let moving = BudgetEditFakes()
        moving.fetch.result = { _ in .success(makeBudget(yearMonth(2026, 10), total: 100_000)) }
        let moved = moving.makeViewModel()
        await moved.go(by: 1)
        #expect(moving.fetch.calls == [yearMonth(2026, 11)])
        #expect(moved.month == yearMonth(2026, 11))
        #expect(moved.phase == .loadFailed)
        #expect(moved.draft.total == nil)
        #expect(!moved.showsDeleteButton)
        moving.fetch.result = { .success(makeBudget($0, total: 120_000)) }
        await moved.go(by: 1)
        #expect(moved.month == yearMonth(2026, 12))
        #expect(moved.phase == .editing)
        #expect(moved.draft.directTotal == 120_000)

        // 지난 달(9월)을 읽었는데 8월 응답 — 칸 그대로, 맞는 응답이면 채운다.
        let previous = BudgetEditFakes()
        previous.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        previous.fetch.result = { _ in .success(makeBudget(yearMonth(2026, 8), total: 80000)) }
        let loading = previous.makeViewModel()
        let before = loading.draft
        await loading.loadPrevious()
        #expect(previous.fetch.calls == [yearMonth(2026, 9)])
        #expect(loading.toast == .previousLoadFailed)
        #expect(loading.dialog == nil)
        #expect(loading.draft == before)
        #expect(!loading.isPreviousApplied)
        loading.toast = nil
        previous.fetch.result = { .success(makeBudget($0, total: 90000)) }
        await loading.loadPrevious()
        #expect(loading.toast == nil)
        #expect(loading.draft.directTotal == 90000)
        #expect(loading.isPreviousApplied)
    }

    @Test("지난 달을 읽는 사이 통화를 바꿨으면 늦게 온 응답을 버린다 — 방금 고른 통화를 지난 달 통화로 되돌리지 않는다")
    func latePreviousAfterCurrencyChangeIsDropped() async {
        let withAmounts = makeBudget(yearMonth(2026, 10), total: 500_000, categories: [categoryLine(1, 400_000)])
        let cases: [(name: String, initial: MonthlyBudget)] = [
            ("금액이 있어 확인 창을 거쳐 바꿈", withAmounts),
            ("금액이 없어 바로 바꿈", makeNotSetBudget(yearMonth(2026, 10)))
        ]
        for (name, initial) in cases {
            let fakes = BudgetEditFakes()
            fakes.initialBudget = initial
            let viewModel = fakes.makeViewModel()
            await fakes.loadPrevious(on: viewModel) {
                viewModel.selectCurrency(.usd)
                let asks = initial.hasAnyBudget
                #expect(viewModel.dialog == (asks ? .changeCurrency(.usd) : nil), "\(name)")
                await viewModel.confirmDialog()
            }
            #expect(viewModel.draft.currency == .usd, "\(name)")
            #expect(viewModel.draft.directTotal == nil, "\(name)")
            #expect(viewModel.draft.categoryLines.allSatisfy { $0.amount == nil }, "\(name)")
            #expect(viewModel.draft.paymentAmounts.isEmpty, "\(name)")
            #expect(!viewModel.isPreviousApplied, "\(name)")
            #expect(viewModel.dialog == nil, "\(name)")
            #expect(viewModel.toast == nil, "\(name)")
        }

        // 짝: 통화를 안 바꾸면 같은 응답이 채운다.
        let kept = BudgetEditFakes()
        kept.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let filled = kept.makeViewModel()
        await kept.loadPrevious(on: filled) {}
        #expect(filled.draft.currency == .krw)
        #expect(filled.draft.directTotal == 90000)
        #expect(filled.isPreviousApplied)
    }

    @Test("불러오기 읽기가 실패해도 그 사이 달을 옮겼으면 실패 토스트를 띄우지 않는다")
    func latePreviousFailureIgnoredAfterMonthMove() async {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()

        await fakes.loadPrevious(on: viewModel) {
            fakes.fetch.holds = false
            await viewModel.go(by: 1)
            #expect(viewModel.phase == .editing)
            fakes.fetch.result = { _ in .failure(BudgetEditTestError.offline) }
        }

        #expect(fakes.fetch.calls == [yearMonth(2026, 9), yearMonth(2026, 11)])
        #expect(viewModel.toast == nil)
        #expect(viewModel.month == yearMonth(2026, 11))
        #expect(viewModel.phase == .editing)
        #expect(viewModel.draft.directTotal == 110_000)
    }
}

// MARK: 입력·닫기

extension BudgetEditViewModelTests {
    @Test("전체를 카테고리 합보다 작게 치고 벗어나면 합계로 맞추고 토스트 — 치지 않고 벗어나면 그대로")
    func endingTotalBelowSumShowsToast() {
        let fakes = BudgetEditFakes()
        fakes.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let below = fakes.makeViewModel()
        below.addCategory(1)
        below.setCategoryAmount(400_000, for: 1)
        below.beginTotalEditing()
        below.setDirectTotal(300_000)
        below.endTotalEditing()
        #expect(below.toast == .totalBelowCategorySum)
        #expect(below.draft.directTotal == 400_000)

        let above = fakes.makeViewModel()
        above.addCategory(1)
        above.setCategoryAmount(400_000, for: 1)
        above.beginTotalEditing()
        above.setDirectTotal(500_000)
        above.endTotalEditing()
        #expect(above.toast == nil)
        #expect(above.draft.directTotal == 500_000)

        // T 500,000 · S 400,000 에서 카테고리를 올려 S 600,000 — 전체 칸을 열었다 닫기만 했다.
        fakes.initialBudget = makeBudget(yearMonth(2026, 10), total: 500_000, categories: [categoryLine(1, 400_000)])
        let untouched = fakes.makeViewModel()
        untouched.setCategoryAmount(600_000, for: 1)
        untouched.beginTotalEditing()
        untouched.endTotalEditing()
        #expect(untouched.toast == nil)
        #expect(untouched.draft.directTotal == 500_000)
    }

    @Test("카테고리 합이 상한을 넘는 입력은 거절하고 상한 토스트 — 상한까지는 받는다")
    func categoryLimitRejectionReturnsFalse() {
        let fakes = BudgetEditFakes()
        fakes.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let viewModel = fakes.makeViewModel()
        viewModel.addCategory(1)
        viewModel.addCategory(2)
        #expect(viewModel.setCategoryAmount(99_998_999, for: 1))
        let before = viewModel.draft

        #expect(!viewModel.setCategoryAmount(1001, for: 2))
        #expect(viewModel.toast == .amountOverLimit)
        #expect(viewModel.draft == before)

        viewModel.toast = nil
        #expect(viewModel.setCategoryAmount(1000, for: 2))
        #expect(viewModel.toast == nil)
        #expect(viewModel.draft.categorySum == 99_999_999)
    }

    @Test("바뀐 입력이 없으면 바로 닫고 보던 달을 넘긴다 — 있으면 나갈까요를 묻고, 비회원은 달을 넘기지 않는다")
    func closeAsksOnlyWithChanges() async {
        let clean = BudgetEditFakes()
        let unchanged = clean.makeViewModel()
        unchanged.requestClose()
        #expect(unchanged.dialog == nil)
        #expect(clean.dismissedMonths == [yearMonth(2026, 10)])

        let edited = BudgetEditFakes()
        let changed = edited.makeViewModel()
        changed.setDirectTotal(600_000)
        changed.requestClose()
        #expect(changed.dialog == .leave)
        #expect(edited.outcomes.isEmpty)
        changed.cancelDialog()
        #expect(edited.outcomes.isEmpty)
        changed.requestClose()
        await changed.confirmDialog()
        #expect(changed.dialog == nil)
        #expect(edited.dismissedMonths == [yearMonth(2026, 10)])

        let memberless = BudgetEditFakes()
        memberless.lastMonth = nil
        memberless.initialBudget = nil
        let fixed = memberless.makeViewModel()
        fixed.requestClose()
        #expect(memberless.dismissedMonths == [nil])
    }
}

// MARK: 가짜 입력

private enum BudgetEditTestError: Error {
    case offline
}

/// 예산 읽기 가짜. 읽은 달을 기록한다. `holds` 를 켜면 응답을 붙잡아 두고, 테스트가 `release` 로 시점을 정한다.
@MainActor
private final class FakeBudgetFetch {
    var result: (ServerMonth) -> Result<MonthlyBudget, any Error>
    var holds = false
    private(set) var calls: [ServerMonth] = []
    private var held: [Int: CheckedContinuation<MonthlyBudget, any Error>] = [:]

    init(_ result: @escaping (ServerMonth) -> Result<MonthlyBudget, any Error>) {
        self.result = result
    }

    func call(_ month: ServerMonth) async throws -> MonthlyBudget {
        calls.append(month)
        guard holds else {
            return try result(month).get()
        }
        let index = calls.count - 1
        return try await withCheckedThrowingContinuation { held[index] = $0 }
    }

    func isHeld(_ index: Int) -> Bool {
        held[index] != nil
    }

    /// 붙잡은 `index` 번째 읽기에 지금의 `result` 로 답한다.
    func release(_ index: Int) {
        held.removeValue(forKey: index)?.resume(with: result(calls[index]))
    }
}

@MainActor
private final class BudgetEditFakes {
    let fetch = FakeBudgetFetch { .success(makeBudget($0, total: Decimal($0.month) * 10000)) }
    var month: ServerMonth
    /// nil = 신원 없는 비회원.
    var lastMonth: ServerMonth?
    var initialBudget: MonthlyBudget?
    var baseCurrency: CurrencyCode
    var chipOrder = [1, 2, 3]
    private(set) var outcomes: [BudgetEditOutcome] = []

    init() {
        month = yearMonth(2026, 10)
        lastMonth = yearMonth(2027, 10)
        initialBudget = makeBudget(yearMonth(2026, 10), total: 500_000, categories: [categoryLine(1, 400_000)])
        baseCurrency = .krw
    }

    /// 닫힘으로 넘긴 달. 닫힘이 아닌 끝 결과는 세지 않는다.
    var dismissedMonths: [ServerMonth?] {
        outcomes.compactMap { outcome -> ServerMonth?? in
            if case let .dismissed(month) = outcome {
                return .some(month)
            }
            return nil
        }
    }

    func makeViewModel() -> BudgetEditViewModel {
        BudgetEditViewModel(
            context: BudgetEditViewModel.Context(month: month, lastMonth: lastMonth, initialBudget: initialBudget),
            chipOrder: { self.chipOrder },
            baseCurrency: baseCurrency,
            fetch: { year, month in try await self.fetch.call(yearMonth(year, month)) },
            onFinish: { self.outcomes.append($0) }
        )
    }

    /// 지난 달 읽기를 붙잡아 둔 채 `meanwhile` 을 하고, 그 뒤에 지금의 `fetch.result` 로 답한다.
    func loadPrevious(on viewModel: BudgetEditViewModel, meanwhile: @MainActor () async -> Void) async {
        let index = fetch.calls.count
        fetch.holds = true
        let loading = Task { await viewModel.loadPrevious() }
        await waitUntil { self.fetch.isHeld(index) }
        await meanwhile()
        fetch.release(index)
        await loading.value
    }
}

// MARK: 응답 픽스처

@MainActor
private func yearMonth(_ year: Int, _ month: Int) -> ServerMonth {
    ServerMonth(year: year, month: month)
}

/// 쓴 돈 0 인 몫 있는 줄. 계약상 상태 NONE · 퍼센트 0(0원 예산이면 nil) · 남은 돈 = 몫이다.
private func under(_ budget: Decimal) -> BudgetLine {
    BudgetLine(
        budgetAmount: budget,
        actualAmount: 0,
        status: BudgetStatus.none,
        percent: budget == 0 ? nil : 0,
        remainingAmount: budget,
        overAmount: nil
    )
}

/// 몫이 없는 줄 — 사용액만 있다.
private func spentOnly(_ spent: Decimal) -> BudgetLine {
    BudgetLine(budgetAmount: nil, actualAmount: spent, status: nil, percent: nil, remainingAmount: nil, overAmount: nil)
}

private func categoryLine(_ id: Int, _ amount: Decimal, isDeleted: Bool = false) -> BudgetCategoryLine {
    BudgetCategoryLine(
        category: Category(id: id, code: "FOOD", displayNameKo: "식비", displayNameEn: "Food", icon: "🍽️", sortOrder: id),
        isDeleted: isDeleted,
        line: under(amount)
    )
}

/// 예산이 있는 달. 응답의 이번 달은 2026-10 이고 남은 일수는 요청한 달이 이번 달일 때만 7 이다. 쓴 돈은 모두 0,
/// 결제수단 세 묶음은 몫이 없다. 그 외 카테고리 몫 = 전체 − 카테고리 몫 합(삭제된 몫 포함), 0 이면 쓴 돈만 — 서버 규칙 그대로.
@MainActor
private func makeBudget(
    _ month: ServerMonth,
    currency: CurrencyCode = .krw,
    total: Decimal,
    categories: [BudgetCategoryLine] = []
) -> MonthlyBudget {
    let otherShare = total - categories.compactMap(\.line.budgetAmount).reduce(0, +)
    let groups: [PaymentGroup] = [.creditCard, .cashAndDebit, .accountAndOther]
    let budget = MonthlyBudget(
        year: month.year,
        month: month.month,
        currentYear: 2026,
        currentMonth: 10,
        remainingDaysIncludingToday: month == yearMonth(2026, 10) ? 7 : nil,
        hasAnyBudget: true,
        status: BudgetStatus.none,
        currency: currency,
        total: under(total),
        paymentGroups: groups.map { BudgetPaymentGroupLine(paymentGroup: $0, line: spentOnly(0)) },
        categories: categories,
        otherCategories: otherShare > 0 ? under(otherShare) : spentOnly(0),
        missingRateCount: 0,
        dailyAllowance: nil
    )
    #expect(BudgetTabViewModel.isWellFormed(budget))
    return budget
}

/// 미설정 달 — 계약상 통화·전체·그 외 카테고리·하루 권장이 nil 이고 결제수단·카테고리는 [] 이다.
@MainActor
private func makeNotSetBudget(_ month: ServerMonth) -> MonthlyBudget {
    let budget = MonthlyBudget(
        year: month.year,
        month: month.month,
        currentYear: 2026,
        currentMonth: 10,
        remainingDaysIncludingToday: month == yearMonth(2026, 10) ? 7 : nil,
        hasAnyBudget: false,
        status: .notSet,
        currency: nil,
        total: nil,
        paymentGroups: [],
        categories: [],
        otherCategories: nil,
        missingRateCount: 0,
        dailyAllowance: nil
    )
    #expect(BudgetTabViewModel.isWellFormed(budget))
    return budget
}

/// 계약을 어긴 응답 — 잘 만든 응답에서 상태·통화·결제수단만 바꾼다. 계약 검사에 걸리는 모양인지 먼저 확인한다.
@MainActor
private func breaking(
    _ budget: MonthlyBudget,
    status: BudgetStatus,
    currency: CurrencyCode?,
    paymentGroups: [BudgetPaymentGroupLine]
) -> MonthlyBudget {
    let broken = MonthlyBudget(
        year: budget.year,
        month: budget.month,
        currentYear: budget.currentYear,
        currentMonth: budget.currentMonth,
        remainingDaysIncludingToday: budget.remainingDaysIncludingToday,
        hasAnyBudget: budget.hasAnyBudget,
        status: status,
        currency: currency,
        total: budget.total,
        paymentGroups: paymentGroups,
        categories: budget.categories,
        otherCategories: budget.otherCategories,
        missingRateCount: budget.missingRateCount,
        dailyAllowance: budget.dailyAllowance
    )
    #expect(!BudgetTabViewModel.isWellFormed(broken))
    return broken
}
