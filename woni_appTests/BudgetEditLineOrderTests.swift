//
//  BudgetEditLineOrderTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 편집 금액 줄의 순서(UI_GUIDE 2026-10-04 "금액 줄은 누른 순서대로 아래에 쌓인다"). 줄은 열 때·불러올 때 서버
/// 응답 순서이고 그 뒤로는 누른 순서로 맨 뒤에 붙는다 — 기기 칩 순서로 다시 세우지 않는다.
/// 칩 순서는 일부러 누른 순서·응답 순서와 다르게 둔다. 같으면 칩 순서로 세우는 옛 코드도 통과한다.
/// 따로 적지 않으면 회원이 2026-10 을 연다.
@MainActor
struct BudgetEditLineOrderTests {
    @Test("BDF2.S0-R1 칩으로 넣은 줄은 누른 순서로 맨 뒤에 붙는다 — 칩 순서가 3 → 4 여도 4 → 3 으로 누르면 4 · 3 순이다")
    func chipLinesStackInTapOrder() {
        let fakes = LineOrderFakes(initialBudget: twoLineBudget(), chipOrder: [3, 1, 2, 4])
        let viewModel = fakes.makeViewModel()
        #expect(ids(viewModel) == [1, 2])

        viewModel.addCategory(4)
        viewModel.addCategory(3)

        #expect(ids(viewModel) == [1, 2, 4, 3])
        #expect(viewModel.draft.categoryLines.map(\.amount) == [100_000, 200_000, nil, nil])
        #expect(viewModel.chipCategoryIDs.isEmpty)
    }

    @Test("BDF2.S0-R1 짝: 칩 순서 자리([3, 1, 2, 4])에 끼우지 않고, 이미 줄이 있는 번호를 누르면 줄·자리·금액이 그대로다")
    func chipLinesIgnoreChipOrderAndDuplicates() {
        let fakes = LineOrderFakes(initialBudget: twoLineBudget(), chipOrder: [3, 1, 2, 4])
        let viewModel = fakes.makeViewModel()
        viewModel.addCategory(4)
        viewModel.addCategory(3)
        #expect(ids(viewModel) != [3, 1, 2, 4])

        viewModel.setCategoryAmount(45000, for: 4)
        viewModel.addCategory(4)
        viewModel.addCategory(1)

        #expect(ids(viewModel) == [1, 2, 4, 3])
        #expect(viewModel.draft.categoryLines.map(\.amount) == [100_000, 200_000, 45000, nil])
    }

    @Test("BDF2.S0-R1 초안: 줄 [1, 2] 에 4 → 3 을 넣으면 [1, 2, 4, 3] 이다 — 칩 묶음은 기기 칩 순서 그대로다")
    func draftAppendsInTapOrder() {
        var draft = BudgetEditDraft(currency: .krw, categoryLines: [line(1, 100_000), line(2, 200_000)])

        draft.addCategory(4)
        draft.addCategory(3)

        #expect(draft.categoryLines.map(\.categoryID) == [1, 2, 4, 3])
        #expect(draft.categoryLines.map(\.amount) == [100_000, 200_000, nil, nil])
        #expect(draft.chipCategoryIDs(chipOrder: [5, 3, 1, 2, 4, 6]) == [5, 6])
    }
}

// MARK: R2 삭제된 줄 다시 넣기

extension BudgetEditLineOrderTests {
    @Test("BDF2.S0-R2 삭제된 칩으로 다시 넣은 줄도 누른 순서로 맨 뒤다 — 8 을 다시 넣고 3 을 누르면 8 · 3 순이다")
    func deletedLineReinsertedAtEnd() {
        let fakes = LineOrderFakes(initialBudget: deletedLineBudget(), chipOrder: [3, 1, 2, 4])
        let viewModel = fakes.makeViewModel()
        #expect(ids(viewModel) == [1, 2, 8])
        viewModel.removeCategory(8)
        #expect(viewModel.deletedChipCategoryIDs == [8])

        viewModel.addDeletedCategory(8)
        viewModel.addCategory(3)

        #expect(ids(viewModel) == [1, 2, 8, 3])
        // 옛 규칙(보통 줄 뒤에 삭제된 줄)이 아니다.
        #expect(ids(viewModel) != [1, 2, 3, 8])
        #expect(viewModel.draft.categoryLines[2] == BudgetEditCategoryLine(categoryID: 8, isDeleted: true, amount: nil))
        #expect(viewModel.deletedChipCategoryIDs.isEmpty)
    }

