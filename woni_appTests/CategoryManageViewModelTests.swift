//
//  CategoryManageViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct CategoryManageViewModelTests {
    @Test("관리 목록은 커스텀만 노출하고 기본은 표시하지 않는다")
    func rowsExposeOnlyCustomCategories() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")]
        )

        let rows = harness.viewModel.rows

        #expect(rows.map(\.id) == [900])
        #expect(rows.first?.category.displayNameKo == "🏋️ 헬스장")
    }

    @Test("탭 전환은 해당 타입 커스텀 목록으로 바뀌고, 삭제 진행 중에는 무시된다")
    func selectTabSwitchesListAndIsIgnoredWhileDeleting() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [
                CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장"),
                CachedCustomCategory(id: 910, transactionType: .income, name: "💰 용돈")
            ],
            gateDelete: true
        )

        harness.viewModel.selectTab(.income)
        #expect(harness.viewModel.tab == .income)
        #expect(harness.viewModel.rows.map(\.id) == [910])

        harness.viewModel.selectTab(.expense)
        let category = try #require(harness.viewModel.rows.first?.category)
        harness.viewModel.requestDelete(category)
        let deletion = Task { await harness.viewModel.confirmDelete() }
        await waitUntil { harness.cache.removeStarted }

        harness.viewModel.selectTab(.income)
        #expect(harness.viewModel.tab == .expense)

        harness.cache.releaseRemove()
        _ = await deletion.value
    }

    @Test("커스텀 0개는 빈 상태로, refresh 실패는 오류 상태로 구분 표시한다")
    func emptyStateAndLoadErrorAreDistinguished() async throws {
        let harness = try await makeManageHarness(fetchError: ManageTestError.requestFailed)

        #expect(harness.viewModel.showsEmptyState)
        #expect(!harness.viewModel.showsLoadError)

        await harness.store.refresh()

        #expect(harness.viewModel.showsLoadError)
        #expect(!harness.viewModel.showsEmptyState)

        // 재시도 성공 → 오류 상태를 벗어나 서버 목록으로 수렴한다.
        harness.service.fetchError = nil
        harness.service.expense = [categoryDTO(id: 901, name: "🐶 반려동물")]
        await harness.viewModel.retryRefresh()

        #expect(!harness.viewModel.showsLoadError)
        #expect(!harness.viewModel.showsEmptyState)
        #expect(harness.viewModel.rows.last?.id == 901)
    }

    @Test("커스텀이 남아 있으면 refresh 실패여도 빈 상태·오류 상태를 띄우지 않는다")
    func populatedListSuppressesEmptyAndErrorStates() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")],
            fetchError: ManageTestError.requestFailed
        )

        await harness.store.refresh()

        #expect(harness.store.lastRefreshError != nil)
        #expect(!harness.viewModel.showsEmptyState)
        #expect(!harness.viewModel.showsLoadError)
    }

    @Test("삭제는 연결 상태 확인이나 push 없이 로컬에서 즉시 반영한다")
    func deleteCommitsLocallyWithoutConnectivityOrPushGate() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")]
        )
        let category = try #require(harness.store.expenseCategories.first)

        harness.viewModel.requestDelete(category)
        let outcome = await harness.viewModel.confirmDelete()

        #expect(outcome == .success)
        #expect(harness.service.deletedIDs.isEmpty)
        #expect(harness.store.expenseCategories.isEmpty)
        #expect(harness.viewModel.pendingDeletion == nil)
        #expect(!harness.viewModel.isDeleting)
    }

    @Test("삭제는 로컬에서 즉시 성공하고 pendingDelete로 표시한다")
    func deleteSucceedsLocallyAndMarksPendingDelete() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")]
        )
        let category = try #require(harness.store.expenseCategories.first)

        harness.viewModel.requestDelete(category)
        let outcome = await harness.viewModel.confirmDelete()

        #expect(outcome == .success)
        #expect(harness.service.deletedIDs.isEmpty)
        #expect(harness.cache.categories.first?.syncState == .pendingDelete)
        #expect(harness.store.expenseCategories.isEmpty)
    }

    @Test("로컬 삭제는 서버 삭제 오류를 기다리지 않고 성공한다")
    func localDeleteDoesNotCallServer() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")]
        )
        let category = try #require(harness.store.expenseCategories.first)

        harness.viewModel.requestDelete(category)
        let outcome = await harness.viewModel.confirmDelete()

        #expect(outcome == .success)
        #expect(harness.service.deletedIDs.isEmpty)
        #expect(harness.service.fetchCalls.isEmpty)
        #expect(harness.store.expenseCategories.isEmpty)
        #expect(!harness.viewModel.isDeleting)
    }

    @Test("삭제 진행 중에는 재진입·취소가 무시되고 요청은 한 번만 나간다")
    func confirmDeleteIgnoresReentryWhileBusy() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")],
            gateDelete: true
        )
        let category = try #require(harness.store.expenseCategories.first)
        harness.viewModel.requestDelete(category)

        let first = Task { await harness.viewModel.confirmDelete() }
        await waitUntil { harness.cache.removeStarted }

        #expect(harness.viewModel.isDeleting)
        let reentry = await harness.viewModel.confirmDelete()
        #expect(reentry == nil)
        harness.viewModel.cancelDelete()
        #expect(harness.viewModel.pendingDeletion?.id == 900)

        harness.cache.releaseRemove()
        let outcome = await first.value

        #expect(outcome == .success)
        #expect(harness.service.deletedIDs.isEmpty)
        #expect(!harness.viewModel.isDeleting)
        #expect(harness.viewModel.pendingDeletion == nil)
    }
}

