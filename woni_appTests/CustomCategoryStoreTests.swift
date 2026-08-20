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
    @Test("음수 로컬과 양수 서버 id를 최신 생성순으로 정렬한다")
    func initialLoadUsesLocalFirstSortKey() throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 9, type: .expense, name: "서버 최신"),
            cachedCategory(id: -1, type: .expense, name: "로컬 이전", state: .pendingCreate),
            cachedCategory(id: 3, type: .expense, name: "서버 이전"),
            cachedCategory(id: -2, type: .expense, name: "로컬 최신", state: .pendingCreate)
        ])

        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        #expect(store.expenseCategories.map(\.id) == [-2, -1, 9, 3])
    }

    @Test("비회원에서도 create rename remove는 서버 없이 로컬 상태만 커밋한다")
    func localCRUDWorksWithoutMemberOrNetwork() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 10, type: .expense, name: "기존")
        ])
        let service = CustomCategoryServiceStub()
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        let createdID = try await store.create(name: "오프라인", type: .expense)
        try await store.rename(id: 10, name: "수정")
        try await store.remove(id: 10)

        #expect(createdID == -1)
        #expect(cache.categories.first { $0.id == -1 }?.syncState == .pendingCreate)
        #expect(cache.categories.first { $0.id == 10 }?.name == "수정")
        #expect(cache.categories.first { $0.id == 10 }?.syncState == .pendingDelete)
        #expect(store.expenseCategories.map(\.id) == [-1])
        #expect(service.createCalls.isEmpty)
        #expect(service.deletedIDs.isEmpty)
    }

    @Test("pendingCreate 이름 수정은 pendingCreate 상태를 유지한다")
    func renameKeepsPendingCreateState() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: -1, type: .income, name: "이전", state: .pendingCreate)
        ])
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        try await store.rename(id: -1, name: "새 이름")

        #expect(cache.categories.first?.name == "새 이름")
        #expect(cache.categories.first?.syncState == .pendingCreate)
        #expect(store.incomeCategories.first?.displayNameKo == "새 이름")
    }

    @Test("참조 없는 pendingCreate 삭제는 물리 삭제한다")
    func removeUnreferencedPendingCreateDeletesRow() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: -1, type: .expense, name: "로컬", state: .pendingCreate)
        ])
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        try await store.remove(id: -1)

        #expect(cache.categories.isEmpty)
        #expect(store.expenseCategories.isEmpty)
    }

    @Test("내역이 참조하는 pendingCreate 삭제는 pendingDelete로 남긴다")
    func removeReferencedPendingCreateKeepsPendingDelete() async throws {
        let cache = CustomCategoryCacheStub(
            categories: [cachedCategory(id: -1, type: .expense, name: "로컬", state: .pendingCreate)],
            referencedIDs: [-1]
        )
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        try await store.remove(id: -1)

        #expect(cache.categories.first?.syncState == .pendingDelete)
        #expect(store.expenseCategories.isEmpty)
    }

    @Test("이미 삭제됐거나 없는 카테고리의 rename·remove는 조용히 성공하지 않고 던진다")
    func renameAndRemoveThrowOnMissingOrDeletedTarget() async throws {
        let database = try AppDatabase.inMemory()
        let cache = CustomCategoryCacheRepository(database: database)
        try await cache.upsert(
            CachedCustomCategory(id: 9, transactionType: .expense, name: "지워짐", syncState: .deleted)
        )
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        await #expect(throws: CustomCategoryCacheError.categoryNotFound(id: 9)) {
            try await store.rename(id: 9, name: "새 이름")
        }
        await #expect(throws: CustomCategoryCacheError.categoryNotFound(id: 9)) {
            try await store.remove(id: 9)
        }
        await #expect(throws: CustomCategoryCacheError.categoryNotFound(id: 404)) {
            try await store.rename(id: 404, name: "없는 것")
        }
    }

    @Test("rename은 해당 카테고리를 쓴 내역 스냅샷을 일괄 갱신한다")
    func renameUpdatesTransactionSnapshots() async throws {
        let database = try AppDatabase.inMemory()
        let cache = CustomCategoryCacheRepository(database: database)
        let repository = TransactionRepository(database: database)
        try await cache.upsert(cachedCategory(id: 20, type: .expense, name: "이전"))
        let transaction = LocalTransaction(
            clientEntryID: UUID(),
            amount: Decimal(1000),
            currencyCode: "KRW",
            categoryID: 20,
            assetID: 1,
            transactionType: .expense,
            transactionDate: "2026-08-20"
        )
        try await repository.insert(transaction)
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        try await store.rename(id: 20, name: "새 이름")

        #expect(try await repository.transaction(clientEntryID: transaction.clientEntryID)?.categorySnapshot == "새 이름")
        #expect(try cache.loadAll().first?.syncState == .pendingUpdate)
    }

    @Test("활성 카테고리 100개면 생성이 막히고 pendingDelete는 한도에서 제외한다")
    func createEnforcesLocalLimitExcludingPendingDelete() async throws {
        var active = (1 ... 100).map { cachedCategory(id: $0, type: .expense, name: "\($0)") }
        let fullCache = CustomCategoryCacheStub(categories: active)
        let fullStore = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: fullCache,
            authProvider: FakeAuthService()
        )

        do {
            _ = try await fullStore.create(name: "초과", type: .expense)
            Issue.record("100개 상한 오류가 필요합니다.")
        } catch let APIError.server(code, _) {
            #expect(code == "CUSTOM_CATEGORY_LIMIT_EXCEEDED")
        }
        #expect(fullCache.categories.count == 100)

        active[0].syncState = .pendingDelete
        let deletingCache = CustomCategoryCacheStub(categories: active)
        let deletingStore = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: deletingCache,
            authProvider: FakeAuthService()
        )

        #expect(try await deletingStore.create(name: "허용", type: .income) == -1)
    }

    @Test("동시 create는 id 발급부터 upsert까지 직렬화해 서로 다른 음수 id를 만든다")
    func concurrentCreatesReceiveDistinctLocalIDs() async throws {
        let cache = CustomCategoryCacheStub(gateNextUpsert: true)
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        let first = Task { try await store.create(name: "첫째", type: .expense) }
        await waitUntil { cache.upsertStarted }
        let second = Task { try await store.create(name: "둘째", type: .expense) }
        cache.releaseUpsert()

        let firstID = try await first.value
        let secondID = try await second.value
        let ids = [firstID, secondID]
        #expect(Set(ids) == [-1, -2])
        #expect(Set(cache.categories.map(\.id)) == [-1, -2])
    }

    @Test("익명 세션에서도 refresh가 서버 목록을 갱신한다")
    func refreshRunsForAnonymousSession() async throws {
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let service = CustomCategoryServiceStub(expense: [categoryDTO(id: 7, name: "헬스")])
        let cache = CustomCategoryCacheStub()
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)

        await store.refresh()

        #expect(service.fetchCalls == [.expense, .income])
        #expect(cache.replaceCount == 1)
        #expect(store.expenseCategories.map(\.id) == [7])
    }

    @Test("신원이 없으면 refresh가 ensureIdentity를 먼저 호출한다")
    func refreshEnsuresIdentityBeforeFetching() async throws {
        let auth = FakeAuthService()
        let service = CustomCategoryServiceStub(identityAvailable: { auth.currentUserID != nil })
        let store = try CustomCategoryStore(
            service: service,
            cache: CustomCategoryCacheStub(),
            authProvider: auth
        )

        await store.refresh()

        #expect(auth.anonymousSignInCount == 1)
        #expect(service.fetchCalls == [.expense, .income])
        #expect(store.lastRefreshError == nil)
    }

    @Test("pendingDelete id가 서버 응답에 있어도 refresh는 PK 충돌 없이 보존한다")
    func refreshExcludesPendingIDsFromServerReplacement() async throws {
        let database = try AppDatabase.inMemory()
        let cache = CustomCategoryCacheRepository(database: database)
        try await cache.upsert(cachedCategory(
            id: 7,
            type: .expense,
            name: "삭제 대기",
            state: .pendingDelete
        ))
        let service = CustomCategoryServiceStub(expense: [
            categoryDTO(id: 7, name: "서버의 이전 이름"),
            categoryDTO(id: 8, name: "서버 신규")
        ])
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.refresh()

        #expect(store.lastRefreshError == nil)
        #expect(store.expenseCategories.map(\.id) == [8])
        let rows = try cache.loadAll()
        #expect(rows.first { $0.id == 7 }?.syncState == .pendingDelete)
        #expect(rows.first { $0.id == 8 }?.syncState == .synced)
    }

    @Test("늦은 refresh는 먼저 완료된 로컬 create 결과를 덮지 않는다")
    func lateRefreshCannotOverwriteCreate() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 1, type: .expense, name: "기존")
        ])
        let service = CustomCategoryServiceStub(
            expense: [categoryDTO(id: 1, name: "기존")],
            gateFetch: true
        )
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        let refresh = Task { await store.refresh() }
        await waitUntil { service.fetchStarted }
        #expect(try await store.create(name: "신규", type: .expense) == -1)
        service.releaseFetch()
        await refresh.value

        #expect(store.expenseCategories.map(\.id) == [-1, 1])
        #expect(cache.categories.contains { $0.id == -1 && $0.syncState == .pendingCreate })
    }

    @Test("refresh 실패는 기존 캐시를 유지하고 비차단 오류를 기록한다")
    func refreshFailureKeepsCachedState() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 1, type: .expense, name: "기존")
        ])
        let service = CustomCategoryServiceStub(fetchError: StoreTestError.requestFailed)
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.refresh()

        #expect(store.expenseCategories.map(\.id) == [1])
        #expect(cache.categories.map(\.id) == [1])
        #expect(store.lastRefreshError is StoreTestError)
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
    var fetchError: Error?
    var fetchCalls: [CatalogTransactionType] = []
    var createCalls: [(name: String, type: String)] = []
    var deletedIDs: [Int] = []
    var fetchStarted = false

    private var gateFetch: Bool
    private let identityAvailable: (() -> Bool)?
    private var fetchContinuation: CheckedContinuation<Void, Never>?

    init(
        expense: [CategoryDTO] = [],
        income: [CategoryDTO] = [],
        fetchError: Error? = nil,
        gateFetch: Bool = false,
        identityAvailable: (() -> Bool)? = nil
    ) {
        self.expense = expense
        self.income = income
        self.fetchError = fetchError
        self.gateFetch = gateFetch
        self.identityAvailable = identityAvailable
    }

    func fetchCustomCategories(transactionType: String) async throws -> [CategoryDTO] {
        if let identityAvailable, !identityAvailable() {
            throw StoreTestError.identityMissing
        }
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

    func createCustomCategory(name: String, transactionType: String) async throws -> CategoryDTO {
        createCalls.append((name, transactionType))
        throw StoreTestError.unexpectedServerMutation
    }

    func deleteCustomCategory(id: Int) async throws {
        deletedIDs.append(id)
        throw StoreTestError.unexpectedServerMutation
    }

    func releaseFetch() {
        gateFetch = false
        fetchContinuation?.resume()
        fetchContinuation = nil
    }
}

