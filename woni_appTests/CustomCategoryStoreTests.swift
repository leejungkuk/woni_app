//
//  CustomCategoryStoreTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct CustomCategoryStoreTests {
    @Test("캐시는 타입별 id 오름차순으로 초기 목록을 복원한다")
    func initialLoadUsesCachedIDOrder() async throws {
        let database = try AppDatabase.inMemory()
        let cache = CustomCategoryCacheRepository(database: database)
        try await cache.replaceAll([
            cachedCategory(id: 9, type: .expense, name: "택시"),
            cachedCategory(id: 2, type: .income, name: "용돈"),
            cachedCategory(id: 3, type: .expense, name: "야식")
        ])

        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        #expect(store.expenseCategories.map(\.id) == [3, 9])
        #expect(store.expenseCategories.map(\.displayNameKo) == ["야식", "택시"])
        #expect(store.incomeCategories.map(\.id) == [2])
    }

    @Test("refresh 성공은 서버 목록으로 캐시와 메모리를 전량 교체한다")
    func refreshSuccessReplacesMemoryAndCache() async throws {
        let auth = try await signedInAuth()
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 1, type: .expense, name: "이전")
        ])
        let service = CustomCategoryServiceStub(
            expense: [categoryDTO(id: 7, name: "헬스")],
            income: [categoryDTO(id: 8, name: "보너스")]
        )
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        await store.refresh()

        #expect(store.expenseCategories.map(\.id) == [7])
        #expect(store.incomeCategories.map(\.id) == [8])
        #expect(store.lastRefreshError == nil)
        #expect(cache.categories.map(\.id) == [7, 8])
    }

    @Test("refresh 실패는 기존 캐시를 유지하고 비차단 오류를 기록한다")
    func refreshFailureKeepsCachedState() async throws {
        let auth = try await signedInAuth()
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 1, type: .expense, name: "기존")
        ])
        let service = CustomCategoryServiceStub(fetchError: StoreTestError.requestFailed)
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        await store.refresh()

        #expect(store.expenseCategories.map(\.id) == [1])
        #expect(cache.categories.map(\.id) == [1])
        #expect(store.lastRefreshError is StoreTestError)
    }

    @Test("세션 없음과 익명 세션에서는 refresh가 무동작이다", arguments: [false, true])
    func refreshSkipsSignedOutAndAnonymousSessions(hasAnonymousSession: Bool) async throws {
        let auth = FakeAuthService()
        if hasAnonymousSession {
            try await auth.ensureIdentity()
        }
        let service = CustomCategoryServiceStub()
        let cache = CustomCategoryCacheStub()
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        await store.refresh()

        #expect(service.fetchCalls.isEmpty)
        #expect(cache.replaceCount == 0)
    }

    @Test("create와 remove 성공은 메모리와 캐시에 함께 반영한다")
    func createAndRemoveUpdateMemoryAndCache() async throws {
        let auth = try await signedInAuth()
        let cache = CustomCategoryCacheStub()
        let service = CustomCategoryServiceStub(
            created: categoryDTO(id: 22, name: "야식")
        )
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        let id = try await store.create(name: "야식", type: .expense)

        #expect(id == 22)
        #expect(store.expenseCategories.map(\.id) == [22])
        #expect(cache.categories.map(\.id) == [22])

        try await store.remove(id: id)

        #expect(store.expenseCategories.isEmpty)
        #expect(cache.categories.isEmpty)
        #expect(service.deletedIDs == [22])
    }

    @Test("create 도중 revision이 바뀌면 stale 오류를 던지고 id를 반환하지 않는다")
    func createRevisionMismatchThrowsStaleOperation() async throws {
        let auth = try await signedInAuth()
        let cache = CustomCategoryCacheStub()
        let service = CustomCategoryServiceStub(
            created: categoryDTO(id: 31, name: "경합"),
            gateCreate: true
        )
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        let creation = Task { try await store.create(name: "경합", type: .expense) }
        await waitUntil { service.createStarted }
        try await store.clear()
        service.releaseCreate()

        do {
            _ = try await creation.value
            Issue.record("stale operation 오류가 필요합니다.")
        } catch CustomCategoryStoreError.staleOperation {
            #expect(store.expenseCategories.isEmpty)
            #expect(cache.categories.isEmpty)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("remove 404는 오류를 보존하고 refresh 결과로 수렴한다")
    func removeNotFoundRefreshesAndPreservesError() async throws {
        let auth = try await signedInAuth()
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 41, type: .expense, name: "사라짐")
        ])
        let service = CustomCategoryServiceStub(
            expense: [],
            income: [],
            deleteError: APIError.server(
                code: "CATEGORY_NOT_FOUND",
                message: "카테고리를 찾을 수 없습니다."
            )
        )
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        do {
            try await store.remove(id: 41)
            Issue.record("404 오류가 호출자에게 전파되어야 합니다.")
        } catch let APIError.server(code, _) {
            #expect(code == "CATEGORY_NOT_FOUND")
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }

        #expect(store.expenseCategories.isEmpty)
        #expect(cache.categories.isEmpty)
        #expect(service.fetchCalls == [.expense, .income])
        // 404는 던져진 오류로 표시한다 — lastRefreshError는 refresh 실패 전용이라 성공 수렴 후 nil.
        #expect(store.lastRefreshError == nil)
    }

    @Test("refresh가 먼저 커밋되면 진행 중이던 create는 stale로 끝나고 중복이 생기지 않는다")
    func refreshCommitInvalidatesInFlightCreate() async throws {
        let auth = try await signedInAuth()
        let cache = CustomCategoryCacheStub()
        let service = CustomCategoryServiceStub(
            expense: [categoryDTO(id: 2, name: "신규")],
            income: [],
            created: categoryDTO(id: 2, name: "신규"),
            gateCreate: true
        )
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        let creation = Task { try await store.create(name: "신규", type: .expense) }
        await waitUntil { service.createStarted }
        await store.refresh()
        service.releaseCreate()

        do {
            _ = try await creation.value
            Issue.record("stale operation 오류가 필요합니다.")
        } catch CustomCategoryStoreError.staleOperation {
            #expect(store.expenseCategories.map(\.id) == [2])
            #expect(cache.categories.map(\.id) == [2])
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("늦은 refresh는 먼저 완료된 create 결과를 덮지 않는다")
    func lateRefreshCannotOverwriteCreate() async throws {
        let auth = try await signedInAuth()
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 1, type: .expense, name: "기존")
        ])
        let service = CustomCategoryServiceStub(
            expense: [categoryDTO(id: 1, name: "기존")],
            income: [],
            created: categoryDTO(id: 2, name: "신규"),
            gateFetch: true
        )
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        let refresh = Task { await store.refresh() }
        await waitUntil { service.fetchStarted }
        _ = try await store.create(name: "신규", type: .expense)
        service.releaseFetch()
        await refresh.value

        #expect(store.expenseCategories.map(\.id) == [1, 2])
        #expect(cache.categories.map(\.id) == [1, 2])
    }

    @Test("늦은 refresh는 먼저 완료된 remove 결과를 되살리지 않는다")
    func lateRefreshCannotResurrectRemovedCategory() async throws {
        let auth = try await signedInAuth()
        let initial = [
            cachedCategory(id: 1, type: .expense, name: "기존"),
            cachedCategory(id: 2, type: .expense, name: "삭제")
        ]
        let cache = CustomCategoryCacheStub(categories: initial)
        let service = CustomCategoryServiceStub(
            expense: initial.map { categoryDTO(id: $0.id, name: $0.name) },
            income: [],
            gateFetch: true
        )
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        let refresh = Task { await store.refresh() }
        await waitUntil { service.fetchStarted }
        try await store.remove(id: 2)
        service.releaseFetch()
        await refresh.value

        #expect(store.expenseCategories.map(\.id) == [1])
        #expect(cache.categories.map(\.id) == [1])
    }

    @Test("stale refresh와 clear 뒤의 create가 겹쳐도 마지막 cache와 memory가 일치한다")
    func commitGatePreventsStaleCompensationFromOverwritingNewCreate() async throws {
        let auth = try await signedInAuth()
        let cache = CustomCategoryCacheStub(
            categories: [cachedCategory(id: 1, type: .expense, name: "이전")],
            gateNextReplace: true
        )
        let service = CustomCategoryServiceStub(
            expense: [categoryDTO(id: 1, name: "이전")],
            income: [],
            created: categoryDTO(id: 2, name: "신규")
        )
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        let refresh = Task { await store.refresh() }
        await waitUntil { cache.replaceStarted }

        let clearing = Task { try await store.clear() }
        await waitUntil { store.expenseCategories.isEmpty }
        let creation = Task { try await store.create(name: "신규", type: .expense) }

        cache.releaseReplace()
        await refresh.value
        try await clearing.value
        #expect(try await creation.value == 2)

        #expect(store.expenseCategories.map(\.id) == [2])
        #expect(cache.categories.map(\.id) == [2])
    }

    @Test("remove 404 대기 중 clear되면 이전 revision 오류와 refresh를 재주입하지 않는다")
    func removeNotFoundAfterClearIsStaleAndDoesNotRefresh() async throws {
        let auth = try await signedInAuth()
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 51, type: .expense, name: "이전 계정")
        ])
        let service = CustomCategoryServiceStub(
            deleteError: APIError.server(
                code: "CATEGORY_NOT_FOUND",
                message: "카테고리를 찾을 수 없습니다."
            ),
            gateDelete: true
        )
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        let removal = Task { try await store.remove(id: 51) }
        await waitUntil { service.deleteStarted }
        try await store.clear()
        service.releaseDelete()

        do {
            try await removal.value
            Issue.record("stale operation 오류가 필요합니다.")
        } catch CustomCategoryStoreError.staleOperation {
            #expect(store.lastRefreshError == nil)
            #expect(service.fetchCalls.isEmpty)
            #expect(cache.categories.isEmpty)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("clear는 메모리와 캐시를 함께 삭제한다")
    func clearDeletesMemoryAndCache() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 1, type: .expense, name: "지출"),
            cachedCategory(id: 2, type: .income, name: "수입")
        ])
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        try await store.clear()

        #expect(store.expenseCategories.isEmpty)
        #expect(store.incomeCategories.isEmpty)
        #expect(cache.categories.isEmpty)
        #expect(cache.clearCount == 1)
    }
}

