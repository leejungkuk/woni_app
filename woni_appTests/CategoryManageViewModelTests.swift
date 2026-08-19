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
        await waitUntil { harness.service.deleteStarted }

        harness.viewModel.selectTab(.income)
        #expect(harness.viewModel.tab == .expense)

        harness.service.releaseDelete()
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

    @Test("오프라인이면 push 시도 전에 삭제를 중단한다")
    func offlineDeleteStopsBeforePushAndDelete() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")],
            isOnline: false
        )
        let category = try #require(harness.store.expenseCategories.first)

        harness.viewModel.requestDelete(category)
        let outcome = await harness.viewModel.confirmDelete()

        #expect(outcome == .offline)
        #expect(harness.sync.pushPendingCount == 0)
        #expect(harness.service.deletedIDs.isEmpty)
        #expect(harness.viewModel.pendingDeletion == nil)
        #expect(!harness.viewModel.isDeleting)
    }

    @Test("push 후에도 해당 카테고리 참조 미동기 내역이 남으면 삭제를 차단한다")
    func deleteBlockedWhenPendingEntriesReferenceCategory() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")]
        )
        try await insertPendingEntry(into: harness.repository, categoryID: 900)
        let category = try #require(harness.store.expenseCategories.first)

        harness.viewModel.requestDelete(category)
        let outcome = await harness.viewModel.confirmDelete()

        #expect(outcome == .blockedByPendingEntries)
        #expect(harness.sync.pushPendingCount == 1)
        #expect(harness.service.deletedIDs.isEmpty)
        #expect(harness.store.expenseCategories.map(\.id) == [900])
    }

    @Test("무관한 카테고리의 미동기 내역으로는 삭제를 막지 않는다")
    func deleteProceedsWhenPendingEntriesAreUnrelated() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")]
        )
        try await insertPendingEntry(into: harness.repository, categoryID: 777)
        let category = try #require(harness.store.expenseCategories.first)

        harness.viewModel.requestDelete(category)
        let outcome = await harness.viewModel.confirmDelete()

        #expect(outcome == .success)
        #expect(harness.service.deletedIDs == [900])
        #expect(harness.store.expenseCategories.isEmpty)
    }

    @Test("push가 미동기 잔량을 비우면 잔존 판정은 push 이후 상태로 삭제를 허용한다")
    func pushDrainBeforeCheckAllowsDelete() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")]
        )
        let clientEntryID = UUID()
        try await insertPendingEntry(
            into: harness.repository,
            categoryID: 900,
            clientEntryID: clientEntryID
        )
        harness.sync.onPushPending = { [repository = harness.repository] in
            try? await repository.markSynced(clientEntryIDs: [clientEntryID])
        }
        let category = try #require(harness.store.expenseCategories.first)

        harness.viewModel.requestDelete(category)
        let outcome = await harness.viewModel.confirmDelete()

        #expect(outcome == .success)
        #expect(harness.service.deletedIDs == [900])
    }

    @Test("404 삭제 실패는 오류로 알리고 refresh로 서버 목록에 수렴한다")
    func delete404ReportsFailureAndConvergesViaRefresh() async throws {
        let harness = try await makeManageHarness(
            cachedCustom: [CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")],
            deleteError: APIError.server(code: "CATEGORY_NOT_FOUND", message: "not found")
        )
        let category = try #require(harness.store.expenseCategories.first)

        harness.viewModel.requestDelete(category)
        let outcome = await harness.viewModel.confirmDelete()

        #expect(outcome == .failed)
        #expect(harness.service.fetchCalls == [.expense, .income])
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
        await waitUntil { harness.service.deleteStarted }

        #expect(harness.viewModel.isDeleting)
        let reentry = await harness.viewModel.confirmDelete()
        #expect(reentry == nil)
        harness.viewModel.cancelDelete()
        #expect(harness.viewModel.pendingDeletion?.id == 900)

        harness.service.releaseDelete()
        let outcome = await first.value

        #expect(outcome == .success)
        #expect(harness.service.deletedIDs == [900])
        #expect(!harness.viewModel.isDeleting)
        #expect(harness.viewModel.pendingDeletion == nil)
    }
}

