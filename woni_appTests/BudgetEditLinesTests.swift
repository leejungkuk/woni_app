//
//  BudgetEditLinesTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 편집 금액 줄 빼기 · 삭제된 카테고리 칩 · 입력 모두 지우기 · 같은 금액 나가기 판정(UI_GUIDE 2026-10-04 결정).
/// 따로 적지 않으면 회원이 2026-10 을 연다. 이 달 응답은 전체 500,000 이고 카테고리 줄은 응답 순서대로
/// 1(몫 100,000 · 쓴 돈 30,000) · 5(삭제 · 몫 50,000 · 쓴 돈 12,000) · 6(삭제 · 몫 20,000 · 쓴 돈 0) ·
/// 8(삭제 · 몫 30,000 · 쓴 돈 7,000) · 9(삭제 · 몫 없음 · 쓴 돈 4,000)다. 기기 칩 순서는 [1, 2, 3, 4] 다.
@MainActor
struct BudgetEditLinesTests {
    @Test("BDF.S2-R1 금액 있는 줄을 빼면 확인 없이 빠지고 그 카테고리가 칩 순서의 원래 자리로 돌아온다 — 맨 앞·가운데·맨 뒤")
    func removingLineReturnsChipToItsPlace() {
        // 1(맨 앞) 100,000 · 3(가운데) 70,000 · 4(맨 뒤) 40,000. 2 만 칩에 있다.
        let cases: [(id: Int, chips: [Int])] = [(1, [1, 2]), (3, [2, 3]), (4, [2, 4])]
        for (id, chips) in cases {
            let fakes = LinesFakes()
            fakes.initialBudget = makeBudget(total: 210_000, categories: [
                categoryLine(1, budget: 100_000), categoryLine(3, budget: 70000), categoryLine(4, budget: 40000)
            ])
            let viewModel = fakes.makeViewModel()
            #expect(viewModel.chipCategoryIDs == [2])

            viewModel.removeCategory(id)

            #expect(!viewModel.draft.categoryLines.map(\.categoryID).contains(id), "\(id)")
            #expect(viewModel.draft.categoryLines.count == 2, "\(id)")
            #expect(viewModel.chipCategoryIDs == chips, "\(id)")
            #expect(viewModel.dialog == nil, "\(id)")
        }
    }

    @Test("BDF.S2-R1 줄을 빼면 자동 합계 전체가 그만큼 줄고, 빈 줄·내 새 카테고리(임시 번호) 줄도 같게 빠진다")
    func removingLineLowersAutomaticTotal() {
        let fakes = LinesFakes()
        fakes.initialBudget = makeBudget(total: 210_000, categories: [
            categoryLine(1, budget: 100_000), categoryLine(3, budget: 70000), categoryLine(4, budget: 40000)
        ])
        let viewModel = fakes.makeViewModel()
        #expect(viewModel.draft.isTotalAutomatic)
        #expect(viewModel.draft.total == 210_000)

        viewModel.removeCategory(3)
        #expect(viewModel.draft.categorySum == 140_000)
        #expect(viewModel.draft.total == 140_000)

        // 빈 줄.
        viewModel.addCategory(2)
        #expect(viewModel.chipCategoryIDs == [3])
        viewModel.removeCategory(2)
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [1, 4])
        #expect(viewModel.chipCategoryIDs == [2, 3])