// MARK: - 순서 재배치(드래그·접근성 이동)

extension CategoryManageViewModelTests {
    @Test("아래로 끌면 목표 인덱스와 보정된 오프셋이 함께 맞고, 목록 끝에서 멈춘다")
    func dragDownMovesRowAndCompensatesOffset() async throws {
        let harness = try await makeManageHarness(cachedCustom: orderedExpenseCustom())
        let viewModel = harness.viewModel
        #expect(viewModel.rows.map(\.id) == [901, 902, 903])

        viewModel.beginDrag(id: 901)
        #expect(viewModel.draggingID == 901)
        #expect(viewModel.draggingOffset == 0)

        // 반 칸(56/2)을 못 넘으면 자리는 그대로고 오프셋만 손가락을 따라간다.
        viewModel.updateDrag(translation: 20)
        #expect(viewModel.rows.map(\.id) == [901, 902, 903])
        #expect(viewModel.draggingOffset == 20)

        // 아래로 1칸: 재배열로 기준 위치가 이미 56 내려갔으므로 보정 후 오프셋은 0이다.
        viewModel.updateDrag(translation: 56)
        #expect(viewModel.rows.map(\.id) == [902, 901, 903])
        #expect(viewModel.draggingOffset == 0)

        // 1.5칸: 목표는 마지막 자리, 손가락은 그 자리보다 28 위에 있다.
        viewModel.updateDrag(translation: 84)
        #expect(viewModel.rows.map(\.id) == [902, 903, 901])
        #expect(viewModel.draggingOffset == -28)

        // 아래로 2칸.
        viewModel.updateDrag(translation: 112)
        #expect(viewModel.rows.map(\.id) == [902, 903, 901])
        #expect(viewModel.draggingOffset == 0)

        // 마지막 행을 더 아래로 끌어도 목록 밖으로 나가지 않는다 — 인덱스도 오프셋도 멈춘다.
        viewModel.updateDrag(translation: 500)
        #expect(viewModel.rows.map(\.id) == [902, 903, 901])
        #expect(viewModel.draggingOffset == 0)
    }

