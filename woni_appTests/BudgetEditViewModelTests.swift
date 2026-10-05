//
//  BudgetEditViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 편집 화면의 상태·판정 — 열기·달 옮기기·통화 바꾸기·지난 달 불러오기·닫기·저장·삭제(스펙 :213-245 · :261-281).
/// 서버 읽기·쓰기는 가짜이고 응답 시점은 테스트가 정한다. 따로 적지 않으면 회원이 탭에서 2026-10 을 열고(전체 500,000 ·
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
    @Test("전체를 카테고리 합보다 작게 치고 벗어나도 맞추지 않고 토스트도 없다 — 저장 캡슐만 꺼진다")
    func endingTotalBelowSumKeepsTyped() {
        let fakes = BudgetEditFakes()
        let below = fakes.makeViewModel()
        below.setDirectTotal(300_000)
        below.endTotalEditing()
        #expect(below.toast == nil)
        #expect(below.draft.directTotal == 300_000)
        #expect(!below.canSave)

        let above = fakes.makeViewModel()
        above.setDirectTotal(450_000)
        above.endTotalEditing()
        #expect(above.toast == nil)
        #expect(above.draft.directTotal == 450_000)
        #expect(above.canSave)

        // 카테고리를 먼저 적은 달(합 600,000) — 전체 칸을 열었다 닫기만 했다.
        fakes.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let untouched = fakes.makeViewModel()
        untouched.addCategory(1)
        untouched.setCategoryAmount(600_000, for: 1)
        untouched.endTotalEditing()
        #expect(untouched.toast == nil)
        #expect(untouched.draft.directTotal == nil)
        #expect(untouched.draft.total == 600_000)
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

// MARK: 저장

extension BudgetEditViewModelTests {
    @Test("회원은 발급 없이 올리기 → 쓰기 표 → 저장 순으로 보내고 응답과 표를 넘긴다 — 저장할 수 없는 초안은 보내지 않는다")
    func savingSendsRequestAndFinishes() async {
        let fakes = BudgetEditFakes()
        fakes.writes.token = 41
        fakes.writes.saveResult = { .success(makeBudget($0, total: 777_000)) }
        let viewModel = fakes.makeViewModel()
        #expect(viewModel.canSave)

        await viewModel.save()

        #expect(fakes.writes.events == [.flushPending, .beginWrite, .save(yearMonth(2026, 10)), .finish])
        let request = fakes.writes.saveRequests.first
        #expect(request?.currency == .krw)
        #expect(request?.totalAmount == 500_000)
        #expect(request?.categoryAmounts.map(\.categoryId) == [1])
        #expect(request?.categoryAmounts.map(\.amount) == [400_000])
        #expect(fakes.finished == [.saved(yearMonth(2026, 10), total: 777_000, writeToken: 41)])
        #expect(viewModel.toast == nil)
        #expect(!viewModel.isWriting)

        // 불러올 수 없음 · 전체 없음 · 결제수단 합이 전체 초과 — 저장 캡슐이 꺼져 있고 아무것도 부르지 않는다.
        let blocked = BudgetEditFakes()
        blocked.initialBudget = nil
        let failedOpen = blocked.makeViewModel()
        blocked.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let empty = blocked.makeViewModel()
        let over = blocked.makeViewModel()
        over.setDirectTotal(100_000)
        over.setPaymentAmount(200_000, for: .creditCard)
        for unsaveable in [failedOpen, empty, over] {
            #expect(!unsaveable.canSave)
            await unsaveable.save()
        }
        #expect(blocked.writes.events.isEmpty)
    }

    @Test("저장이 실패하면 입력을 남기고 저장 실패 토스트 — 닫지 않고 다시 누를 수 있다")
    func saveFailureKeepsInput() async {
        let failures: [any Error] = [BudgetWriteError.other(BudgetEditTestError.offline), BudgetEditTestError.offline]
        for failure in failures {
            let fakes = BudgetEditFakes()
            fakes.writes.saveResult = { _ in .failure(failure) }
            let viewModel = fakes.makeViewModel()
            viewModel.setDirectTotal(600_000)
            let edited = viewModel.draft

            await viewModel.save()

            #expect(fakes.writes.events == [.flushPending, .beginWrite, .save(yearMonth(2026, 10))], "\(failure)")
            #expect(viewModel.toast == .saveFailed, "\(failure)")
            #expect(fakes.outcomes.isEmpty, "\(failure)")
            #expect(viewModel.draft == edited, "\(failure)")
            #expect(viewModel.hasChanges, "\(failure)")
            #expect(!viewModel.isWriting, "\(failure)")
            #expect(viewModel.canSave, "\(failure)")
        }
    }

    @Test("서버 거절 코드는 토스트로 바꾸고 입력을 남긴다")
    func saveErrorCodesMapToToasts() async {
        let cases: [(error: BudgetWriteError, toast: BudgetEditToast)] = [
            (.invalidAmount, .amountOverLimit),
            (.totalRequired, .totalRequired),
            (.allocationExceedsTotal, .allocationExceedsTotal)
        ]
        for (error, toast) in cases {
            let fakes = BudgetEditFakes()
            fakes.writes.saveResult = { _ in .failure(error) }
            let viewModel = fakes.makeViewModel()
            let before = viewModel.draft

            await viewModel.save()

            #expect(viewModel.toast == toast, "\(error)")
            #expect(fakes.outcomes.isEmpty, "\(error)")
            #expect(viewModel.draft == before, "\(error)")
            #expect(!fakes.writes.events.contains(.refreshCategories), "\(error)")
            #expect(!viewModel.isWriting, "\(error)")
        }
    }

    @Test("삭제된 카테고리 거절은 목록을 새로 받은 뒤 닫고 그 달을 다시 읽게 한다 — 범위 밖 달은 새로 받지 않고 닫는다")
    func categoryNotFoundRefreshesAndReloads() async {
        let fakes = BudgetEditFakes()
        fakes.writes.saveResult = { _ in .failure(BudgetWriteError.categoryNotFound) }
        let viewModel = fakes.makeViewModel()

        await viewModel.save()

        #expect(fakes.writes.events == [
            .flushPending, .beginWrite, .save(yearMonth(2026, 10)), .refreshCategories, .finish
        ])
        #expect(fakes.finished == [.reloadRequired(yearMonth(2026, 10), .categoryDeletedReloaded)])
        #expect(viewModel.toast == nil)
        #expect(!viewModel.isWriting)

        // 짝: 범위 밖 달 — 옮겨 간 그 달(11월)을 다시 읽게 한다.
        let outOfRange = BudgetEditFakes()
        outOfRange.writes.saveResult = { _ in .failure(BudgetWriteError.monthOutOfRange) }
        let moved = outOfRange.makeViewModel()
        await moved.go(by: 1)

        await moved.save()

        #expect(outOfRange.writes.events == [.flushPending, .beginWrite, .save(yearMonth(2026, 11)), .finish])
        #expect(outOfRange.finished == [.reloadRequired(yearMonth(2026, 11), .monthNotAllowed)])
        #expect(moved.toast == nil)
    }

    @Test("신원 없는 비회원은 발급 → 올리기 → 쓰기 표 → 저장 순이고, 발급 뒤에도 신원이 없으면 보내지 않는다")
    func memberlessSaveIssuesIdentityFirst() async {
        let fakes = BudgetEditFakes()
        fakes.lastMonth = nil
        fakes.initialBudget = nil
        fakes.writes.hasIdentity = false
        let viewModel = fakes.makeViewModel()
        viewModel.setDirectTotal(100_000)

        await viewModel.save()

        #expect(fakes.writes.events == [
            .ensureIdentity, .flushPending, .beginWrite, .save(yearMonth(2026, 10)), .finish
        ])
        #expect(fakes.writes.saveRequests.first?.totalAmount == 100_000)
        #expect(fakes.finished == [.saved(yearMonth(2026, 10), total: 500_000, writeToken: 7)])

        // 짝: 발급 함수는 던지지 않는다 — 부른 뒤에도 신원이 없으면 올리지도 저장하지도 않는다.
        let failing = BudgetEditFakes()
        failing.lastMonth = nil
        failing.initialBudget = nil
        failing.writes.hasIdentity = false
        failing.writes.issuesIdentity = false
        let unsaved = failing.makeViewModel()
        unsaved.setDirectTotal(100_000)
        let edited = unsaved.draft

        await unsaved.save()

        #expect(failing.writes.events == [.ensureIdentity])
        #expect(unsaved.toast == .saveFailed)
        #expect(failing.outcomes.isEmpty)
        #expect(unsaved.draft == edited)
        #expect(!unsaved.isWriting)
    }
}