        // 내 새 카테고리 — 음수 임시 번호.
        let newFakes = LinesFakes()
        newFakes.initialBudget = makeNotSetBudget()
        newFakes.chipOrder = [-3, 1]
        let adding = newFakes.makeViewModel()
        adding.addCategory(-3)
        adding.setCategoryAmount(50000, for: -3)
        #expect(adding.chipCategoryIDs == [1])
        adding.removeCategory(-3)
        #expect(adding.draft.categoryLines.isEmpty)
        #expect(adding.draft.total == nil)
        #expect(adding.chipCategoryIDs == [-3, 1])
    }

    @Test("BDF.S2-R1 짝: 줄에 없는 번호를 빼면 초안 그대로, 쓰는 중에 빼면 무시한다")
    func removingIgnoredWhenAbsentOrWriting() async {
        let fakes = LinesFakes()
        let viewModel = fakes.makeViewModel()
        let opened = viewModel.draft

        viewModel.removeCategory(2)
        viewModel.removeCategory(9)
        #expect(viewModel.draft == opened)

        let saving = await fakes.startHeldSave(viewModel)
        viewModel.removeCategory(1)
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [1, 5, 6, 8])
        fakes.releaseSave()
        await saving.value
    }
}

// MARK: 삭제된 카테고리 칩

extension BudgetEditLinesTests {
    @Test("BDF.S2-R2 삭제된 칩 = 이 달 응답에서 몫이 있던 삭제된 카테고리 중 지금 줄에 없고 쓴 돈이 있는 것, 응답 순서")
    func deletedChipsFollowServerSpending() {
        let fakes = LinesFakes()
        let viewModel = fakes.makeViewModel()
        // 처음 열 때는 모두 줄에 있다. 9 는 몫이 없어 줄도 칩도 아니다.
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [1, 5, 6, 8])
        #expect(viewModel.deletedChipCategoryIDs.isEmpty)

        viewModel.removeCategory(5)
        #expect(viewModel.deletedChipCategoryIDs == [5])

        // 쓴 돈 0 — 빼도 칩이 없다.
        viewModel.removeCategory(6)
        #expect(viewModel.deletedChipCategoryIDs == [5])

        // 뺀 순서(8 이 나중)가 아니라 응답 순서.
        viewModel.removeCategory(8)
        #expect(viewModel.deletedChipCategoryIDs == [5, 8])
        #expect(!viewModel.deletedChipCategoryIDs.contains(9))
    }

    @Test("BDF.S2-R2 통화를 바꿔 사용액 줄이 안 보여도 판정은 이 달 응답 값 그대로다")
    func deletedChipsIgnoreCurrencyChange() async {
        let fakes = LinesFakes()
        let viewModel = fakes.makeViewModel()
        viewModel.removeCategory(5)
        viewModel.removeCategory(6)

        viewModel.selectCurrency(.usd)
        await viewModel.confirmDialog()

        #expect(viewModel.draft.currency == .usd)
        #expect(viewModel.draft.spent(forCategory: 8) == nil)
        #expect(viewModel.deletedChipCategoryIDs == [5])
        viewModel.removeCategory(8)
        #expect(viewModel.deletedChipCategoryIDs == [5, 8])
    }

    @Test("BDF.S2-R2 짝: 신원 없는 비회원·미설정 달은 응답 줄이 없어 삭제된 칩이 없다")
    func deletedChipsEmptyWithoutResponseLines() {
        let memberless = LinesFakes()
        memberless.lastMonth = nil
        memberless.initialBudget = nil
        #expect(memberless.makeViewModel().deletedChipCategoryIDs.isEmpty)

        let unset = LinesFakes()
        unset.initialBudget = makeNotSetBudget()
        let viewModel = unset.makeViewModel()
        viewModel.addCategory(1)
        viewModel.removeCategory(1)
        #expect(viewModel.deletedChipCategoryIDs.isEmpty)
    }

    @Test("BDF.S2-R3 모두 지우기·지난 달 불러오기로 줄이 빠져도 쓴 돈 있는 삭제된 카테고리만 칩이 된다")
    func deletedChipsAfterClearAllAndPrevious() async {
        let clearing = LinesFakes()
        let cleared = clearing.makeViewModel()
        cleared.requestClearAll()
        await cleared.confirmDialog()
        #expect(cleared.draft.categoryLines.isEmpty)
        #expect(cleared.deletedChipCategoryIDs == [5, 8])

        // 지난 달은 9월 — 삭제된 줄을 빼고 채운다. 칩 판정은 이 달(10월) 응답이다.
        let loading = LinesFakes()
        loading.previous = makeBudget(yearMonth(2026, 9), total: 90000, categories: [
            categoryLine(2, budget: 60000), categoryLine(6, budget: 10000, isDeleted: true)
        ])
        let loaded = loading.makeViewModel()
        await loaded.loadPrevious()
        #expect(loaded.dialog == .replaceWithPrevious)
        await loaded.confirmDialog()
        #expect(loaded.draft.categoryLines.map(\.categoryID) == [2])
        #expect(loaded.deletedChipCategoryIDs == [5, 8])
    }
}