    @Test("위로 끌기도 같은 보정을 받고 첫 자리에서 clamp된다")
    func dragUpMovesRowAndClampsAtTop() async throws {
        let harness = try await makeManageHarness(cachedCustom: orderedExpenseCustom())
        let viewModel = harness.viewModel

        viewModel.beginDrag(id: 903)
        #expect(viewModel.draggingID == 903)

        // 위로 1.5칸: 목표는 첫 자리, 손가락은 그 자리보다 28 아래에 있다.
        viewModel.updateDrag(translation: -84)
        #expect(viewModel.rows.map(\.id) == [903, 901, 902])
        #expect(viewModel.draggingOffset == 28)

        // 위로 2칸.
        viewModel.updateDrag(translation: -112)
        #expect(viewModel.rows.map(\.id) == [903, 901, 902])
        #expect(viewModel.draggingOffset == 0)

        // 첫 행을 더 위로 끌어도 목록 밖으로 나가지 않는다.
        viewModel.updateDrag(translation: -500)
        #expect(viewModel.rows.map(\.id) == [903, 901, 902])
        #expect(viewModel.draggingOffset == 0)

        // 위로 1칸으로 되돌리기.
        viewModel.updateDrag(translation: -56)
        #expect(viewModel.rows.map(\.id) == [901, 903, 902])
        #expect(viewModel.draggingOffset == 0)
    }