    @Test("BDF2.S0-R2 짝: 3 을 먼저 누르고 8 을 다시 넣으면 3 · 8 순이고, 삭제된 칩에 없는 번호(목록에 없음)는 넣지 않는다")
    func deletedLineFollowsTapOrderOnly() {
        // 6 은 삭제 · 그 달 거래가 없어 목록에 없다 — 빼도 삭제된 칩이 생기지 않는다.
        let fakes = LineOrderFakes(
            initialBudget: BudgetEditTestFixture.makeBudget(
                total: 360_000,
                categories: [
                    BudgetEditTestFixture.categoryLine(1, budget: 100_000),
                    BudgetEditTestFixture.categoryLine(2, budget: 200_000),
                    BudgetEditTestFixture.categoryLine(8, budget: 30000, spent: 7000, isDeleted: true),
                    BudgetEditTestFixture.categoryLine(6, budget: 30000, isDeleted: true)
                ],
                deletedWithSpending: [BudgetEditTestFixture.category(8)]
            ),
            chipOrder: [4, 3, 2, 1]
        )
        let viewModel = fakes.makeViewModel()
        viewModel.removeCategory(8)
        viewModel.removeCategory(6)

        viewModel.addCategory(3)
        viewModel.addDeletedCategory(8)
        viewModel.addDeletedCategory(6)

        #expect(ids(viewModel) == [1, 2, 3, 8])
        #expect(viewModel.draft.categoryLines.map(\.isDeleted) == [false, false, false, true])
    }

    @Test("BDF2.S0-R2 초안: 삭제된 줄로 다시 넣어도 맨 뒤에 붙고 삭제 표시를 지닌다")
    func draftAppendsDeletedLineAtEnd() {
        var draft = BudgetEditDraft(currency: .krw, categoryLines: [line(1, 100_000), line(2, 200_000)])

        draft.addCategory(8, isDeleted: true)
        draft.addCategory(3)

        #expect(draft.categoryLines.map(\.categoryID) == [1, 2, 8, 3])
        #expect(draft.categoryLines.map(\.isDeleted) == [false, false, true, false])
    }
}

// MARK: R3 열기

extension BudgetEditLineOrderTests {
    @Test("BDF2.S0-R3 처음 열 때·달을 옮겨 열 때 줄은 응답 순서 그대로다 — 삭제된 줄 자리도 응답 그대로")
    func openingKeepsResponseOrder() async {
        let fakes = LineOrderFakes(initialBudget: responseOrderBudget(), chipOrder: [1, 3, 5])
        fakes.responses = [BudgetEditTestFixture.makeBudget(
            BudgetEditTestFixture.yearMonth(2026, 11),
            total: 400_000,
            categories: [
                BudgetEditTestFixture.categoryLine(3, budget: 70000),
                BudgetEditTestFixture.categoryLine(9, budget: 30000, spent: 6000, isDeleted: true),
                BudgetEditTestFixture.categoryLine(1, budget: 300_000)
            ]
        )]
        let viewModel = fakes.makeViewModel()

        #expect(ids(viewModel) == [5, 9, 1])
        #expect(viewModel.draft.categoryLines.map(\.isDeleted) == [false, true, false])
        #expect(viewModel.draft.categoryLines.map(\.amount) == [100_000, 50000, 300_000])
        // 칩 순서([1, 5, 9])도, 삭제된 줄을 뒤로 몬 순서([5, 1, 9])도 아니다.
        #expect(ids(viewModel) != [1, 5, 9])
        #expect(ids(viewModel) != [5, 1, 9])
        #expect(viewModel.chipCategoryIDs == [3])

        await viewModel.go(by: 1)

        #expect(viewModel.phase == .editing)
        #expect(ids(viewModel) == [3, 9, 1])
        #expect(viewModel.draft.categoryLines.map(\.amount) == [70000, 30000, 300_000])
    }

    @Test("BDF2.S0-R3 짝: 몫 없는 응답 줄은 줄이 아니다 — 남은 줄은 응답 순서 그대로다")
    func openingSkipsUnbudgetedResponseLines() {
        let fakes = LineOrderFakes(
            initialBudget: BudgetEditTestFixture.makeBudget(total: 120_000, categories: [
                BudgetEditTestFixture.categoryLine(9, budget: 40000, spent: 2000, isDeleted: true),
                BudgetEditTestFixture.categoryLine(4, budget: nil, spent: 3000, isDeleted: true),
                BudgetEditTestFixture.categoryLine(1, budget: 60000),
                BudgetEditTestFixture.categoryLine(5, budget: 20000)
            ]),
            chipOrder: [1, 3, 5]
        )
        let viewModel = fakes.makeViewModel()

        #expect(ids(viewModel) == [9, 1, 5])
        #expect(!ids(viewModel).contains(4))
        #expect(viewModel.draft.categoryLines.map(\.amount) == [40000, 60000, 20000])
    }