// MARK: 삭제된 칩 다시 넣기

extension BudgetEditLinesTests {
    @Test("BDF.S2-R4 삭제된 칩을 누르면 같은 번호의 삭제된 빈 줄로 들어가 이름이 삭제된 카테고리다 — 금액을 적으면 저장 요청에 들어간다")
    func addingDeletedChipRestoresDeletedLine() {
        let fakes = LinesFakes()
        let viewModel = fakes.makeViewModel()
        viewModel.removeCategory(5)

        viewModel.addDeletedCategory(5)

        let line = viewModel.draft.categoryLines.first { $0.categoryID == 5 }
        #expect(line == BudgetEditCategoryLine(categoryID: 5, isDeleted: true, amount: nil))
        #expect(viewModel.deletedChipCategoryIDs.isEmpty)
        // 이 기기 목록에는 5 가 아직 있어도(삭제 미도착) 줄은 삭제된 카테고리다.
        #expect(isDeletedLabel(line.map { viewModel.lineLabel($0, in: [category(5), category(1)]) }))

        viewModel.setCategoryAmount(45000, for: 5)
        let request = viewModel.draft.saveRequest { $0 }
        let amounts = request?.categoryAmounts.filter { $0.categoryId == 5 }.map(\.amount)
        #expect(amounts == [45000])
    }

    @Test("BDF.S2-R4 짝: 삭제된 칩 목록에 없는 번호(쓴 돈 0 · 응답에 없음 · 이미 줄)와 쓰는 중에 누른 삭제된 칩은 무시한다")
    func addingDeletedChipIgnoresOtherIDs() async {
        let fakes = LinesFakes()
        let viewModel = fakes.makeViewModel()
        viewModel.removeCategory(6)
        let before = viewModel.draft

        viewModel.addDeletedCategory(6)
        viewModel.addDeletedCategory(2)
        viewModel.addDeletedCategory(9)
        viewModel.addDeletedCategory(8)

        #expect(viewModel.draft == before)
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [1, 5, 8])

        viewModel.removeCategory(5)
        let saving = await fakes.startHeldSave(viewModel)
        viewModel.addDeletedCategory(5)
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [1, 8])
        #expect(viewModel.deletedChipCategoryIDs == [5])
        fakes.releaseSave()
        await saving.value
    }
}

// MARK: 입력 모두 지우기 · 통화 바꾸기

extension BudgetEditLinesTests {
    @Test("BDF.S2-R5 금액(전체만·카테고리 0원만·결제수단만)이 있으면 모두 지우기가 확인 창을 띄운다")
    func clearAllAvailableWithAnyAmount() {
        let edits: [(String, @MainActor (BudgetEditViewModel) -> Void)] = [
            ("전체", { $0.setDirectTotal(10000) }),
            ("카테고리 0원", { viewModel in
                viewModel.addCategory(1)
                viewModel.setCategoryAmount(0, for: 1)
            }),
            ("결제수단", { $0.setPaymentAmount(5000, for: .creditCard) })
        ]
        for (name, edit) in edits {
            let fakes = LinesFakes()
            fakes.initialBudget = makeNotSetBudget()
            let viewModel = fakes.makeViewModel()
            #expect(!viewModel.canClearAll, "\(name)")
            edit(viewModel)
            #expect(viewModel.canClearAll, "\(name)")
            viewModel.requestClearAll()
            #expect(viewModel.dialog == .clearAll, "\(name)")
        }
    }

