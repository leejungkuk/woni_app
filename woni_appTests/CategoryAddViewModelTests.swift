//
//  CategoryAddViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct CategoryAddViewModelTests {
    @Test("공백만 입력하면 저장이 비활성화되고 요청도 나가지 않는다")
    func whitespaceOnlyNameDisablesSave() async throws {
        let harness = try makeAddCategoryHarness()
        harness.viewModel.name = "   "

        #expect(harness.viewModel.canSave == false)
        #expect(harness.viewModel.nameLength == 0)
        #expect(await harness.viewModel.save() == nil)
        #expect(harness.service.createdNames.isEmpty)
    }

    @Test("UTF-16 50 유닛(ZWJ 이모지 포함)은 허용하고 51 유닛은 거부한다")
    func utf16BoundaryGovernsSaveAvailability() throws {
        let harness = try makeAddCategoryHarness()
        let fifty = String(repeating: "👨‍👩‍👧‍👦", count: 4) + "abcdef"
        #expect(fifty.utf16.count == 50)
        harness.viewModel.name = fifty
        #expect(harness.viewModel.canSave == true)

        // grapheme으로는 11자뿐 — 한도의 단위가 서버와 같은 UTF-16임을 고정한다.
        let fiftyOne = fifty + "g"
        #expect(fiftyOne.count == 11)
        #expect(fiftyOne.utf16.count == 51)
        harness.viewModel.name = fiftyOne
        #expect(harness.viewModel.canSave == false)
    }

    @Test("카운터는 trim한 이름의 grapheme 수가 아니라 UTF-16 유닛 수를 센다")
    func counterCountsUTF16UnitsOfTrimmedName() throws {
        let harness = try makeAddCategoryHarness()
        harness.viewModel.name = " 🏋️ 헬스장 "

        // 🏋️(3 유닛) + 공백 + 헬스장(3) = 7. grapheme으로 세면 5가 되어 서버 기준과 어긋난다.
        #expect(harness.viewModel.nameLength == 7)
        #expect(harness.viewModel.canSave == true)
    }

    @Test("저장 성공은 trim한 이름으로 만들고 새 id로 입력 화면 자동 선택까지 이어진다")
    func saveSuccessReturnsNewIDAndAutoSelectsInEntryScreen() async throws {
        let harness = try makeAddCategoryHarness()
        let entryViewModel = try makeAddExpenseHarness(customCategoryStore: harness.store).viewModel
        await entryViewModel.load()
        harness.viewModel.name = " 🏋️ 헬스장 "

        let outcome = await harness.viewModel.save()

        #expect(outcome == .saved(id: -1, type: .expense))
        #expect(harness.service.createdNames.isEmpty)
        #expect(entryViewModel.visibleCategories.contains { $0.id == -1 })

        // View 완료 콜백과 동일한 수신 지점(결정 10).
        entryViewModel.selectCategory(id: -1)
        #expect(entryViewModel.selectedCategoryId == -1)
    }

    @Test("오프라인 여부와 무관하게 로컬 저장이 성공한다")
    func localSaveSucceedsWithoutConnectivityGate() async throws {
        let harness = try makeAddCategoryHarness()
        harness.viewModel.name = "🚕 택시"

        let outcome = await harness.viewModel.save()

        #expect(outcome == .saved(id: -1, type: .expense))
        #expect(harness.service.createdNames.isEmpty)
        #expect(harness.store.expenseCategories.first?.displayNameKo == "🚕 택시")
        #expect(harness.viewModel.isSaving == false)
    }

    @Test("수정 모드는 초기 이름을 주입하고 타입 탭을 숨긴 채 타입 전환을 막는다")
    func editModeInjectsNameAndHidesTypeTab() throws {
        let harness = try makeAddCategoryHarness(
            mode: .edit(id: 900),
            initialName: "🏋️ 헬스장",
            cachedCustom: [
                CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")
            ]
        )

        #expect(harness.viewModel.name == "🏋️ 헬스장")
        #expect(harness.viewModel.showsTypeTab == false)

        harness.viewModel.selectTab(.income)
        #expect(harness.viewModel.tab == .expense)
    }

    @Test("수정 안내는 생성 문구 대신 기존 내역 반영을 알린다")
    func editNoticeExplainsExistingEntryUpdates() {
        let notice = WoniStrings.categoryEditNotice(.ko)

        #expect(notice == "이름을 바꾸면 이 카테고리를 쓴 내역에도 함께 반영돼요.")
        #expect(!notice.contains("만들어져요"))
    }

    @Test("수정 저장은 trim한 이름으로 rename하고 updated를 반환한다")
    func editSaveRenamesCategoryAndReturnsUpdated() async throws {
        let harness = try makeAddCategoryHarness(
            mode: .edit(id: 900),
            initialName: "🏋️ 헬스장",
            cachedCustom: [
                CachedCustomCategory(id: 900, transactionType: .expense, name: "🏋️ 헬스장")
            ]
        )
        harness.viewModel.name = "  🧘 요가  "

        let outcome = await harness.viewModel.save()

        #expect(outcome == .updated)
        #expect(harness.service.createdNames.isEmpty)
        #expect(harness.store.expenseCategories.first?.displayNameKo == "🧘 요가")
        #expect(harness.viewModel.isSaving == false)
    }

    @Test("403 한도 초과는 한도 분기로 알리고 입력을 유지한다")
    func limitExceededKeepsInput() async throws {
        let harness = try makeAddCategoryHarness(activeCount: 100)
        harness.viewModel.name = "🚕 택시"

        let outcome = await harness.viewModel.save()

        #expect(outcome == .limitExceeded)
        #expect(harness.viewModel.name == "🚕 택시")
        #expect(harness.store.expenseCategories.count == 100)
        #expect(harness.viewModel.isSaving == false)
    }

    @Test("저장 진행 중 재진입은 무시되고 요청은 한 번만 나간다")
    func saveIgnoresReentryWhileBusy() async throws {
        let harness = try makeAddCategoryHarness(gateCreate: true)
        harness.viewModel.name = "🚕 택시"

        let first = Task { await harness.viewModel.save() }
        await waitUntil { harness.cache.upsertStarted }
        #expect(harness.viewModel.isSaving)

        let reentry = await harness.viewModel.save()
        #expect(reentry == nil)
        #expect(harness.service.createdNames.isEmpty)

        harness.cache.releaseUpsert()
        let outcome = await first.value

        #expect(outcome == .saved(id: -1, type: .expense))
        #expect(harness.viewModel.isSaving == false)
    }

    @Test("stale-operation 경합은 일반 오류 분기로 끝나고 폐기된 결과를 반영하지 않는다")
    func staleOperationEndsAsGeneralFailure() async throws {
        let harness = try makeAddCategoryHarness(gateCreate: true)
        harness.viewModel.name = "🚕 택시"

        let save = Task { await harness.viewModel.save() }
        await waitUntil { harness.cache.upsertStarted }
        // 요청이 떠 있는 동안 로그아웃 정리가 revision을 올린 경합.
        let clearing = Task { try await harness.store.clear() }
        await Task.yield()
        harness.cache.releaseUpsert()
        let outcome = await save.value
        try await clearing.value

        #expect(outcome == .failed)
        #expect(harness.viewModel.name == "🚕 택시")
        #expect(harness.store.expenseCategories.isEmpty)
        #expect(harness.viewModel.isSaving == false)
    }

    @Test("탭 전환은 생성 타입을 바꾸고, 저장 진행 중에는 무시된다")
    func selectTabSwitchesCreateTypeAndIsIgnoredWhileSaving() async throws {
        let harness = try makeAddCategoryHarness(gateCreate: true)
        harness.viewModel.selectTab(.income)
        #expect(harness.viewModel.tab == .income)

        harness.viewModel.name = "💰 용돈"
        let save = Task { await harness.viewModel.save() }
        await waitUntil { harness.cache.upsertStarted }

        harness.viewModel.selectTab(.expense)
        #expect(harness.viewModel.tab == .income)

        harness.cache.releaseUpsert()
        let outcome = await save.value

        #expect(outcome == .saved(id: -1, type: .income))
        #expect(harness.store.incomeCategories.map(\.id) == [-1])
    }
}