    @Test("BDF2.S0-R3 초안: 응답 [5, 9(삭제), 1] 로 열면 줄도 [5, 9, 1] 이다 — 칩 묶음은 기기 칩 순서 그대로다")
    func draftOpensInResponseOrder() {
        let draft = BudgetEditDraft(budget: responseOrderBudget(), baseCurrency: .krw)

        #expect(draft.categoryLines.map(\.categoryID) == [5, 9, 1])
        #expect(draft.categoryLines.map(\.isDeleted) == [false, true, false])
        #expect(draft.chipCategoryIDs(chipOrder: [1, 3, 5, 7]) == [3, 7])
    }
}

// MARK: R4 지난 달 불러오기

extension BudgetEditLineOrderTests {
    @Test("BDF2.S0-R4 지난 달을 불러오면 줄은 지난 달 응답 순서다 — 삭제된 줄만 빼고 칩 순서로 다시 세우지 않는다")
    func previousKeepsResponseOrder() async {
        let fakes = LineOrderFakes(initialBudget: BudgetEditTestFixture.makeNotSetBudget(), chipOrder: [1, 2])
        fakes.responses = [BudgetEditTestFixture.makeBudget(
            BudgetEditTestFixture.yearMonth(2026, 9),
            total: 100_000,
            categories: [
                BudgetEditTestFixture.categoryLine(2, budget: 60000),
                BudgetEditTestFixture.categoryLine(9, budget: 10000, isDeleted: true),
                BudgetEditTestFixture.categoryLine(1, budget: 30000)
            ]
        )]
        let viewModel = fakes.makeViewModel()

        await viewModel.loadPrevious()

        #expect(viewModel.isPreviousApplied)
        #expect(ids(viewModel) == [2, 1])
        #expect(ids(viewModel) != [1, 2])
        #expect(viewModel.draft.categoryLines.map(\.amount) == [60000, 30000])
        #expect(viewModel.toast == .droppedDeletedCategories(1))
    }

    @Test("BDF2.S0-R4 짝: 빠진 수는 몫이 있던 삭제 줄만 센다 — 몫 없는 삭제 줄은 세지 않고 남은 줄의 상대 순서는 그대로다")
    func previousCountsOnlyBudgetedDeletedLines() async {
        let fakes = LineOrderFakes(initialBudget: BudgetEditTestFixture.makeNotSetBudget(), chipOrder: [1, 2, 3])
        fakes.responses = [BudgetEditTestFixture.makeBudget(
            BudgetEditTestFixture.yearMonth(2026, 9),
            total: 80000,
            categories: [
                BudgetEditTestFixture.categoryLine(3, budget: 40000),
                BudgetEditTestFixture.categoryLine(7, budget: nil, spent: 1000, isDeleted: true),
                BudgetEditTestFixture.categoryLine(9, budget: 5000, isDeleted: true),
                BudgetEditTestFixture.categoryLine(1, budget: 20000),
                BudgetEditTestFixture.categoryLine(2, budget: 10000)
            ]
        )]
        let viewModel = fakes.makeViewModel()

        await viewModel.loadPrevious()

        #expect(ids(viewModel) == [3, 1, 2])
        #expect(viewModel.toast == .droppedDeletedCategories(1))
    }

    @Test("BDF2.S0-R4 초안: 지난 달 [2, 9(삭제), 1] 을 불러오면 줄은 [2, 1] 이고 빠진 수 1 을 돌려준다")
    func draftAppliesPreviousInResponseOrder() {
        var draft = BudgetEditDraft(emptyWith: .krw)

        let dropped = draft.applyPrevious(BudgetEditTestFixture.makeBudget(
            BudgetEditTestFixture.yearMonth(2026, 9),
            total: 100_000,
            categories: [
                BudgetEditTestFixture.categoryLine(2, budget: 60000),
                BudgetEditTestFixture.categoryLine(9, budget: 10000, isDeleted: true),
                BudgetEditTestFixture.categoryLine(1, budget: 30000)
            ]
        ))

        #expect(dropped == 1)
        #expect(draft.categoryLines.map(\.categoryID) == [2, 1])
        #expect(draft.categoryLines.map(\.amount) == [60000, 30000])
    }
}