    @Test("BDF.S2-R5 확인하면 전체·몫·결제수단을 비우고 줄을 모두 빼 칩으로 돌린다 — 이 달 응답의 삭제 번호는 칩에 없다")
    func confirmingClearAllEmptiesDraft() async {
        let fakes = LinesFakes()
        fakes.chipOrder = [1, 2, 5, 3]
        let viewModel = fakes.makeViewModel()
        viewModel.togglePaymentSection()
        viewModel.setPaymentAmount(100_000, for: .cashAndDebit)
        viewModel.requestClearAll()

        await viewModel.confirmDialog()

        #expect(viewModel.dialog == nil)
        #expect(viewModel.draft.directTotal == nil)
        #expect(viewModel.draft.total == nil)
        #expect(viewModel.draft.categoryLines.isEmpty)
        #expect(viewModel.draft.paymentAmounts.isEmpty)
        #expect(viewModel.chipCategoryIDs == [1, 2, 3])
        #expect(!viewModel.canClearAll)
    }

    @Test("BDF.S2-R5 짝: 취소하면 그대로, 금액이 없으면(빈 줄만 있어도) 창을 띄우지 않고, 쓰는 중에는 누를 수 없다")
    func clearAllBlockedWithoutAmountsOrWhileWriting() async {
        let fakes = LinesFakes()
        let viewModel = fakes.makeViewModel()
        let opened = viewModel.draft
        viewModel.requestClearAll()
        viewModel.cancelDialog()
        #expect(viewModel.dialog == nil)
        #expect(viewModel.draft == opened)

        let empty = LinesFakes()
        empty.initialBudget = makeNotSetBudget()
        let blank = empty.makeViewModel()
        blank.addCategory(1)
        #expect(!blank.canClearAll)
        blank.requestClearAll()
        #expect(blank.dialog == nil)
        #expect(blank.draft.categoryLines.map(\.categoryID) == [1])

        let saving = await fakes.startHeldSave(viewModel)
        #expect(!viewModel.canClearAll)
        viewModel.requestClearAll()
        #expect(viewModel.dialog == nil)
        fakes.releaseSave()
        await saving.value
    }

    @Test("BDF.S2-R6 통화 바꾸기는 그대로다 — 줄은 남기고 금액만 비운다")
    func changingCurrencyKeepsLines() async {
        let fakes = LinesFakes()
        let viewModel = fakes.makeViewModel()

        viewModel.selectCurrency(.usd)
        #expect(viewModel.dialog == .changeCurrency(.usd))
        await viewModel.confirmDialog()

        #expect(viewModel.draft.currency == .usd)
        #expect(viewModel.draft.categoryLines.map(\.categoryID) == [1, 5, 6, 8])
        #expect(viewModel.draft.categoryLines.allSatisfy { $0.amount == nil })
        #expect(viewModel.draft.directTotal == nil)
        #expect(viewModel.chipCategoryIDs == [2, 3, 4])
    }
}

// MARK: 나가기 판정

extension BudgetEditLinesTests {
    @Test("BDF.S2-R7 나가기 판정은 실제 전체로 본다 — 자동 합계와 같은 값을 쳐도 바뀐 입력이 아니다")
    func leaveCheckComparesActualTotal() {
        // 자동 합계 1,000.
        let automatic = LinesFakes()
        automatic.initialBudget = makeBudget(total: 1000, categories: [categoryLine(1, budget: 1000)])
        let auto = automatic.makeViewModel()
        #expect(auto.draft.isTotalAutomatic)
        auto.setDirectTotal(1000)
        #expect(auto.draft.directTotal == 1000)
        #expect(!auto.hasChanges)
        auto.setDirectTotal(1001)
        #expect(auto.hasChanges)

        // 직접 2,000.
        let direct = LinesFakes()
        direct.initialBudget = makeBudget(total: 2000, categories: [categoryLine(1, budget: 1000)])
        let typed = direct.makeViewModel()
        #expect(typed.draft.directTotal == 2000)
        typed.setDirectTotal(2000)
        #expect(!typed.hasChanges)
        typed.setDirectTotal(nil)
        #expect(typed.draft.total == 1000)
        #expect(typed.hasChanges)

        // 카테고리 금액 비교는 그대로.
        let categoryEdited = direct.makeViewModel()
        categoryEdited.setCategoryAmount(900, for: 1)
        #expect(categoryEdited.hasChanges)
    }