@MainActor
private struct AddCategoryHarness {
    let viewModel: CategoryAddViewModel
    let store: CustomCategoryStore
    let service: AddCategoryServiceStub
    let cache: AddCategoryCacheStub
}

@MainActor
private func makeAddCategoryHarness(
    tab: EntryType = .expense,
    mode: CategoryAddViewModel.Mode = .create,
    initialName: String = "",
    cachedCustom: [CachedCustomCategory] = [],
    gateCreate: Bool = false,
    activeCount: Int = 0
) throws -> AddCategoryHarness {
    let service = AddCategoryServiceStub()
    let cache = AddCategoryCacheStub(
        categories: cachedCustom + (0 ..< activeCount).map {
            CachedCustomCategory(id: $0 + 1, transactionType: .expense, name: "\($0 + 1)")
        },
        gateNextUpsert: gateCreate
    )
    let store = try CustomCategoryStore(
        service: service,
        cache: cache,
        authProvider: FakeAuthService()
    )
    let viewModel = CategoryAddViewModel(
        tab: tab,
        customCategoryStore: store,
        mode: mode,
        name: initialName
    )
    return AddCategoryHarness(viewModel: viewModel, store: store, service: service, cache: cache)
}

@MainActor
private final class AddCategoryServiceStub: CustomCategoryServicing {
    private(set) var createdNames: [String] = []

    func fetchCustomCategories(transactionType _: String) async throws -> [CategoryDTO] {
        []
    }

    func createCustomCategory(name: String, transactionType _: String) async throws -> CategoryDTO {
        createdNames.append(name)
        Issue.record("로컬 create는 서버를 호출하지 않아야 한다")
        throw CustomCategoryServiceError.invalidName
    }

    func updateCustomCategory(id _: Int, name _: String) async throws -> CategoryDTO {
        Issue.record("이 스위트에서 update는 호출되지 않아야 한다")
        throw CustomCategoryServiceError.invalidName
    }

    func deleteCustomCategory(id _: Int) async throws {
        Issue.record("이 스위트에서 delete는 호출되지 않아야 한다")
    }
}

@MainActor
private final class AddCategoryCacheStub: CustomCategoryCaching {
    private var categories: [CachedCustomCategory]
    private var gateNextUpsert: Bool
    private var upsertContinuation: CheckedContinuation<Void, Never>?
    private(set) var upsertStarted = false

    init(categories: [CachedCustomCategory], gateNextUpsert: Bool) {
        self.categories = categories
        self.gateNextUpsert = gateNextUpsert
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
        if gateNextUpsert {
            gateNextUpsert = false
            upsertStarted = true
            await withCheckedContinuation { upsertContinuation = $0 }
        }
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

    func releaseUpsert() {
        upsertContinuation?.resume()
        upsertContinuation = nil
    }
}