// MARK: 저장 — 새 카테고리·전체 맞추기

extension BudgetEditViewModelTests {
    @Test("올린 뒤에도 금액 있는 줄에 임시 번호가 남으면 보내지 않는다 — 서버 번호를 받으면 그 번호로 보낸다")
    func unuploadedCategoryBlocksSave() async {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModelWithNewCategory()
        let before = viewModel.draft

        await viewModel.save()

        #expect(fakes.writes.events == [.flushPending])
        #expect(viewModel.toast == .categoryUploadFailed)
        #expect(viewModel.draft == before)
        #expect(fakes.outcomes.isEmpty)
        #expect(!viewModel.isWriting)

        // 짝: 올리기가 서버 번호 42 를 받았다.
        let uploading = BudgetEditFakes()
        uploading.writes.uploads = [-3: 42]
        let uploaded = uploading.makeViewModelWithNewCategory()

        await uploaded.save()

        #expect(uploading.writes.events == [.flushPending, .beginWrite, .save(yearMonth(2026, 10)), .finish])
        let request = uploading.writes.saveRequests.first
        #expect(request?.categoryAmounts.map(\.categoryId) == [42])
        #expect(request?.categoryAmounts.map(\.amount) == [50000])
        #expect(request?.totalAmount == 50000)

        // 짝: 금액 없는 임시 번호 줄은 보내지 않으므로 막지 않는다.
        let blank = BudgetEditFakes()
        blank.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        blank.chipOrder = [-3, 1]
        let blankLine = blank.makeViewModel()
        blankLine.addCategory(-3)
        blankLine.setDirectTotal(100_000)

        await blankLine.save()

        #expect(blank.writes.events == [.flushPending, .beginWrite, .save(yearMonth(2026, 10)), .finish])
        #expect(blank.writes.saveRequests.first?.categoryAmounts.isEmpty == true)
        #expect(blankLine.toast == nil)
    }

    @Test("올린 뒤 저장이 실패하면 줄이 서버 번호로 남는다 — 칩과 겹치지 않고, 다시 저장하면 한 번만 보낸다")
    func saveFailureAfterUploadKeepsServerIDs() async {
        let fakes = BudgetEditFakes()
        fakes.writes.uploads = [-3: 42]
        fakes.writes.saveResult = { _ in .failure(BudgetWriteError.other(BudgetEditTestError.offline)) }
        let viewModel = fakes.makeViewModelWithNewCategory()
        let changedBefore = viewModel.hasChanges

        await viewModel.save()

        #expect(viewModel.toast == .saveFailed)
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [42])
        #expect(viewModel.draft.categoryLines.map(\.amount) == [50000])
        #expect(viewModel.hasChanges == changedBefore)
        fakes.chipOrder = [42, 1]
        #expect(viewModel.draft.chipCategoryIDs(chipOrder: fakes.chipOrder) == [1])

        fakes.writes.saveResult = { .success(makeBudget($0, total: 50000)) }
        await viewModel.save()
        #expect(fakes.writes.saveRequests.last?.categoryAmounts.map(\.categoryId) == [42])

        // 짝: 올리기가 실패했으면 줄은 임시 번호 그대로다.
        let failing = BudgetEditFakes()
        let kept = failing.makeViewModelWithNewCategory()

        await kept.save()

