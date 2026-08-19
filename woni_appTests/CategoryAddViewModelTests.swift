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
        let harness = try makeAddCategoryHarness(nextID: 950)
        let entryViewModel = try makeAddExpenseHarness(customCategoryStore: harness.store).viewModel
        await entryViewModel.load()
        harness.viewModel.name = " 🏋️ 헬스장 "

        let outcome = await harness.viewModel.save()

        #expect(outcome == .saved(id: 950))
        #expect(harness.service.createdNames == ["🏋️ 헬스장"])
        #expect(entryViewModel.visibleCategories.contains { $0.id == 950 })

        // View 완료 콜백과 동일한 수신 지점(결정 10).
        entryViewModel.selectCategory(id: 950)
        #expect(entryViewModel.selectedCategoryId == 950)
    }

    @Test("오프라인이면 요청 없이 오프라인 분기로 끝나고 입력을 유지한다")
    func offlineSaveKeepsInputWithoutRequest() async throws {
        let harness = try makeAddCategoryHarness(isOnline: false)
        harness.viewModel.name = "🚕 택시"

        let outcome = await harness.viewModel.save()

        #expect(outcome == .offline)
        #expect(harness.service.createdNames.isEmpty)
        #expect(harness.viewModel.name == "🚕 택시")
        #expect(harness.viewModel.isSaving == false)
    }

    @Test("403 한도 초과는 한도 분기로 알리고 입력을 유지한다")
    func limitExceededKeepsInput() async throws {
        let harness = try makeAddCategoryHarness(
            createError: APIError.server(code: "CUSTOM_CATEGORY_LIMIT_EXCEEDED", message: "한도 초과")
        )
        harness.viewModel.name = "🚕 택시"

        let outcome = await harness.viewModel.save()

        #expect(outcome == .limitExceeded)
        #expect(harness.viewModel.name == "🚕 택시")
        #expect(harness.store.expenseCategories.isEmpty)
        #expect(harness.viewModel.isSaving == false)
    }

    @Test("저장 진행 중 재진입은 무시되고 요청은 한 번만 나간다")
    func saveIgnoresReentryWhileBusy() async throws {
        let harness = try makeAddCategoryHarness(nextID: 900, gateCreate: true)
        harness.viewModel.name = "🚕 택시"

        let first = Task { await harness.viewModel.save() }
        await waitUntil { harness.service.createStarted }
        #expect(harness.viewModel.isSaving)

        let reentry = await harness.viewModel.save()
        #expect(reentry == nil)
        #expect(harness.service.createdNames.count == 1)

        harness.service.releaseCreate()
        let outcome = await first.value

        #expect(outcome == .saved(id: 900))
        #expect(harness.viewModel.isSaving == false)
    }

    @Test("stale-operation 경합은 일반 오류 분기로 끝나고 폐기된 결과를 반영하지 않는다")
    func staleOperationEndsAsGeneralFailure() async throws {
        let harness = try makeAddCategoryHarness(nextID: 950, gateCreate: true)
        harness.viewModel.name = "🚕 택시"

        let save = Task { await harness.viewModel.save() }
        await waitUntil { harness.service.createStarted }
        // 요청이 떠 있는 동안 로그아웃 정리가 revision을 올린 경합.
        try await harness.store.clear()
        harness.service.releaseCreate()
        let outcome = await save.value

        #expect(outcome == .failed)
        #expect(harness.viewModel.name == "🚕 택시")
        #expect(harness.store.expenseCategories.isEmpty)
        #expect(harness.viewModel.isSaving == false)
    }
}

@MainActor
private struct AddCategoryHarness {
    let viewModel: CategoryAddViewModel
    let store: CustomCategoryStore
    let service: AddCategoryServiceStub
}

@MainActor
private func makeAddCategoryHarness(
    tab: EntryType = .expense,
    nextID: Int = 900,
    createError: Error? = nil,
    gateCreate: Bool = false,
    isOnline: Bool = true
) throws -> AddCategoryHarness {
    let service = AddCategoryServiceStub(
        nextID: nextID,
        createError: createError,
        gateCreate: gateCreate
    )
    let store = try CustomCategoryStore(
        service: service,
        cache: AddCategoryCacheStub(),
        authProvider: FakeAuthService()
    )
    let viewModel = CategoryAddViewModel(
        tab: tab,
        customCategoryStore: store,
        connectivity: FakeConnectivityMonitor(isOnline: isOnline)
    )
    return AddCategoryHarness(viewModel: viewModel, store: store, service: service)
}

@MainActor
private final class AddCategoryServiceStub: CustomCategoryServicing {
    private(set) var createdNames: [String] = []
    private(set) var createStarted = false

    private var nextID: Int
    private let createError: Error?
    private var gateCreate: Bool
    private var createContinuation: CheckedContinuation<Void, Never>?

    init(nextID: Int, createError: Error?, gateCreate: Bool) {
        self.nextID = nextID
        self.createError = createError
        self.gateCreate = gateCreate
    }

    func fetchCustomCategories(transactionType _: String) async throws -> [CategoryDTO] {
        []
    }

    func createCustomCategory(name: String, transactionType _: String) async throws -> CategoryDTO {
        createStarted = true
        createdNames.append(name)
        if gateCreate {
            await withCheckedContinuation { createContinuation = $0 }
        }
        if let createError {
            throw createError
        }
        let category = CategoryDTO(
            id: nextID,
            code: "CUSTOM",
            displayNameKo: name,
            displayNameEn: name,
            icon: nil,
            sortOrder: 1000
        )
        nextID += 1
        return category
    }

    func deleteCustomCategory(id _: Int) async throws {
        Issue.record("이 스위트에서 delete는 호출되지 않아야 한다")
    }

    func releaseCreate() {
        gateCreate = false
        createContinuation?.resume()
        createContinuation = nil
    }
}

@MainActor
private final class AddCategoryCacheStub: CustomCategoryCaching {
    private var categories: [CachedCustomCategory] = []

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