    @Test("행이 1개면 아무리 끌어도 순서·오프셋이 움직이지 않고 커밋도 하지 않는다")
    func dragWithSingleRowNeitherMovesNorCommits() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [cachedCategory(id: 901, type: .expense, name: "🏋️ 헬스장", sortOrder: 1001)]
        )
        let viewModel = harness.viewModel

        viewModel.beginDrag(id: 901)
        viewModel.updateDrag(translation: 500)
        #expect(viewModel.rows.map(\.id) == [901])
        #expect(viewModel.draggingOffset == 0)

        viewModel.updateDrag(translation: -500)
        #expect(viewModel.draggingOffset == 0)

        let outcome = await viewModel.endDrag(id: 901)

        #expect(outcome == nil)
        #expect(harness.cache.orderQueue.isEmpty)
        #expect(viewModel.draggingID == nil)
        #expect(!viewModel.isReordering)
    }

    @Test("놓으면 로컬에 순서를 커밋하고 전송 큐에 등록한다")
    func endDragCommitsOrderLocallyAndQueuesType() async throws {
        let harness = try await makeManageHarness(cachedCustom: orderedExpenseCustom())
        let viewModel = harness.viewModel

        viewModel.beginDrag(id: 901)
        viewModel.updateDrag(translation: 112)
        let outcome = await viewModel.endDrag(id: 901)

        #expect(outcome == .committed)
        #expect(viewModel.rows.map(\.id) == [902, 903, 901])
        #expect(harness.store.expenseCategories.map(\.id) == [902, 903, 901])
        #expect(harness.cache.orderQueue == [.expense])
        #expect(harness.cache.categories.first { $0.id == 901 }?.sortOrder == 1003)
        #expect(viewModel.draggingID == nil)
        #expect(viewModel.draggingOffset == 0)
        #expect(!viewModel.isReordering)
    }

    @Test("드래그 중에는 refresh가 행 순서도 내용도 흔들지 못한다")
    func dragSnapshotIsolatesRowsFromRefresh() async throws {
        let harness = try await makeManageHarness(cachedCustom: orderedExpenseCustom())
        let viewModel = harness.viewModel

        viewModel.beginDrag(id: 901)
        viewModel.updateDrag(translation: 56)

        // 이름 변경 + 행 추가 + 행 삭제가 한꺼번에 도착해도 스냅샷이 목록을 고정한다.
        harness.service.expense = [
            categoryDTO(id: 901, name: "🏋️ 헬스클럽", sortOrder: 1001),
            categoryDTO(id: 904, name: "🍜 야식", sortOrder: 1004)
        ]
        await harness.store.refresh()

        #expect(harness.store.expenseCategories.map(\.id) == [901, 904])
        #expect(viewModel.rows.map(\.id) == [902, 901, 903])
        #expect(viewModel.rows.first { $0.id == 901 }?.category.displayNameKo == "🏋️ 헬스장")
    }

    @Test("커밋 시점에 목록 구성이 바뀌었으면 조용히 최신 목록으로 되돌린다")
    func staleCommitRestoresStoreOrderWithoutOutcome() async throws {
        let harness = try await makeManageHarness(cachedCustom: orderedExpenseCustom())
        let viewModel = harness.viewModel

        viewModel.beginDrag(id: 901)
        viewModel.updateDrag(translation: 56)

        harness.service.expense = [
            categoryDTO(id: 901, name: "🏋️ 헬스장", sortOrder: 1001),
            categoryDTO(id: 902, name: "🍜 야식", sortOrder: 1002)
        ]
        await harness.store.refresh()

        let outcome = await viewModel.endDrag(id: 901)

        #expect(outcome == nil)
        #expect(viewModel.rows.map(\.id) == [901, 902])
        #expect(harness.cache.orderQueue.isEmpty)
        #expect(viewModel.draggingID == nil)
        #expect(viewModel.draggingOffset == 0)
        #expect(!viewModel.isReordering)
    }

    @Test("로컬 쓰기가 거부되면 순서를 저장하지 않고 결과를 화면으로 올린다")
    func localWriteRejectionRestoresOrderAndReportsOutcome() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: orderedExpenseCustom(),
            rejectsLocalWrites: true
        )
        let viewModel = harness.viewModel

        viewModel.beginDrag(id: 901)
        viewModel.updateDrag(translation: 56)
        #expect(viewModel.rows.map(\.id) == [902, 901, 903])

        let outcome = await viewModel.endDrag(id: 901)

        #expect(outcome == .localWriteRejected)
        #expect(viewModel.rows.map(\.id) == [901, 902, 903])
        #expect(harness.cache.orderQueue.isEmpty)
        #expect(harness.cache.categories.first { $0.id == 901 }?.sortOrder == 1001)
        #expect(viewModel.draggingID == nil)
        #expect(viewModel.draggingOffset == 0)
        #expect(!viewModel.isReordering)
    }

    @Test("드래그 중에는 삭제 요청과 탭 전환이 무시된다")
    func dragLocksDeleteRequestAndTabSwitch() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: orderedExpenseCustom()
                + [cachedCategory(id: 910, type: .income, name: "💰 용돈", sortOrder: 1001)]
        )
        let viewModel = harness.viewModel
        let category = try #require(viewModel.rows.first?.category)

        viewModel.beginDrag(id: 901)
        viewModel.updateDrag(translation: 56)
        #expect(viewModel.isReordering)

        viewModel.requestDelete(category)
        viewModel.selectTab(.income)

        #expect(viewModel.pendingDeletion == nil)
        #expect(viewModel.tab == .expense)
        #expect(viewModel.rows.map(\.id) == [902, 901, 903])
    }

    @Test("접근성 이동은 경계 밖에서 무동작이고, 안에서는 드래그와 같은 커밋 경로를 탄다")
    func accessibilityMoveNoOpsOutsideBoundsAndCommitsInside() async throws {
        let harness = try await makeManageHarness(cachedCustom: orderedExpenseCustom())
        let viewModel = harness.viewModel

        #expect(await viewModel.move(id: 901, by: -1) == nil)
        #expect(await viewModel.move(id: 903, by: 1) == nil)
        #expect(harness.cache.orderQueue.isEmpty)
        #expect(viewModel.rows.map(\.id) == [901, 902, 903])

        let outcome = await viewModel.move(id: 901, by: 1)

        #expect(outcome == .committed)
        #expect(viewModel.rows.map(\.id) == [902, 901, 903])
        #expect(harness.store.expenseCategories.map(\.id) == [902, 901, 903])
        #expect(harness.cache.orderQueue == [.expense])
        #expect(harness.cache.categories.first { $0.id == 901 }?.sortOrder == 1002)
        #expect(viewModel.draggingID == nil)
        #expect(!viewModel.isReordering)
    }

    @Test("커밋을 기다리는 동안 들어온 조작은 진행 중인 순서를 흔들지도, 두 번 커밋하지도 않는다")
    func reentryDuringCommitLeavesOrderIntactAndCommitsOnce() async throws {
        let hold = LocalWriteHold()
        let harness = try await makeManageHarness(
            cachedCustom: orderedExpenseCustom(),
            localWriteHold: hold
        )
        let viewModel = harness.viewModel

        viewModel.beginDrag(id: 901)
        viewModel.updateDrag(translation: 56)
        let commit = Task { await viewModel.endDrag(id: 901) }
        await waitUntil { hold.isHeld }

        // 커밋이 끝나기 전 같은 행을 다시 잡고 놓아도 순서가 흔들리거나 두 번 커밋되지 않는다.
        #expect(!viewModel.beginDrag(id: 901))
        viewModel.updateDrag(translation: -112)

        #expect(viewModel.rows.map(\.id) == [902, 901, 903])
        #expect(await viewModel.endDrag(id: 901) == nil)

        hold.release()

        #expect(await commit.value == .committed)
        #expect(harness.store.expenseCategories.map(\.id) == [902, 901, 903])
        #expect(harness.cache.orderQueue == [.expense])
    }

    @Test("두 번째 손가락이나 접근성 이동은 진행 중인 다른 행의 드래그를 가로채지 못한다")
    func crossRowInputDoesNotHijackActiveDrag() async throws {
        let harness = try await makeManageHarness(cachedCustom: orderedExpenseCustom())
        let viewModel = harness.viewModel

        #expect(viewModel.beginDrag(id: 901))
        viewModel.updateDrag(translation: 56)

        // 핸들은 행마다 독립된 제스처라 두 손가락이 동시에 잡힐 수 있다.
        #expect(!viewModel.beginDrag(id: 903))
        // 그 손가락이 먼저 떨어져도 남의 드래그를 커밋하지 않는다.
        #expect(await viewModel.endDrag(id: 903) == nil)
        // 접근성 이동도 같은 이유로 끼어들지 못한다.
        #expect(await viewModel.move(id: 903, by: -1) == nil)

        #expect(viewModel.rows.map(\.id) == [902, 901, 903])
        #expect(viewModel.draggingID == 901)
        #expect(harness.cache.orderQueue.isEmpty)

        #expect(await viewModel.endDrag(id: 901) == .committed)
        #expect(harness.store.expenseCategories.map(\.id) == [902, 901, 903])
    }
}