        #expect(kept.draft.categoryLines.map(\.categoryID) == [-3])
        #expect(kept.draft.categoryLines.map(\.amount) == [50000])
    }

    @Test("전체가 카테고리 합보다 작은 채 저장을 누르면 맞추지 않고 보내지도 않는다 — 합만큼 고치면 저장한다")
    func saveBlockedWhileTotalBelowSum() async {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()
        viewModel.setDirectTotal(300_000)

        await viewModel.save()

        #expect(viewModel.toast == nil)
        #expect(viewModel.draft.directTotal == 300_000)
        #expect(fakes.writes.events.isEmpty)

        viewModel.setDirectTotal(400_000)
        await viewModel.save()

        #expect(viewModel.toast == nil)
        #expect(fakes.writes.saveRequests.count == 1)
        #expect(fakes.writes.saveRequests.first?.totalAmount == 400_000)

        // 짝: 카테고리를 먼저 적은 달(합 600,000) — 전체가 합이라 바로 저장한다.
        let summed = BudgetEditFakes()
        summed.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let summing = summed.makeViewModel()
        summing.addCategory(1)
        summing.setCategoryAmount(600_000, for: 1)

        await summing.save()

        #expect(summing.toast == nil)
        #expect(summed.writes.saveRequests.count == 1)
        #expect(summed.writes.saveRequests.first?.totalAmount == 600_000)
    }

    @Test("편집 중 목록 번호가 바뀌면 초안·기준선의 임시 번호를 서버 번호로 — 한 줄로 남고 바뀐 입력은 그대로")
    func categoryRemapWhileEditingKeepsOneLine() {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModelWithNewCategory()
        let changedBefore = viewModel.hasChanges
        fakes.writes.remap = [-3: 42]
        fakes.chipOrder = [42, 1]

        viewModel.categoriesDidChange()
        viewModel.categoriesDidChange()

        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [42])
        #expect(viewModel.draft.categoryLines.map(\.amount) == [50000])
        #expect(viewModel.hasChanges == changedBefore)
        #expect(viewModel.draft.chipCategoryIDs(chipOrder: fakes.chipOrder) == [1])

        // 기준선에 든 임시 번호 줄도 같이 바꾼다 — 번호만 바뀐 것은 바뀐 입력이 아니다.
        let based = BudgetEditFakes()
        based.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        based.chipOrder = [-3, 1]
        let rebased = based.makeViewModel()
        rebased.addCategory(-3)
        rebased.selectCurrency(.usd)
        #expect(!rebased.hasChanges)
        based.writes.remap = [-3: 42]

        rebased.categoriesDidChange()

        #expect(rebased.draft.categoryLines.map(\.categoryID) == [42])
        #expect(!rebased.hasChanges)

        // 짝: 번호가 바뀌지 않았으면 그대로다.
        let unchanged = BudgetEditFakes()
        let kept = unchanged.makeViewModelWithNewCategory()

        kept.categoriesDidChange()

        #expect(kept.draft.categoryLines.map(\.categoryID) == [-3])
    }
}

// MARK: 쓰기 중 · 삭제

extension BudgetEditViewModelTests {
    @Test("쓰기 중(발급·올리기·저장·삭제)에는 저장·삭제·불러오기·달 이동·닫기·통화 바꾸기가 아무것도 하지 않는다")
    func writeBlocksOtherActions() async {
        let stages: [FakeBudgetWrites.Event] = [
            .ensureIdentity, .flushPending, .save(yearMonth(2026, 10)), .delete(yearMonth(2026, 10))
        ]
        for stage in stages {
            let fakes = BudgetEditFakes()
            fakes.writes.holdAt = stage
            if stage == .ensureIdentity {
                // 신원 없는 비회원이 전체를 적고 저장 — 발급 단계에서 붙잡는다.
                fakes.lastMonth = nil
                fakes.initialBudget = nil
                fakes.writes.hasIdentity = false
            }
            let viewModel = fakes.makeViewModel()
            if stage == .ensureIdentity {
                viewModel.setDirectTotal(100_000)
            }
            let writing = Task {
                if case .delete = stage {
                    viewModel.requestDelete()
                    await viewModel.confirmDialog()
                } else {
                    await viewModel.save()
                }
            }
            await waitUntil { fakes.writes.isHeld }
            #expect(viewModel.isWriting, "\(stage)")
            #expect(!viewModel.canSave, "\(stage)")
            let eventsBefore = fakes.writes.events

            await viewModel.go(by: 1)
            await viewModel.loadPrevious()
            viewModel.requestClose()
            viewModel.requestDelete()
            viewModel.selectCurrency(.usd)
            await viewModel.save()

            #expect(fakes.fetch.calls.isEmpty, "\(stage)")
            #expect(viewModel.dialog == nil, "\(stage)")
            #expect(fakes.outcomes.isEmpty, "\(stage)")
            #expect(fakes.writes.events == eventsBefore, "\(stage)")
            #expect(viewModel.month == yearMonth(2026, 10), "\(stage)")
            #expect(viewModel.draft.currency == .krw, "\(stage)")

            fakes.writes.release()
            await writing.value
            #expect(!viewModel.isWriting, "\(stage)")
            #expect(fakes.outcomes.count == 1, "\(stage)")
        }
    }