@MainActor
private final class CustomCategoryCacheStub: CustomCategoryCaching {
    var categories: [CachedCustomCategory]
    var replaceCount = 0
    var clearCount = 0
    var clearError: Error?
    var referencedIDs: Set<Int>

    private var gateNextUpsert: Bool
    private var upsertContinuation: CheckedContinuation<Void, Never>?
    private(set) var upsertStarted = false

    init(
        categories: [CachedCustomCategory] = [],
        referencedIDs: Set<Int> = [],
        gateNextUpsert: Bool = false
    ) {
        self.categories = categories
        self.referencedIDs = referencedIDs
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
        replaceCount += 1
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
        if categories[index].syncState == .pendingCreate, !referencedIDs.contains(id) {
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

    func nextLocalID() throws -> Int {
        min(categories.map(\.id).min() ?? 0, 0) - 1
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
        referencedIDs
    }

    func clearAll() async throws {
        clearCount += 1
        if let clearError {
            throw clearError
        }
        categories = []
    }

    func releaseUpsert() {
        upsertContinuation?.resume()
        upsertContinuation = nil
    }
}

private enum StoreTestError: Error {
    case requestFailed
    case identityMissing
    case unexpectedServerMutation
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
    name: String,
    state: CustomCategorySyncState = .synced
) -> CachedCustomCategory {
    CachedCustomCategory(id: id, transactionType: type, name: name, syncState: state)
}