    @Test("BDF.S2-R7 짝: 불러오기 칩은 그대로 — 불러온 자동 합계와 같은 값을 직접 쳐도 꺼진다")
    func previousChipStillUsesDirectTotal() async {
        let fakes = LinesFakes()
        fakes.initialBudget = makeNotSetBudget()
        fakes.previous = makeBudget(yearMonth(2026, 9), total: 60000, categories: [categoryLine(2, budget: 60000)])
        let viewModel = fakes.makeViewModel()
        await viewModel.loadPrevious()
        #expect(viewModel.isPreviousApplied)
        #expect(viewModel.draft.isTotalAutomatic)

        viewModel.setDirectTotal(60000)

        #expect(viewModel.draft.total == 60000)
        #expect(!viewModel.isPreviousApplied)
    }
}

// MARK: 보통 칩의 삭제 판정

extension BudgetEditLinesTests {
    @Test("BDF.S2-R8 이 달 응답이 삭제로 표시한 번호는 기기 칩 순서에 있어도 보통 칩에 없다 — 줄을 빼도 삭제된 칩 한 곳에만")
    func normalChipsExcludeServerDeleted() {
        let fakes = LinesFakes()
        fakes.chipOrder = [1, 5, 2, 9, 6, 3]
        let viewModel = fakes.makeViewModel()
        // 9 는 몫 없이 쓴 돈만 있는 삭제된 카테고리 — 줄이 아니어도 칩이 아니다.
        #expect(viewModel.chipCategoryIDs == [2, 3])

        viewModel.removeCategory(5)
        #expect(viewModel.chipCategoryIDs == [2, 3])
        #expect(viewModel.deletedChipCategoryIDs == [5])

        // 쓴 돈 0 — 어느 칩에도 없다.
        viewModel.removeCategory(6)
        #expect(viewModel.chipCategoryIDs == [2, 3])
        #expect(viewModel.deletedChipCategoryIDs == [5])

        // 짝: 삭제 표시 없는 1 은 원래 자리로.
        viewModel.removeCategory(1)
        #expect(viewModel.chipCategoryIDs == [1, 2, 3])
    }

    @Test("BDF.S2-R8 칩 순서의 임시 번호도 서버 번호로 바꿔 삭제를 판정한다")
    func normalChipsResolveTemporaryIDs() {
        let fakes = LinesFakes()
        fakes.chipOrder = [-7, 1, 2]
        fakes.remap = [-7: 5]
        let viewModel = fakes.makeViewModel()

        viewModel.removeCategory(5)

        #expect(viewModel.chipCategoryIDs == [2])
        #expect(viewModel.deletedChipCategoryIDs == [5])
    }

    @Test("BDF.S2-R8 짝: 이 달 응답이 없는 미설정 달은 칩 순서 그대로다")
    func normalChipsUnchangedForUnsetMonth() {
        let fakes = LinesFakes()
        fakes.initialBudget = makeNotSetBudget()
        fakes.chipOrder = [1, 5, 2, 6]
        #expect(fakes.makeViewModel().chipCategoryIDs == [1, 5, 2, 6])
    }
}

// MARK: 삭제된 줄의 자리