    @Test("삭제는 확인 뒤에만 보내고 응답과 표를 넘긴다 — 실패면 입력을 남기고, 범위 밖 달은 닫고 다시 읽게 한다")
    func deleteConfirmsThenFinishes() async {
        let fakes = BudgetEditFakes()
        fakes.writes.token = 9
        let viewModel = fakes.makeViewModel()

        viewModel.requestDelete()
        #expect(viewModel.dialog == .deleteMonth)
        #expect(fakes.writes.events.isEmpty)
        viewModel.cancelDialog()
        #expect(viewModel.dialog == nil)
        #expect(fakes.writes.events.isEmpty)
        #expect(fakes.outcomes.isEmpty)

        viewModel.requestDelete()
        await viewModel.confirmDialog()

        #expect(viewModel.dialog == nil)
        #expect(fakes.writes.events == [.beginWrite, .delete(yearMonth(2026, 10)), .finish])
        #expect(fakes.finished == [.deleted(yearMonth(2026, 10), status: .notSet, writeToken: 9)])
        #expect(!viewModel.isWriting)

        // 짝: 실패 — 저장·삭제 거절 표의 "그 밖" 문구, 입력 그대로.
        let failing = BudgetEditFakes()
        failing.writes.deleteResult = { _ in .failure(BudgetWriteError.other(BudgetEditTestError.offline)) }
        let kept = failing.makeViewModel()
        let before = kept.draft
        kept.requestDelete()
        await kept.confirmDialog()
        #expect(kept.toast == .deleteFailed)
        #expect(failing.outcomes.isEmpty)
        #expect(kept.draft == before)
        #expect(kept.showsDeleteButton)
        #expect(!kept.isWriting)

        // 범위 밖 달 — 저장과 같이 닫고 그 달을 다시 읽게 한다.
        let outOfRange = BudgetEditFakes()
        outOfRange.writes.deleteResult = { _ in .failure(BudgetWriteError.monthOutOfRange) }
        let rejected = outOfRange.makeViewModel()
        rejected.requestDelete()
        await rejected.confirmDialog()
        #expect(outOfRange.finished == [.reloadRequired(yearMonth(2026, 10), .monthNotAllowed)])
        #expect(rejected.toast == nil)

        // 예산이 없는 달에는 삭제 버튼이 없고 묻지 않는다.
        let unset = BudgetEditFakes()
        unset.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let unsetMonth = unset.makeViewModel()
        unsetMonth.requestDelete()
        #expect(unsetMonth.dialog == nil)
    }
}

// MARK: 쓰기 중 읽기 응답 · 확인 창

extension BudgetEditViewModelTests {
    @Test("쓰기 전에 시작한 지난 달 읽기의 응답은 버린다 — 성공이면 바꿀까요를, 실패면 실패 토스트를 띄우지 않고 입력 그대로")
    func readStartedBeforeWriteIsDropped() async {
        let outcomes: [(name: String, result: Result<MonthlyBudget, any Error>)] = [
            ("성공", .success(makeBudget(yearMonth(2026, 9), total: 90000))),
            ("실패", .failure(BudgetEditTestError.offline))
        ]
        for (name, result) in outcomes {
            let fakes = BudgetEditFakes()
            fakes.writes.holdAt = .save(yearMonth(2026, 10))
            fakes.writes.saveResult = { _ in .failure(BudgetWriteError.other(BudgetEditTestError.offline)) }
            let viewModel = fakes.makeViewModel()
            let before = viewModel.draft
            var saving: Task<Void, Never>?

            await fakes.loadPrevious(on: viewModel) {
                saving = Task { await viewModel.save() }
                await waitUntil { fakes.writes.isHeld }
                fakes.fetch.result = { _ in result }
            }

            #expect(viewModel.dialog == nil, "\(name)")
            #expect(viewModel.toast == nil, "\(name)")
            #expect(viewModel.draft == before, "\(name)")
            #expect(!viewModel.isPreviousApplied, "\(name)")

            fakes.writes.release()
            await saving?.value

            #expect(viewModel.dialog == nil, "\(name)")
            #expect(viewModel.toast == .saveFailed, "\(name)")
            #expect(viewModel.draft == before, "\(name)")
            #expect(fakes.outcomes.isEmpty, "\(name)")
        }

        // 짝: 쓰기가 없으면 같은 응답이 바꿀까요를 띄운다.
        let idleFakes = BudgetEditFakes()
        let idle = idleFakes.makeViewModel()
        await idleFakes.loadPrevious(on: idle) {}
        #expect(idle.dialog == .replaceWithPrevious)
    }

    @Test("쓰기 중에는 확인 창의 확인이 아무것도 하지 않는다 — 쓰기가 없으면 같은 확인이 닫는다")
    func confirmDuringWriteDoesNothing() async {
        let fakes = BudgetEditFakes()
        fakes.writes.holdAt = .save(yearMonth(2026, 10))
        fakes.writes.saveResult = { _ in .failure(BudgetWriteError.other(BudgetEditTestError.offline)) }
        let viewModel = fakes.makeViewModel()
        viewModel.setDirectTotal(600_000)
        viewModel.requestClose()
        #expect(viewModel.dialog == .leave)
        let saving = Task { await viewModel.save() }
        await waitUntil { fakes.writes.isHeld }

        await viewModel.confirmDialog()

        #expect(viewModel.dialog == .leave)
        #expect(!fakes.writes.events.contains(.finish))
        #expect(fakes.outcomes.isEmpty)
        fakes.writes.release()
        await saving.value
        #expect(viewModel.toast == .saveFailed)
        #expect(viewModel.dialog == .leave)
        #expect(fakes.outcomes.isEmpty)

        // 짝: 쓰기가 없으면 같은 확인이 닫는다.
        let idleFakes = BudgetEditFakes()
        let idle = idleFakes.makeViewModel()
        idle.setDirectTotal(600_000)
        idle.requestClose()
        #expect(idle.dialog == .leave)

        await idle.confirmDialog()

        #expect(idleFakes.writes.events == [.finish])
        #expect(idleFakes.finished == [.dismissed(yearMonth(2026, 10))])
    }
}

// MARK: 쓰기 중 입력