@MainActor
private final class CustomCategoryServiceStub: CustomCategoryServicing {
    var expense: [CategoryDTO]
    var income: [CategoryDTO]
    var created: CategoryDTO
    var fetchError: Error?
    var deleteError: Error?
    var fetchCalls: [CatalogTransactionType] = []
    var deletedIDs: [Int] = []
    var fetchStarted = false
    var createStarted = false
    var deleteStarted = false

    private var gateFetch: Bool
    private var gateCreate: Bool
    private var gateDelete: Bool
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private var createContinuation: CheckedContinuation<Void, Never>?
    private var deleteContinuation: CheckedContinuation<Void, Never>?

    init(
        expense: [CategoryDTO] = [],
        income: [CategoryDTO] = [],
        created: CategoryDTO = categoryDTO(id: 999, name: "신규"),
        fetchError: Error? = nil,
        deleteError: Error? = nil,
        gateFetch: Bool = false,
        gateCreate: Bool = false,
        gateDelete: Bool = false
    ) {
        self.expense = expense
        self.income = income
        self.created = created
        self.fetchError = fetchError
        self.deleteError = deleteError
        self.gateFetch = gateFetch
        self.gateCreate = gateCreate
        self.gateDelete = gateDelete
    }

    func fetchCustomCategories(transactionType: String) async throws -> [CategoryDTO] {
        let type = try #require(CatalogTransactionType(rawValue: transactionType))
        fetchCalls.append(type)
        let result = type == .expense ? expense : income
        if gateFetch, type == .expense {
            fetchStarted = true
            await withCheckedContinuation { fetchContinuation = $0 }
        }
        if let fetchError {
            throw fetchError
        }
        return result
    }