extension BudgetEditLinesTests {
    @Test("BDF.S2-R10 이 달 응답이 삭제로 표시한 줄의 자리는 기기 칩 순서와 무관하다 — 열기는 응답 순서, 다시 넣기·칩 넣기는 맨 뒤")
    func deletedLineOrderIsDeviceIndependent() {
        // 삭제 도착 전(5 가 칩 순서 가운데) · 도착 뒤(5 없음) · 임시 번호 -7(서버 번호 5)이 칩 순서 가운데.
        let devices: [(chips: [Int], remap: [Int: Int])] = [
            ([1, 5, 3, 4], [:]), ([1, 3, 4], [:]), ([1, -7, 3, 4], [-7: 5])
        ]
        for (chips, remap) in devices {
            let viewModel = makeOrderFakes(chips: chips, remap: remap).makeViewModel()
            // 짝: 보통 줄도 칩 순서(1 → 3)가 아니라 응답 순서이고, 삭제된 줄은 응답 자리 그대로다(UI_GUIDE 2026-10-04).
            #expect(viewModel.draft.categoryLines.map(\.categoryID) == [3, 5, 1], "\(chips)")

            viewModel.removeCategory(5)
            viewModel.addDeletedCategory(5)
            #expect(viewModel.draft.categoryLines.map(\.categoryID) == [3, 1, 5], "\(chips)")
            #expect(viewModel.draft.categoryLines.last?.isDeleted == true, "\(chips)")

            viewModel.addCategory(4)
            #expect(viewModel.draft.categoryLines.map(\.categoryID) == [3, 1, 5, 4], "\(chips)")
        }
    }

    @Test("BDF.S2-R10 두 기기에서 같은 동작 뒤 나가기 판정이 같다 — 삭제된 줄을 빼고 같은 금액으로 다시 넣으면 바뀐 입력이 아니다")
    func leaveCheckIsDeviceIndependent() {
        for chips in [[1, 5, 3, 4], [1, 3, 4]] {
            let viewModel = makeOrderFakes(chips: chips).makeViewModel()
            viewModel.removeCategory(5)
            #expect(viewModel.hasChanges, "\(chips)")

            viewModel.addDeletedCategory(5)
            viewModel.setCategoryAmount(50000, for: 5)
            #expect(!viewModel.hasChanges, "\(chips)")
        }
    }

    /// 응답 순서 3(몫 70,000) · 5(삭제 · 몫 50,000 · 쓴 돈 12,000) · 1(몫 100,000), 자동 합계 220,000.
    private func makeOrderFakes(chips: [Int], remap: [Int: Int] = [:]) -> LinesFakes {
        let fakes = LinesFakes()
        fakes.initialBudget = makeBudget(total: 220_000, categories: [
            categoryLine(3, budget: 70000),
            categoryLine(5, budget: 50000, spent: 12000, isDeleted: true),
            categoryLine(1, budget: 100_000)
        ])
        fakes.chipOrder = chips
        fakes.remap = remap
        return fakes
    }
}

// MARK: 불러오기 칩

extension BudgetEditLinesTests {
    @Test("BDF.S2-R9 줄 빼기·삭제된 칩 넣기·모두 지우기도 불러오기 칩을 끈다")
    func lineEditsTurnOffPreviousChip() async {
        let edits: [(String, @MainActor (BudgetEditViewModel) async -> Void)] = [
            ("줄 빼기", { $0.removeCategory(2) }),
            ("삭제된 칩 넣기", { $0.addDeletedCategory(5) }),
            ("모두 지우기", { viewModel in
                viewModel.requestClearAll()
                await viewModel.confirmDialog()
            })
        ]
        for (name, edit) in edits {
            let (viewModel, _) = await makePreviousApplied()
            #expect(viewModel.deletedChipCategoryIDs == [5, 8], "\(name)")
            await edit(viewModel)
            #expect(!viewModel.isPreviousApplied, "\(name)")
        }
    }