extension BudgetEditViewModelTests {
    @Test("쓰기 중(올리기·저장)에는 금액·칩·결제수단 펼치기·전체 칸 들고 남이 초안을 바꾸지 않고 토스트도 없다 — 저장은 쓰기 전 값")
    func editsIgnoredWhileWriting() async {
        /// 전체를 카테고리 합보다 작게 치고 끝냄·전체를 넘는 카테고리·상한 넘는 카테고리·결제수단·칩·펼치기.
        /// 상한 넘는 카테고리 입력의 결과를 돌려준다.
        func editEverything(_ viewModel: BudgetEditViewModel) -> Bool {
            viewModel.setDirectTotal(300_000)
            viewModel.setCategoryAmount(450_000, for: 1)
            let overLimit = viewModel.setCategoryAmount(AddExpenseViewModel.maximumAmount + 1, for: 1)
            viewModel.setPaymentAmount(100_000, for: .creditCard)
            viewModel.addCategory(2)
            viewModel.togglePaymentSection()
            viewModel.endTotalEditing()
            return overLimit
        }

        // 요청을 만들기 전(올리기)과 만든 뒤(저장) 두 시점 모두.
        let stages: [FakeBudgetWrites.Event] = [.flushPending, .save(yearMonth(2026, 10))]
        for stage in stages {
            let fakes = BudgetEditFakes()
            fakes.writes.holdAt = stage
            let viewModel = fakes.makeViewModel()
            let before = viewModel.draft
            let saving = Task { await viewModel.save() }
            await waitUntil { fakes.writes.isHeld }

            let overLimit = editEverything(viewModel)

            #expect(overLimit, "\(stage)")
            #expect(viewModel.draft == before, "\(stage)")
            #expect(viewModel.toast == nil, "\(stage)")
            #expect(viewModel.categoryOverTotalRejectionCount == 0, "\(stage)")
            #expect(!viewModel.isPreviousApplied, "\(stage)")

            fakes.writes.release()
            await saving.value

            let request = fakes.writes.saveRequests.last
            #expect(fakes.writes.saveRequests.count == 1, "\(stage)")
            #expect(request?.totalAmount == 500_000, "\(stage)")
            #expect(request?.categoryAmounts.map(\.categoryId) == [1], "\(stage)")
            #expect(request?.categoryAmounts.map(\.amount) == [400_000], "\(stage)")
            #expect(request?.paymentGroupAmounts.isEmpty == true, "\(stage)")
        }

        // 짝: 쓰기가 없으면 같은 호출이 초안을 바꾸고, 전체를 넘게 하는 카테고리 입력(상한 포함)은 거절하며 막은 횟수가
        // 오르고, 작게 친 전체는 맞추지 않는다.
        let idleFakes = BudgetEditFakes()
        let idle = idleFakes.makeViewModel()
        let before = idle.draft

        let overLimit = editEverything(idle)

        #expect(!overLimit)
        #expect(idle.draft != before)
        #expect(idle.draft.directTotal == 300_000)
        #expect(idle.draft.categoryLines.map(\.categoryID) == [1, 2])
        #expect(idle.draft.categoryLines.map(\.amount) == [400_000, nil])
        #expect(idle.draft.paymentAmounts[.creditCard] == 100_000)
        #expect(idle.draft.isPaymentExpanded)
        #expect(idle.categoryOverTotalRejectionCount == 2)
        #expect(idle.toast == nil)
    }
}

// MARK: 임시 번호 줄과 칩

extension BudgetEditViewModelTests {
    @Test("올리기가 번호를 바꾼 뒤 줄을 옮기기 전에도 같은 카테고리는 칩에 없고 다시 넣을 수 없다 — 다른 칩은 넣는다")
    func sameCategoryUnderTempIDIsNotAddedTwice() {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModelWithNewCategory()
        fakes.writes.remap = [-3: 42]
        fakes.chipOrder = [42, 1]

        #expect(viewModel.chipCategoryIDs == [1])
        viewModel.addCategory(42)
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [-3])

        viewModel.categoriesDidChange()

        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [42])
        #expect(viewModel.draft.categoryLines.map(\.amount) == [50000])

        // 짝: 다른 카테고리 칩은 줄을 더한다.
        let other = BudgetEditFakes()
        let adding = other.makeViewModelWithNewCategory()
        other.writes.remap = [-3: 42]
        other.chipOrder = [42, 1]

        adding.addCategory(1)

        #expect(Set(adding.draft.categoryLines.map(\.categoryID)) == [-3, 1])
        #expect(adding.chipCategoryIDs.isEmpty)
    }
}

// MARK: 금액 줄 이름

extension BudgetEditViewModelTests {
    @Test("금액 줄 이름 — 서버 삭제 표시가 먼저(목록에 있어도), 다음은 지금 목록, 그다음 응답의 서버 이름, 어디에도 없으면 삭제된 카테고리")
    func lineLabelPrefersServerDeletion() {
        let fakes = BudgetEditFakes()
        // 7 = 로컬 삭제 대기라 목록에 없다. 5 = 서버가 삭제로 표시했지만 이 기기 목록에는 아직 있다.
        fakes.initialBudget = makeBudget(
            yearMonth(2026, 10),
            total: 500_000,
            categories: [namedCategoryLine(7, "여행", 100_000), namedCategoryLine(5, "간식", 50000, isDeleted: true)]
        )
        fakes.chipOrder = [42, 1]
        let viewModel = fakes.makeViewModel()
        viewModel.addCategory(42)
        // 짝: 목록에도 응답에도 없는 줄 — 칩으로 넣은 뒤 다른 기기에서 지워져 목록에서 빠진 카테고리.
        viewModel.addCategory(99)
        let categories = [namedCategory(42, "커피"), namedCategory(5, "간식")]

        func label(_ id: Int) -> BudgetEditLineLabel? {
            let line = viewModel.draft.categoryLines.first { $0.categoryID == id }
            return line.map { viewModel.lineLabel($0, in: categories) }
        }
        /// `.category` 면 그 이름, 아니면 nil.
        func name(_ id: Int) -> String? {
            guard case let .category(category) = label(id) else {
                return nil
            }
            return category.displayNameKo
        }
        func isDeleted(_ id: Int) -> Bool {
            guard case .deleted = label(id) else {
                return false
            }
            return true
        }

        #expect(name(42) == "커피")
        #expect(name(7) == "여행")
        #expect(isDeleted(5))
        #expect(isDeleted(99))
    }
}

// MARK: 먼저 적은 쪽이 기준(UI_GUIDE 2026-10-05) — 따로 적지 않으면 갈래 A(전체 500,000 · 카테고리 1 몫 400,000)