@MainActor
private struct ManageHarness {
    let viewModel: CategoryManageViewModel
    let store: CustomCategoryStore
    let service: ManageServiceStub
    let sync: ForegroundSyncingStub
    let connectivity: FakeConnectivityMonitor
    let repository: TransactionRepository
}

@MainActor
private func makeManageHarness(
    tab: EntryType = .expense,
    cachedCustom: [CachedCustomCategory] = [],
    deleteError: Error? = nil,
    gateDelete: Bool = false,
    fetchError: Error? = nil,
    isOnline: Bool = true
) async throws -> ManageHarness {
    let auth = FakeAuthService()
    try await auth.signIn(.google)
    let service = ManageServiceStub(
        fetchError: fetchError,
        deleteError: deleteError,
        gateDelete: gateDelete
    )
    let store = try CustomCategoryStore(
        service: service,
        cache: ManageCacheStub(categories: cachedCustom),
        authProvider: auth
    )
    let repository = try TransactionRepository(database: AppDatabase.inMemory())
    let connectivity = FakeConnectivityMonitor(isOnline: isOnline)
    let sync = ForegroundSyncingStub()
    let viewModel = CategoryManageViewModel(
        tab: tab,
        customCategoryStore: store,
        connectivity: connectivity,
        sync: sync,
        transactionRepository: repository
    )
    return ManageHarness(
        viewModel: viewModel,
        store: store,
        service: service,
        sync: sync,
        connectivity: connectivity,
        repository: repository
    )
}

@MainActor
private func insertPendingEntry(
    into repository: TransactionRepository,
    categoryID: Int,
    clientEntryID: UUID = UUID()
) async throws {
    try await repository.insert(LocalTransaction(
        clientEntryID: clientEntryID,
        amount: 1000,
        currencyCode: "KRW",
        categoryID: categoryID,
        assetID: 20,
        transactionType: .expense,
        transactionDate: "2026-08-01"
    ))
}

@MainActor
private final class ManageServiceStub: CustomCategoryServicing {
    var expense: [CategoryDTO]
    var income: [CategoryDTO]
    var fetchError: Error?
    var deleteError: Error?
    private(set) var fetchCalls: [CatalogTransactionType] = []
    private(set) var deletedIDs: [Int] = []
    private(set) var deleteStarted = false

    private var gateDelete: Bool
    private var deleteContinuation: CheckedContinuation<Void, Never>?

    init(
        expense: [CategoryDTO] = [],
        income: [CategoryDTO] = [],
        fetchError: Error? = nil,
        deleteError: Error? = nil,
        gateDelete: Bool = false
    ) {
        self.expense = expense
        self.income = income
        self.fetchError = fetchError
        self.deleteError = deleteError
        self.gateDelete = gateDelete
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

    func deleteCustomCategory(id: Int) async throws {
        deletedIDs.append(id)
        if gateDelete {
            deleteStarted = true
            await withCheckedContinuation { deleteContinuation = $0 }
        }
        if let deleteError {
            throw deleteError
        }
    }

    func releaseDelete() {
        gateDelete = false
        deleteContinuation?.resume()
        deleteContinuation = nil
    }
}

@MainActor
private final class ManageCacheStub: CustomCategoryCaching {
    var categories: [CachedCustomCategory]

    init(categories: [CachedCustomCategory] = []) {
        self.categories = categories
    }

    func load(for transactionType: CatalogTransactionType) throws -> [CachedCustomCategory] {
        categories
            .filter { $0.transactionType == transactionType }
            .sorted { $0.id < $1.id }
    }

    func replaceAll(_ categories: [CachedCustomCategory]) async throws {
        self.categories = categories.sorted { $0.id < $1.id }
    }

    func clearAll() async throws {
        categories = []
    }
}

@MainActor
private final class ForegroundSyncingStub: ForegroundSyncing {
    private(set) var pushPendingCount = 0
    var onPushPending: (@MainActor () async -> Void)?

    func pushPending() async {
        pushPendingCount += 1
        await onPushPending?()
    }

    func pullChanges() async throws {}
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