    @Test("BDF.S2-R9 짝: 모두 지우기를 취소하거나 쓰는 중에 빼면(무시) 불러오기 칩은 켜진 채다")
    func previousChipKeptWhenNothingChanges() async {
        let (cancelled, _) = await makePreviousApplied()
        cancelled.requestClearAll()
        cancelled.cancelDialog()
        #expect(cancelled.isPreviousApplied)

        let (writing, fakes) = await makePreviousApplied()
        let saving = await fakes.startHeldSave(writing)
        writing.removeCategory(2)
        #expect(writing.isPreviousApplied)
        #expect(writing.draft.categoryLines.map(\.categoryID) == [2])
        fakes.releaseSave()
        await saving.value
    }

    /// 기본 응답의 달에서 지난 달(전체 90,000 · 카테고리 2 몫 60,000)을 불러와 칩이 켜진 편집 화면.
    private func makePreviousApplied() async -> (BudgetEditViewModel, LinesFakes) {
        let fakes = LinesFakes()
        fakes.previous = makeBudget(yearMonth(2026, 9), total: 90000, categories: [categoryLine(2, budget: 60000)])
        let viewModel = fakes.makeViewModel()
        await viewModel.loadPrevious()
        await viewModel.confirmDialog()
        #expect(viewModel.isPreviousApplied)
        return (viewModel, fakes)
    }
}

// MARK: 가짜 입력

private enum LinesTestError: Error {
    case noBudget
}

/// 편집 화면 조립. 지난 달 읽기는 `previous` 를 돌려주고(없으면 실패), 저장은 `startHeldSave` 로 붙잡을 수 있다.
@MainActor
private final class LinesFakes {
    var initialBudget: MonthlyBudget?
    /// nil = 신원 없는 비회원.
    var lastMonth: ServerMonth?
    var chipOrder = [1, 2, 3, 4]
    /// 서버 번호를 받은 임시 번호.
    var remap: [Int: Int] = [:]
    var previous: MonthlyBudget?
    private var holdsSave = false
    private var heldSave: CheckedContinuation<Void, Never>?

    init() {
        initialBudget = makeBudget(total: 500_000, categories: [
            categoryLine(1, budget: 100_000, spent: 30000),
            categoryLine(5, budget: 50000, spent: 12000, isDeleted: true),
            categoryLine(6, budget: 20000, isDeleted: true),
            categoryLine(8, budget: 30000, spent: 7000, isDeleted: true),
            categoryLine(9, budget: nil, spent: 4000, isDeleted: true)
        ])
        lastMonth = yearMonth(2027, 10)
    }

    func makeViewModel() -> BudgetEditViewModel {
        BudgetEditViewModel(
            context: BudgetEditViewModel.Context(
                month: yearMonth(2026, 10),
                lastMonth: lastMonth,
                initialBudget: initialBudget
            ),
            chipOrder: { self.chipOrder },
            baseCurrency: .krw,
            fetch: { _, _ in
                guard let previous = self.previous else {
                    throw LinesTestError.noBudget
                }
                return previous
            },
            save: { year, month, _ in
                await self.passSave()
                return makeBudget(yearMonth(year, month), total: 500_000)
            },
            delete: { year, month in makeNotSetBudget(yearMonth(year, month)) },
            hasIdentity: { true },
            ensureIdentity: {},
            flushPendingCategories: {},
            resolvedCategoryID: { self.remap[$0] ?? $0 },
            refreshCategories: {},
            beginWrite: { 1 },
            onFinish: { _ in }
        )
    }

    /// 저장을 붙잡아 쓰는 중으로 만든다. 돌려준 작업은 `releaseSave()` 뒤에 기다린다.
    func startHeldSave(_ viewModel: BudgetEditViewModel) async -> Task<Void, Never> {
        holdsSave = true
        let saving = Task { await viewModel.save() }
        await waitUntil { self.heldSave != nil }
        #expect(viewModel.isWriting)
        return saving
    }

    func releaseSave() {
        holdsSave = false
        heldSave?.resume()
        heldSave = nil
    }