/// 첫 로컬 쓰기 하나만 붙잡아 "커밋을 기다리는 중"을 결정적으로 재현한다.
@MainActor
private final class LocalWriteHold {
    private(set) var isHeld = false
    private var didHold = false
    private var isReleased = false
    private var continuation: CheckedContinuation<Void, Never>?

    func holdFirst() async {
        guard !didHold else {
            return
        }
        didHold = true
        isHeld = true
        await withCheckedContinuation { continuation in
            // release가 먼저 도착했으면 기다리지 않는다. `isHeld`를 세운 뒤 이 클로저에
            // 닿기까지 실행이 넘어갈 수 있어(게이트 클로저는 nonisolated라 hop이 실제로 난다),
            // 신호를 버리면 아무도 깨우지 않는 continuation에 걸려 스위트가 통째로 멈춘다
            // (`CustomCategoryCacheStub.releaseUpsert`와 같은 함정). 등록과 판정을 같은
            // 동기 구간에 두어야 그 창이 사라진다.
            if isReleased {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func release() {
        isReleased = true
        isHeld = false
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private struct ManageHarness {
    let viewModel: CategoryManageViewModel
    let store: CustomCategoryStore
    let service: ManageServiceStub
    let cache: CustomCategoryCacheStub
}

@MainActor
private func makeManageHarness(
    tab: EntryType = .expense,
    cachedCustom: [CachedCustomCategory] = [],
    gateDelete: Bool = false,
    fetchError: Error? = nil,
    rejectsLocalWrites: Bool = false,
    localWriteHold: LocalWriteHold? = nil
) async throws -> ManageHarness {
    let auth = FakeAuthService()
    try await auth.signIn(.google)
    let service = ManageServiceStub(
        fetchError: fetchError
    )
    let cache = CustomCategoryCacheStub(categories: cachedCustom, gateNextRemove: gateDelete)
    let store = try CustomCategoryStore(
        service: service,
        cache: cache,
        authProvider: auth
    )
    if rejectsLocalWrites {
        // 로그아웃 정리·purge 중 로컬 커밋 자체를 거부하는 경로(`SyncEngine.performLocalWrite`).
        store.configure(localWriteGate: { _ in
            throw SyncEngineError.localWritesSuspended
        })
    }
    if let localWriteHold {
        // 게이트는 대입이라 두 번 꽂으면 뒤가 앞을 조용히 덮는다 — 함께 쓰면 그 자리에서 멈춘다.
        precondition(!rejectsLocalWrites, "rejectsLocalWrites와 localWriteHold는 함께 쓸 수 없다")
        store.configure(localWriteGate: { work in
            await localWriteHold.holdFirst()
            try await work()
        })
    }
    let viewModel = CategoryManageViewModel(
        tab: tab,
        customCategoryStore: store
    )
    return ManageHarness(
        viewModel: viewModel,
        store: store,
        service: service,
        cache: cache
    )
}

@MainActor
private final class ManageServiceStub: CustomCategoryServicing {
    var expense: [CategoryDTO]
    var income: [CategoryDTO]
    var fetchError: Error?
    private(set) var fetchCalls: [CatalogTransactionType] = []
    private(set) var deletedIDs: [Int] = []

    init(
        expense: [CategoryDTO] = [],
        income: [CategoryDTO] = [],
        fetchError: Error? = nil
    ) {
        self.expense = expense
        self.income = income
        self.fetchError = fetchError
    }

    func fetchCustomCategories(transactionType: String) async throws -> [CategoryDTO] {
        let type = try #require(CatalogTransactionType(rawValue: transactionType))
        fetchCalls.append(type)
        if let fetchError {
            throw fetchError
        }
        return type == .expense ? expense : income
    }

    func createCustomCategory(name _: String, transactionType _: String) async throws -> CategoryDTO {
        Issue.record("이 스위트에서 create는 호출되지 않아야 한다")
        throw ManageTestError.unexpectedCall
    }

    func updateCustomCategory(id _: Int, name _: String) async throws -> CategoryDTO {
        Issue.record("이 스위트에서 update는 호출되지 않아야 한다")
        throw ManageTestError.unexpectedCall
    }

    func reorderCustomCategories(orderedIDs _: [Int], transactionType _: String) async throws -> [CategoryDTO] {
        Issue.record("로컬 reorder는 서버를 호출하지 않아야 한다")
        throw ManageTestError.unexpectedCall
    }

    func deleteCustomCategory(id: Int) async throws {
        deletedIDs.append(id)
        Issue.record("로컬 remove는 서버를 호출하지 않아야 한다")
    }
}

/// sortOrder를 명시해 표시 순서를 id와 분리한다 — 정렬 원천이 sort_order다(step 2).
private func orderedExpenseCustom() -> [CachedCustomCategory] {
    [
        cachedCategory(id: 901, type: .expense, name: "🏋️ 헬스장", sortOrder: 1001),
        cachedCategory(id: 902, type: .expense, name: "🍜 야식", sortOrder: 1002),
        cachedCategory(id: 903, type: .expense, name: "🚌 교통", sortOrder: 1003)
    ]
}

private enum ManageTestError: Error {
    case requestFailed
    case unexpectedCall
}