extension BudgetEditViewModelTests {
    @Test("BETR.S0-R2 붙여넣기도 같은 길이다 — 합이 전체를 넘으면 칸 글자 그대로(rejected), 같으면 받는다, 소수 통화도 같다")
    func pastedCategoryAmountFollowsTotalCap() {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()
        viewModel.addCategory(2)
        let empty = NSRange(location: 0, length: 0)

        let over = BudgetAmountInput.commit("100001", in: empty, of: "", decimalPlaces: 0) {
            viewModel.setCategoryAmount($0, for: 2)
        }
        #expect(over == .rejected)
        #expect(viewModel.draft.categoryLines.map(\.amount) == [400_000, nil])

        let fits = BudgetAmountInput.commit("100000", in: empty, of: "", decimalPlaces: 0) {
            viewModel.setCategoryAmount($0, for: 2)
        }
        #expect(fits == .accepted("100,000"))
        #expect(viewModel.draft.categorySum == 500_000)

        // 소수 통화 — 전체 450.50 · 카테고리 1 몫 300.25.
        let usd = BudgetEditFakes()
        usd.initialBudget = makeBudget(
            yearMonth(2026, 10),
            currency: .usd,
            total: Decimal(45050) / 100,
            categories: [categoryLine(1, Decimal(30025) / 100)]
        )
        let usdViewModel = usd.makeViewModel()
        usdViewModel.addCategory(2)
        let usdOver = BudgetAmountInput.commit("15026", in: empty, of: "", decimalPlaces: 2) {
            usdViewModel.setCategoryAmount($0, for: 2)
        }
        #expect(usdOver == .rejected)
        let usdFits = BudgetAmountInput.commit("15025", in: empty, of: "", decimalPlaces: 2) {
            usdViewModel.setCategoryAmount($0, for: 2)
        }
        #expect(usdFits == .accepted("150.25"))
        #expect(usdViewModel.draft.categorySum == Decimal(45050) / 100)
    }

    @Test("BETR.S0-R3 저장 캡슐은 초안의 저장 가능 판정을 따른다 — 합보다 1 작은 전체는 꺼지고 합과 같으면 켜진다")
    func canSaveFollowsCategoryExcess() {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()
        #expect(viewModel.canSave)

        viewModel.setDirectTotal(399_999)
        #expect(viewModel.draft.categoryExcess == 1)
        #expect(!viewModel.canSave)

        viewModel.setDirectTotal(400_000)
        #expect(viewModel.draft.categoryExcess == nil)
        #expect(viewModel.canSave)
    }

    @Test("BETR.S0-R4 전체를 비우면 입력 중에는 저장이 꺼지고, 벗어나면 카테고리 합이 전체가 된다 — 토스트 없음")
    func clearingTotalThenLeavingSwitchesToSum() {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()

        #expect(viewModel.setDirectTotal(nil))
        #expect(viewModel.draft.totalMode == .direct)
        #expect(!viewModel.canSave)

        viewModel.endTotalEditing()
        #expect(viewModel.draft.totalMode == .categorySum)
        #expect(viewModel.draft.total == 400_000)
        #expect(viewModel.canSave)
        #expect(viewModel.toast == nil)
    }

    @Test("BETR.S0-R5 갈래 B 의 전체 칸은 잠겨 있다 — 치면 거절·토스트, 누르면 토스트, 초안·바뀐 입력 그대로")
    func lockedTotalShowsToast() {
        let fakes = BudgetEditFakes()
        fakes.initialBudget = makeBudget(yearMonth(2026, 10), total: 300_000, categories: [categoryLine(1, 300_000)])
        let viewModel = fakes.makeViewModel()
        #expect(viewModel.draft.totalMode == .categorySum)
        let before = viewModel.draft

        #expect(!viewModel.setDirectTotal(1))
        #expect(viewModel.toast == .totalLocked)
        #expect(viewModel.draft == before)
        #expect(!viewModel.hasChanges)

        viewModel.toast = nil
        viewModel.tapLockedTotal()
        #expect(viewModel.toast == .totalLocked)

        // 짝: 갈래 A 는 잠기지 않는다 — 누름에 토스트가 없고 친 값이 들어간다.
        let directFakes = BudgetEditFakes()
        let direct = directFakes.makeViewModel()
        direct.tapLockedTotal()
        #expect(direct.toast == nil)
        #expect(direct.setDirectTotal(600_000))
        #expect(direct.toast == nil)
        #expect(direct.draft.total == 600_000)
    }

    @Test("BETR.S0-R6 넘는 카테고리 입력은 토스트 없이 거절하고 경고를 켠다 — 거절마다 횟수를 올리고, 받아들인 입력·칸 벗어남이 끈다")
    func overTotalRejectionRaisesWarning() {
        let fakes = BudgetEditFakes()
        let viewModel = fakes.makeViewModel()
        viewModel.addCategory(2)

        #expect(!viewModel.setCategoryAmount(100_001, for: 2))
        #expect(viewModel.toast == nil)
        #expect(viewModel.showsCategoryOverTotalWarning)
        #expect(viewModel.categoryOverTotalRejectionCount == 1)
        #expect(viewModel.draft.categoryLines.map(\.amount) == [400_000, nil])

        #expect(!viewModel.setCategoryAmount(100_002, for: 2))
        #expect(viewModel.showsCategoryOverTotalWarning)
        #expect(viewModel.categoryOverTotalRejectionCount == 2)

        #expect(viewModel.setCategoryAmount(60000, for: 2))
        #expect(!viewModel.showsCategoryOverTotalWarning)
        #expect(viewModel.categoryOverTotalRejectionCount == 2)

        #expect(!viewModel.setCategoryAmount(100_001, for: 2))
        #expect(viewModel.showsCategoryOverTotalWarning)
        viewModel.endCategoryEditing()
        #expect(!viewModel.showsCategoryOverTotalWarning)
        #expect(viewModel.categoryOverTotalRejectionCount == 3)
    }