    private func passSave() async {
        guard holdsSave else {
            return
        }
        await withCheckedContinuation { heldSave = $0 }
    }
}

// MARK: 응답 픽스처

@MainActor
private func yearMonth(_ year: Int, _ month: Int) -> ServerMonth {
    ServerMonth(year: year, month: month)
}

private func category(_ id: Int) -> woni_app.Category {
    Category(id: id, code: "FOOD", displayNameKo: "식비", displayNameEn: "Food", icon: "🍽️", sortOrder: id)
}

/// `BudgetEditLineLabel` 은 비교할 수 없어 꺼내 본다.
private func isDeletedLabel(_ label: BudgetEditLineLabel?) -> Bool {
    guard case .deleted? = label else {
        return false
    }
    return true
}

/// 계약 모양의 줄. 몫이 없으면 사용액만, 몫이 있으면 쓴 돈 0 은 NONE · 그 밖은 IN_PROGRESS(픽스처는 몫을 넘지 않는다).
private func budgetLine(budget: Decimal?, spent: Decimal) -> BudgetLine {
    guard let budget else {
        return BudgetLine(
            budgetAmount: nil,
            actualAmount: spent,
            status: nil,
            percent: nil,
            remainingAmount: nil,
            overAmount: nil
        )
    }
    return BudgetLine(
        budgetAmount: budget,
        actualAmount: spent,
        status: spent == 0 ? BudgetStatus.none : .inProgress,
        percent: budget == 0 ? nil : NSDecimalNumber(decimal: spent * 100 / budget).intValue,
        remainingAmount: budget - spent,
        overAmount: nil
    )
}

private func categoryLine(
    _ id: Int,
    budget: Decimal?,
    spent: Decimal = 0,
    isDeleted: Bool = false
) -> BudgetCategoryLine {
    BudgetCategoryLine(category: category(id), isDeleted: isDeleted, line: budgetLine(budget: budget, spent: spent))
}

/// 예산이 있는 달(nil = 2026-10). 전체 쓴 돈 = 카테고리 쓴 돈 합, 결제수단은 몫이 없다.
/// 그 외 카테고리 몫 = 전체 − 카테고리 몫 합, 0 이면 쓴 돈만 — 서버 규칙 그대로.
@MainActor
private func makeBudget(
    _ month: ServerMonth? = nil,
    total: Decimal,
    categories: [BudgetCategoryLine] = []
) -> MonthlyBudget {
    let month = month ?? yearMonth(2026, 10)
    let shares = categories.compactMap(\.line.budgetAmount).reduce(0, +)
    let spent = categories.map(\.line.actualAmount).reduce(0, +)
    let groups: [PaymentGroup] = [.creditCard, .cashAndDebit, .accountAndOther]
    let budget = MonthlyBudget(
        year: month.year,
        month: month.month,
        currentYear: 2026,
        currentMonth: 10,
        remainingDaysIncludingToday: month == yearMonth(2026, 10) ? 7 : nil,
        hasAnyBudget: true,
        status: spent == 0 ? BudgetStatus.none : .inProgress,
        currency: .krw,
        total: budgetLine(budget: total, spent: spent),
        paymentGroups: groups.map { BudgetPaymentGroupLine(paymentGroup: $0, line: budgetLine(budget: nil, spent: 0)) },
        categories: categories,
        otherCategories: budgetLine(budget: total > shares ? total - shares : nil, spent: 0),
        missingRateCount: 0,
        dailyAllowance: nil
    )
    #expect(BudgetTabViewModel.isWellFormed(budget))
    return budget
}

/// 미설정 달(nil = 2026-10) — 계약상 통화·전체·그 외 카테고리가 nil 이고 결제수단·카테고리는 [] 이다.
@MainActor
private func makeNotSetBudget(_ month: ServerMonth? = nil) -> MonthlyBudget {
    let month = month ?? yearMonth(2026, 10)
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