// MARK: R5 나가기 판정

extension BudgetEditLineOrderTests {
    @Test("BDF2.S0-R5 줄과 금액이 같고 순서만 바뀌면 바뀐 입력이 아니다 — 닫기·달 옮기기가 묻지 않고, 저장은 새 순서로 보낸다")
    func reorderOnlyIsNotUnsavedChange() async {
        let closing = LineOrderFakes(initialBudget: reorderBudget(), chipOrder: [1, 2, 3])
        let closed = closing.makeViewModel()
        reorder(closed)
        #expect(ids(closed) == [2, 1])
        #expect(!closed.hasChanges)
        closed.requestClose()
        #expect(closed.dialog == nil)
        #expect(closing.dismissedCount == 1)

        let moving = LineOrderFakes(initialBudget: reorderBudget(), chipOrder: [1, 2, 3])
        let moved = moving.makeViewModel()
        reorder(moved)
        await moved.go(by: 1)
        #expect(moved.dialog == nil)
        #expect(moved.month == BudgetEditTestFixture.yearMonth(2026, 11))

        let saving = LineOrderFakes(initialBudget: reorderBudget(), chipOrder: [1, 2, 3])
        let saved = saving.makeViewModel()
        reorder(saved)
        await saved.save()
        #expect(saving.saveRequests.last?.categoryAmounts.map(\.categoryId) == [2, 1])
        #expect(saving.saveRequests.last?.categoryAmounts.map(\.amount) == [200, 100])
    }

    @Test("BDF2.S0-R5 짝: 금액이 하나 다르거나 줄이 하나 더·덜하면 바뀐 입력이다 — 닫기·달 옮기기가 나갈지 묻는다")
    func lineOrAmountChangeIsUnsavedChange() async {
        let edits: [(String, @MainActor (BudgetEditViewModel) -> Void)] = [
            ("금액", { viewModel in
                reorder(viewModel)
                viewModel.setCategoryAmount(101, for: 1)
            }),
            ("줄 더", { viewModel in
                reorder(viewModel)
                viewModel.addCategory(3)
            }),
            ("줄 덜", { $0.removeCategory(2) })
        ]
        for (name, edit) in edits {
            let fakes = LineOrderFakes(initialBudget: reorderBudget(), chipOrder: [1, 2, 3])
            let viewModel = fakes.makeViewModel()
            edit(viewModel)
            #expect(viewModel.hasChanges, "\(name)")

            viewModel.requestClose()
            #expect(viewModel.dialog == .leave, "\(name)")
            #expect(fakes.dismissedCount == 0, "\(name)")
            viewModel.cancelDialog()

            await viewModel.go(by: 1)
            #expect(viewModel.dialog == .leave, "\(name)")
            #expect(viewModel.month == BudgetEditTestFixture.yearMonth(2026, 10), "\(name)")
        }
    }

    @Test("BDF2.S0-R5 초안: 같은 번호끼리 삭제 표시·금액이 같고 줄 집합이 같으면 순서가 달라도 바뀐 입력이 아니다")
    func draftIgnoresLineOrder() {
        let baseline = BudgetEditDraft(
            currency: .krw,
            categoryLines: [line(1, 100), line(2, 200), deletedLine(9, 50)]
        )
        let reordered = BudgetEditDraft(
            currency: .krw,
            categoryLines: [deletedLine(9, 50), line(2, 200), line(1, 100)]
        )

        #expect(!reordered.hasUnsavedChanges(from: baseline))
    }

    @Test("BDF2.S0-R5 초안 짝: 금액·삭제 표시가 다르거나 줄이 더·덜하면 순서와 상관없이 바뀐 입력이다")
    func draftDetectsLineDifferences() {
        let baseline = BudgetEditDraft(currency: .krw, categoryLines: [line(1, 100), line(2, 200)])
        let variants: [(String, [BudgetEditCategoryLine])] = [
            ("금액", [line(2, 200), line(1, 101)]),
            ("빈칸", [line(2, 200), line(1, nil)]),
            ("삭제 표시", [line(2, 200), deletedLine(1, 100)]),
            ("줄 더", [line(2, 200), line(1, 100), line(3, nil)]),
            ("줄 덜", [line(2, 200)])
        ]
        for (name, lines) in variants {
            let draft = BudgetEditDraft(currency: .krw, categoryLines: lines)
            #expect(draft.hasUnsavedChanges(from: baseline), "\(name)")
        }
    }
}

