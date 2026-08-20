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
        await waitUntil { harness.cache.updateStateStarted }

        harness.viewModel.selectTab(.income)
        #expect(harness.viewModel.tab == .expense)

        harness.cache.releaseUpdateState()
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
        harness.service.expense = [manageCategoryDTO(id: 901, name: "🐶 반려동물")]
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
        await waitUntil { harness.cache.updateStateStarted }

        #expect(harness.viewModel.isDeleting)
        let reentry = await harness.viewModel.confirmDelete()
        #expect(reentry == nil)
        harness.viewModel.cancelDelete()
        #expect(harness.viewModel.pendingDeletion?.id == 900)

        harness.cache.releaseUpdateState()
        let outcome = await first.value

        #expect(outcome == .success)
        #expect(harness.service.deletedIDs.isEmpty)
        #expect(!harness.viewModel.isDeleting)
        #expect(harness.viewModel.pendingDeletion == nil)
    }
}

@MainActor
private struct ManageHarness {
    let viewModel: CategoryManageViewModel
    let store: CustomCategoryStore
    let service: ManageServiceStub
    let cache: ManageCacheStub
}

@MainActor
private func makeManageHarness(
    tab: EntryType = .expense,
    cachedCustom: [CachedCustomCategory] = [],
    gateDelete: Bool = false,
    fetchError: Error? = nil
) async throws -> ManageHarness {
    let auth = FakeAuthService()
    try await auth.signIn(.google)
    let service = ManageServiceStub(
        fetchError: fetchError
    )
    let cache = ManageCacheStub(categories: cachedCustom, gateNextUpdateState: gateDelete)
    let store = try CustomCategoryStore(
        service: service,
        cache: cache,
        authProvider: auth
    )
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

    func deleteCustomCategory(id: Int) async throws {
        deletedIDs.append(id)
        Issue.record("로컬 remove는 서버를 호출하지 않아야 한다")
    }
}

@MainActor
private final class ManageCacheStub: CustomCategoryCaching {
    var categories: [CachedCustomCategory]
    private var gateNextUpdateState: Bool
    private var updateStateContinuation: CheckedContinuation<Void, Never>?
    private(set) var updateStateStarted = false

    init(categories: [CachedCustomCategory] = [], gateNextUpdateState: Bool = false) {
        self.categories = categories
        self.gateNextUpdateState = gateNextUpdateState
    }

    func load(for transactionType: CatalogTransactionType) throws -> [CachedCustomCategory] {
        categories
            .filter {
                $0.transactionType == transactionType
                    && [.synced, .pendingCreate, .pendingUpdate].contains($0.syncState)
            }
            .sorted { $0.id > $1.id }
    }

    func loadAll() throws -> [CachedCustomCategory] {
        categories.sorted { $0.id > $1.id }
    }

    func replaceSynced(_ categories: [CachedCustomCategory]) async throws {
        self.categories.removeAll { $0.syncState == .synced }
        self.categories.append(contentsOf: categories)
    }

    func upsert(_ category: CachedCustomCategory) async throws {
        categories.removeAll { $0.id == category.id }
        categories.append(category)
    }

    func renameLocally(id: Int, name: String) async throws {
        guard let index = try editableIndex(of: id) else {
            throw CustomCategoryCacheError.categoryNotFound(id: id)
        }
        let current = categories[index]
        categories[index] = CachedCustomCategory(
            id: current.id,
            transactionType: current.transactionType,
            name: name,
            syncState: current.syncState == .synced ? .pendingUpdate : current.syncState
        )
    }

    func removeLocally(id: Int) async throws {
        if gateNextUpdateState {
            gateNextUpdateState = false
            updateStateStarted = true
            await withCheckedContinuation { updateStateContinuation = $0 }
        }
        guard let index = try editableIndex(of: id) else {
            throw CustomCategoryCacheError.categoryNotFound(id: id)
        }
        let isReferenced = try referencedCategoryIDs().contains(id)
        if categories[index].syncState == .pendingCreate, !isReferenced {
            categories.remove(at: index)
        } else {
            categories[index].syncState = .pendingDelete
        }
    }

    private func editableIndex(of id: Int) throws -> Int? {
        guard
            let index = categories.firstIndex(where: { $0.id == id }),
            ![.pendingDelete, .deleted].contains(categories[index].syncState)
        else {
            return nil
        }
        return index
    }

    func updateSyncState(id: Int, to state: CustomCategorySyncState) async throws {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].syncState = state
    }

    func deleteRow(id: Int) async throws {
        categories.removeAll { $0.id == id }
    }

    func nextLocalID(reserving reservedIDs: Set<Int>) throws -> Int {
        min(categories.map(\.id).min() ?? 0, reservedIDs.min() ?? 0, 0) - 1
    }

    func activeCount() throws -> Int {
        categories.count { [.synced, .pendingCreate, .pendingUpdate].contains($0.syncState) }
    }

    func remap(from oldID: Int, to newID: Int) async throws {
        categories = categories.map {
            $0.id == oldID
                ? CachedCustomCategory(
                    id: newID,
                    transactionType: $0.transactionType,
                    name: $0.name,
                    syncState: $0.syncState
                )
                : $0
        }
    }

    func referencedCategoryIDs() throws -> Set<Int> {
        []
    }

    func pendingPushCategoryIDs() throws -> Set<Int> {
        []
    }

    func resetForAccountSwitch(reserving _: Set<Int>) async throws -> [Int: Int] {
        [:]
    }

    func clearAll() async throws {
        categories = []
    }

    func releaseUpdateState() {
        updateStateContinuation?.resume()
        updateStateContinuation = nil
    }
}

private enum ManageTestError: Error {
    case requestFailed
    case unexpectedCall
}

private func manageCategoryDTO(id: Int, name: String) -> CategoryDTO {
    CategoryDTO(
        id: id,
        code: "CUSTOM",
        displayNameKo: name,
        displayNameEn: name,
        icon: nil,
        sortOrder: 1000
    )
}