    func createCustomCategory(name _: String, transactionType _: String) async throws -> CategoryDTO {
        if gateCreate {
            createStarted = true
            await withCheckedContinuation { createContinuation = $0 }
        }
        return created
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

    func releaseFetch() {
        gateFetch = false
        fetchContinuation?.resume()
        fetchContinuation = nil
    }

    func releaseCreate() {
        gateCreate = false
        createContinuation?.resume()
        createContinuation = nil
    }

    func releaseDelete() {
        gateDelete = false
        deleteContinuation?.resume()
        deleteContinuation = nil
    }
}

@MainActor
private final class CustomCategoryCacheStub: CustomCategoryCaching {
    var categories: [CachedCustomCategory]
    var replaceCount = 0
    var clearCount = 0
    var clearError: Error?

    private var gateNextReplace: Bool
    private var replaceContinuation: CheckedContinuation<Void, Never>?
    private(set) var replaceStarted = false

    init(categories: [CachedCustomCategory] = [], gateNextReplace: Bool = false) {
        self.categories = categories
        self.gateNextReplace = gateNextReplace
    }

    func load(for transactionType: CatalogTransactionType) throws -> [CachedCustomCategory] {
        categories
            .filter { $0.transactionType == transactionType }
            .sorted { $0.id < $1.id }
    }

    func replaceAll(_ categories: [CachedCustomCategory]) async throws {
        replaceCount += 1
        if gateNextReplace {
            gateNextReplace = false
            replaceStarted = true
            await withCheckedContinuation { replaceContinuation = $0 }
        }
        self.categories = categories.sorted { $0.id < $1.id }
    }

    func clearAll() async throws {
        clearCount += 1
        if let clearError {
            throw clearError
        }
        categories = []
    }

    func releaseReplace() {
        replaceContinuation?.resume()
        replaceContinuation = nil
    }
}

private enum StoreTestError: Error {
    case requestFailed
}

@MainActor
private func signedInAuth() async throws -> FakeAuthService {
    let auth = FakeAuthService()
    try await auth.signIn(.google)
    return auth
}

private func categoryDTO(id: Int, name: String) -> CategoryDTO {
    CategoryDTO(
        id: id,
        code: "CUSTOM",
        displayNameKo: name,
        displayNameEn: name,
        icon: nil,
        sortOrder: 1000
    )
}

private func cachedCategory(
    id: Int,
    type: CatalogTransactionType,
    name: String
) -> CachedCustomCategory {
    CachedCustomCategory(id: id, transactionType: type, name: name)
}