// MARK: R6 기기 간 같음

extension BudgetEditLineOrderTests {
    @Test("BDF2.S0-R6 같은 응답·같은 누름이면 칩 순서가 다른 기기(임시 번호 섞임 포함)의 줄 번호가 모두 같다")
    func lineOrderIsDeviceIndependent() async {
        var runs: [DeviceRun] = []
        for chips in Self.devices {
            await runs.append(runDevice(chips: chips))
        }

        #expect(runs.map(\.opened) == Array(repeating: [3, 9, 1], count: Self.devices.count))
        #expect(runs.map(\.edited) == Array(repeating: [3, 1, 4, 2, 9], count: Self.devices.count))
        #expect(runs.map(\.loaded) == Array(repeating: [2, 1, 3], count: Self.devices.count))
    }

    @Test("BDF2.S0-R6 짝: 칩 묶음은 기기 칩 순서를 따른다 — 같은 동작 뒤에도 기기마다 다르다")
    func chipBundleStillFollowsDeviceChipOrder() async {
        var runs: [DeviceRun] = []
        for chips in Self.devices {
            await runs.append(runDevice(chips: chips))
        }

        #expect(runs.map(\.chips) == [[5, 6], [6, 5], [-7, 6, 5]])
    }

    /// 칩 순서가 다른 세 기기 — 셋째는 아직 서버에 없는 내 카테고리(임시 번호 -7)가 가운데 있다.
    private static let devices: [[Int]] = [[1, 2, 3, 4, 5, 6], [6, 5, 4, 3, 2, 1], [2, -7, 6, 4, 1, 5, 3]]

    private struct DeviceRun {
        let opened: [Int]
        let edited: [Int]
        let chips: [Int]
        let loaded: [Int]
    }

    /// 응답 3 · 9(삭제 · 쓴 돈 12,000) · 1(목록 [9])로 열고 4 → 2 를 누른 뒤 9 를 빼고 다시 넣는다. 따로 미설정 달에서
    /// 지난 달 2 · 9(삭제) · 1 · 3 을 불러온다.
    private func runDevice(chips: [Int]) async -> DeviceRun {
        let fakes = LineOrderFakes(
            initialBudget: BudgetEditTestFixture.makeBudget(
                total: 220_000,
                categories: [
                    BudgetEditTestFixture.categoryLine(3, budget: 70000),
                    BudgetEditTestFixture.categoryLine(9, budget: 50000, spent: 12000, isDeleted: true),
                    BudgetEditTestFixture.categoryLine(1, budget: 100_000)
                ],
                deletedWithSpending: [BudgetEditTestFixture.category(9)]
            ),
            chipOrder: chips
        )
        let viewModel = fakes.makeViewModel()
        let opened = ids(viewModel)
        viewModel.addCategory(4)
        viewModel.addCategory(2)
        viewModel.removeCategory(9)
        viewModel.addDeletedCategory(9)

        let unset = LineOrderFakes(initialBudget: BudgetEditTestFixture.makeNotSetBudget(), chipOrder: chips)
        unset.responses = [BudgetEditTestFixture.makeBudget(
            BudgetEditTestFixture.yearMonth(2026, 9),
            total: 160_000,
            categories: [
                BudgetEditTestFixture.categoryLine(2, budget: 40000),
                BudgetEditTestFixture.categoryLine(9, budget: 20000, isDeleted: true),
                BudgetEditTestFixture.categoryLine(1, budget: 60000),
                BudgetEditTestFixture.categoryLine(3, budget: 40000)
            ]
        )]
        let loading = unset.makeViewModel()
        await loading.loadPrevious()

        return DeviceRun(opened: opened, edited: ids(viewModel), chips: viewModel.chipCategoryIDs, loaded: ids(loading))
    }
}

// MARK: 도우미

@MainActor
private func ids(_ viewModel: BudgetEditViewModel) -> [Int] {
    viewModel.draft.categoryLines.map(\.categoryID)
}

/// 기준 [1: 100, 2: 200] 에서 1 을 X 로 빼고 칩 1 을 다시 눌러 100 을 적는다 — 줄과 금액은 같고 순서만 [2, 1] 이다.
@MainActor
private func reorder(_ viewModel: BudgetEditViewModel) {
    viewModel.removeCategory(1)
    viewModel.addCategory(1)
    viewModel.setCategoryAmount(100, for: 1)
}