    @Test("BETR.S0-R6 경고는 초안을 바꾸는 다음 입력이면 어느 길이든 꺼진다 — 전체·결제수단·칩·줄 빼기·통화·달 이동·불러오기·모두 지우기")
    func overTotalWarningClearsOnNextEdit() async {
        let edits: [(String, @MainActor (BudgetEditViewModel) async -> Void)] = [
            ("전체", { $0.setDirectTotal(700_000) }),
            ("결제수단", { $0.setPaymentAmount(10000, for: .creditCard) }),
            ("칩", { $0.addCategory(3) }),
            ("줄 빼기", { $0.removeCategory(2) }),
            ("통화", { viewModel in
                viewModel.selectCurrency(.usd)
                await viewModel.confirmDialog()
            }),
            ("달 이동", { viewModel in
                await viewModel.go(by: 1)
                await viewModel.confirmDialog()
            }),
            ("불러오기", { viewModel in
                await viewModel.loadPrevious()
                await viewModel.confirmDialog()
            }),
            ("모두 지우기", { viewModel in
                viewModel.requestClearAll()
                await viewModel.confirmDialog()
            })
        ]
        for (name, edit) in edits {
            let fakes = BudgetEditFakes()
            let viewModel = fakes.makeViewModel()
            viewModel.addCategory(2)
            #expect(!viewModel.setCategoryAmount(100_001, for: 2), "\(name)")
            #expect(viewModel.showsCategoryOverTotalWarning, "\(name)")

            await edit(viewModel)

            #expect(viewModel.dialog == nil, "\(name)")
            #expect(!viewModel.showsCategoryOverTotalWarning, "\(name)")
            #expect(viewModel.categoryOverTotalRejectionCount == 1, "\(name)")
        }
    }

    @Test("BETR.S0-R6 짝: 상한 거절은 토스트만 · 합 초과 상태의 늘리는 키는 경고 없이 횟수만 · 쓰는 중에는 경고도 토스트도 없다")
    func overTotalWarningPairs() async {
        // 카테고리를 먼저 적은 달의 상한 — 지금처럼 상한 토스트, 경고 없음.
        let limitFakes = BudgetEditFakes()
        limitFakes.initialBudget = makeNotSetBudget(yearMonth(2026, 10))
        let limited = limitFakes.makeViewModel()
        limited.addCategory(1)
        limited.addCategory(2)
        #expect(limited.setCategoryAmount(99_998_999, for: 1))
        #expect(!limited.setCategoryAmount(1001, for: 2))
        #expect(limited.toast == .amountOverLimit)
        #expect(!limited.showsCategoryOverTotalWarning)
        #expect(limited.categoryOverTotalRejectionCount == 0)

        // 전체를 합보다 작게 줄인 상태 — 늘리는 키는 막고 경고 줄은 켜지 않되 횟수는 올린다.
        let excessFakes = BudgetEditFakes()
        let excess = excessFakes.makeViewModel()
        excess.setDirectTotal(300_000)
        #expect(excess.draft.categoryExcess == 100_000)
        #expect(!excess.setCategoryAmount(450_000, for: 1))
        #expect(!excess.showsCategoryOverTotalWarning)
        #expect(excess.categoryOverTotalRejectionCount == 1)
        #expect(excess.toast == nil)
        #expect(excess.draft.categoryLines.map(\.amount) == [400_000])

        // 쓰는 중 — 같은 입력이 아무것도 바꾸지 않는다.
        let writingFakes = BudgetEditFakes()
        writingFakes.writes.holdAt = .save(yearMonth(2026, 10))
        let writing = writingFakes.makeViewModel()
        writing.addCategory(2)
        let saving = Task { await writing.save() }
        await waitUntil { writingFakes.writes.isHeld }
        #expect(writing.setCategoryAmount(100_001, for: 2))
        #expect(!writing.showsCategoryOverTotalWarning)
        #expect(writing.categoryOverTotalRejectionCount == 0)
        #expect(writing.toast == nil)
        writingFakes.writes.release()
        await saving.value
    }

    @Test("BETR.S0-R7 저장은 맞추지 않고 갈래의 전체를 보낸다 — A 는 적은 전체, B 는 카테고리 합")
    func saveSendsModeTotal() async {
        let shares = [categoryLine(1, 200_000), categoryLine(2, 100_000)]
        let directFakes = BudgetEditFakes()
        directFakes.initialBudget = makeBudget(yearMonth(2026, 10), total: 500_000, categories: shares)
        let direct = directFakes.makeViewModel()
        #expect(direct.draft.totalMode == .direct)

        await direct.save()

        let directRequest = directFakes.writes.saveRequests.first
        #expect(directRequest?.totalAmount == 500_000)
        #expect(directRequest?.categoryAmounts.map(\.categoryId) == [1, 2])
        #expect(directRequest?.categoryAmounts.map(\.amount) == [200_000, 100_000])

        let sumFakes = BudgetEditFakes()
        sumFakes.initialBudget = makeBudget(yearMonth(2026, 10), total: 300_000, categories: shares)
        let bySum = sumFakes.makeViewModel()
        #expect(bySum.draft.totalMode == .categorySum)

        await bySum.save()

        #expect(sumFakes.writes.saveRequests.first?.totalAmount == 300_000)
    }

    @Test("BETR.S0-R7 짝: 전체가 합보다 작거나 비우는 중이면 저장이 꺼지고 눌러도 보내지 않으며 토스트도 없다")
    func saveSkippedWhenNotSaveable() async {
        let fakes = BudgetEditFakes()
        let below = fakes.makeViewModel()
        below.setDirectTotal(300_000)
        #expect(!below.canSave)
        await below.save()
        #expect(below.toast == nil)
        #expect(below.draft.directTotal == 300_000)

        let clearing = fakes.makeViewModel()
        clearing.setDirectTotal(nil)
        #expect(!clearing.canSave)
        await clearing.save()
        #expect(clearing.toast == nil)

        #expect(fakes.writes.events.isEmpty)
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

/// 쓰기 쪽 가짜 — 신원 발급·카테고리 올리기·목록 새로 받기·쓰기 표·저장·삭제. 호출 순서와 인자를 한 기록(`events`)에 남긴다.
/// 따로 적지 않으면 신원 있음·올릴 것 없음·번호 그대로이고, 저장은 전체 500,000 응답·삭제는 미설정 응답을 돌려준다.
/// `holdAt` 을 주면 그 단계에서 붙잡아 두고, 테스트가 `release` 로 놓는다.
@MainActor
private final class FakeBudgetWrites {
    enum Event: Equatable {
        case ensureIdentity
        case flushPending
        case refreshCategories
        case beginWrite
        case save(ServerMonth)
        case delete(ServerMonth)
        /// 끝 결과(`onFinish`).
        case finish
    }

    private(set) var events: [Event] = []
    /// 저장을 부를 때마다 하나.
    private(set) var saveRequests: [SaveBudgetRequest] = []
    var hasIdentity = true
    /// false 면 발급을 불러도 신원이 생기지 않는다 — 발급 함수는 실패해도 던지지 않는다.
    var issuesIdentity = true
    /// 서버 번호를 받은 임시 번호. 없으면 번호 그대로.
    var remap: [Int: Int] = [:]
    /// 올리기가 서버 번호를 받아 `remap` 에 더하는 번호. 비어 있으면 올리기 실패와 같다 — 올리기도 던지지 않는다.
    var uploads: [Int: Int] = [:]
    var token = 7
    var saveResult: (ServerMonth) -> Result<MonthlyBudget, any Error>
    var deleteResult: (ServerMonth) -> Result<MonthlyBudget, any Error>
    var holdAt: Event?
    private var held: CheckedContinuation<Void, Never>?

    init() {
        saveResult = { .success(makeBudget($0, total: 500_000)) }
        deleteResult = { .success(makeNotSetBudget($0)) }
    }

    var isHeld: Bool {
        held != nil
    }

    func record(_ event: Event) {
        events.append(event)
    }

    func release() {
        holdAt = nil
        let continuation = held
        held = nil
        continuation?.resume()
    }

    func ensureIdentity() async {
        await pass(.ensureIdentity)
        if issuesIdentity {
            hasIdentity = true
        }
    }

    func flushPending() async {
        await pass(.flushPending)
        remap.merge(uploads) { $1 }
    }

    func refreshCategories() async {
        await pass(.refreshCategories)
    }

    func resolvedID(for id: Int) -> Int {
        remap[id] ?? id
    }

    func beginWrite() -> Int {
        events.append(.beginWrite)
        return token
    }

    func save(_ month: ServerMonth, _ request: SaveBudgetRequest) async throws -> MonthlyBudget {
        saveRequests.append(request)
        await pass(.save(month))
        return try saveResult(month).get()
    }

    func delete(_ month: ServerMonth) async throws -> MonthlyBudget {
        await pass(.delete(month))
        return try deleteResult(month).get()
    }

    /// 붙잡는 것은 한 번뿐이다 — 막혀야 할 두 번째 쓰기가 들어오면 기다리지 않고 기록에만 남아, 테스트가 멈추지 않고 빨갛게 된다.
    private func pass(_ event: Event) async {
        events.append(event)
        guard event == holdAt, held == nil else {
            return
        }
        await withCheckedContinuation { held = $0 }
    }
}

@MainActor
private final class BudgetEditFakes {
    /// 끝 결과를 비교할 수 있는 모양으로. 응답은 달과 전체 몫(저장)·상태(삭제)만 본다.
    enum Finished: Equatable {
        case dismissed(ServerMonth?)
        case saved(ServerMonth, total: Decimal?, writeToken: Int)
        case deleted(ServerMonth, status: BudgetStatus, writeToken: Int)
        case reloadRequired(ServerMonth, BudgetEditReloadReason)
    }

    let fetch = FakeBudgetFetch { .success(makeBudget($0, total: Decimal($0.month) * 10000)) }
    let writes = FakeBudgetWrites()
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

    var finished: [Finished] {
        outcomes.map { outcome in
            switch outcome {
            case let .dismissed(month):
                .dismissed(month)
            case let .saved(budget, token):
                .saved(yearMonth(budget.year, budget.month), total: budget.total?.budgetAmount, writeToken: token)
            case let .deleted(budget, token):
                .deleted(yearMonth(budget.year, budget.month), status: budget.status, writeToken: token)
            case let .reloadRequired(month, reason):
                .reloadRequired(month, reason)
            }
        }
    }

    func makeViewModel() -> BudgetEditViewModel {
        BudgetEditViewModel(
            context: BudgetEditViewModel.Context(month: month, lastMonth: lastMonth, initialBudget: initialBudget),
            chipOrder: { self.chipOrder },
            baseCurrency: baseCurrency,
            fetch: { year, month in try await self.fetch.call(yearMonth(year, month)) },
            save: { year, month, request in try await self.writes.save(yearMonth(year, month), request) },
            delete: { year, month in try await self.writes.delete(yearMonth(year, month)) },
            hasIdentity: { self.writes.hasIdentity },
            ensureIdentity: { await self.writes.ensureIdentity() },
            flushPendingCategories: { await self.writes.flushPending() },
            resolvedCategoryID: { self.writes.resolvedID(for: $0) },
            refreshCategories: { await self.writes.refreshCategories() },
            beginWrite: { self.writes.beginWrite() },
            onFinish: { outcome in
                self.writes.record(.finish)
                self.outcomes.append(outcome)
            }
        )
    }

    /// 미설정 달에 방금 만든 내 카테고리(임시 번호 -3) 줄 50,000 을 넣은 편집 화면. 칩 순서는 [-3, 1] 이다.
    func makeViewModelWithNewCategory() -> BudgetEditViewModel {
        initialBudget = makeNotSetBudget(month)
        chipOrder = [-3, 1]
        let viewModel = makeViewModel()
        viewModel.addCategory(-3)
        viewModel.setCategoryAmount(50000, for: -3)
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [-3])
        return viewModel
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

private func namedCategory(_ id: Int, _ nameKo: String) -> woni_app.Category {
    Category(id: id, code: "CUSTOM", displayNameKo: nameKo, displayNameEn: nameKo, icon: nil, sortOrder: id)
}

private func namedCategoryLine(
    _ id: Int,
    _ nameKo: String,
    _ amount: Decimal,
    isDeleted: Bool = false
) -> BudgetCategoryLine {
    BudgetCategoryLine(category: namedCategory(id, nameKo), isDeleted: isDeleted, line: under(amount))
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