private func line(_ id: Int, _ amount: Decimal?) -> BudgetEditCategoryLine {
    BudgetEditCategoryLine(categoryID: id, isDeleted: false, amount: amount)
}

private func deletedLine(_ id: Int, _ amount: Decimal?) -> BudgetEditCategoryLine {
    BudgetEditCategoryLine(categoryID: id, isDeleted: true, amount: amount)
}

/// 줄 1(100,000) · 2(200,000), 자동 합계.
@MainActor
private func twoLineBudget() -> MonthlyBudget {
    BudgetEditTestFixture.makeBudget(total: 300_000, categories: [
        BudgetEditTestFixture.categoryLine(1, budget: 100_000),
        BudgetEditTestFixture.categoryLine(2, budget: 200_000)
    ])
}

/// 줄 1 · 2 · 8(삭제 · 쓴 돈 7,000), 목록 [8]. 8 을 빼면 삭제된 칩이 생긴다.
@MainActor
private func deletedLineBudget() -> MonthlyBudget {
    BudgetEditTestFixture.makeBudget(
        total: 330_000,
        categories: [
            BudgetEditTestFixture.categoryLine(1, budget: 100_000),
            BudgetEditTestFixture.categoryLine(2, budget: 200_000),
            BudgetEditTestFixture.categoryLine(8, budget: 30000, spent: 7000, isDeleted: true)
        ],
        deletedWithSpending: [BudgetEditTestFixture.category(8)]
    )
}

/// 응답 순서 5 · 9(삭제) · 1.
@MainActor
private func responseOrderBudget() -> MonthlyBudget {
    BudgetEditTestFixture.makeBudget(total: 450_000, categories: [
        BudgetEditTestFixture.categoryLine(5, budget: 100_000),
        BudgetEditTestFixture.categoryLine(9, budget: 50000, spent: 5000, isDeleted: true),
        BudgetEditTestFixture.categoryLine(1, budget: 300_000)
    ])
}

/// 기준 [1: 100, 2: 200], 자동 합계 300.
@MainActor
private func reorderBudget() -> MonthlyBudget {
    BudgetEditTestFixture.makeBudget(total: 300, categories: [
        BudgetEditTestFixture.categoryLine(1, budget: 100),
        BudgetEditTestFixture.categoryLine(2, budget: 200)
    ])
}

// MARK: 가짜 입력

/// 편집 화면 조립. 달 읽기(달 옮기기·지난 달 불러오기)는 `responses` 에서 그 달 응답을 찾고, 없으면 미설정 달이다.
@MainActor
private final class LineOrderFakes {
    let initialBudget: MonthlyBudget
    let chipOrder: [Int]
    var responses: [MonthlyBudget] = []
    private(set) var saveRequests: [SaveBudgetRequest] = []
    private(set) var outcomes: [BudgetEditOutcome] = []

    init(initialBudget: MonthlyBudget, chipOrder: [Int]) {
        self.initialBudget = initialBudget
        self.chipOrder = chipOrder
    }

    var dismissedCount: Int {
        outcomes.filter {
            guard case .dismissed = $0 else {
                return false
            }
            return true
        }.count
    }

    func makeViewModel() -> BudgetEditViewModel {
        BudgetEditViewModel(
            context: BudgetEditViewModel.Context(
                month: BudgetEditTestFixture.yearMonth(2026, 10),
                lastMonth: BudgetEditTestFixture.yearMonth(2027, 10),
                initialBudget: initialBudget
            ),
            chipOrder: { self.chipOrder },
            baseCurrency: .krw,
            fetch: { year, month in
                self.responses.first { $0.year == year && $0.month == month }
                    ?? BudgetEditTestFixture.makeNotSetBudget(BudgetEditTestFixture.yearMonth(year, month))
            },
            save: { year, month, request in
                self.saveRequests.append(request)
                return BudgetEditTestFixture.makeBudget(
                    BudgetEditTestFixture.yearMonth(year, month),
                    total: request.totalAmount
                )
            },
            delete: { year, month in
                BudgetEditTestFixture.makeNotSetBudget(BudgetEditTestFixture.yearMonth(year, month))
            },
            hasIdentity: { true },
            ensureIdentity: {},
            flushPendingCategories: {},
            resolvedCategoryID: { $0 },
            refreshCategories: {},
            beginWrite: { 1 },
            onFinish: { self.outcomes.append($0) }
        )
    }
}
