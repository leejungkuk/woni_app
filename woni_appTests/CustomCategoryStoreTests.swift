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

extension CustomCategoryStoreTests {
    @Test("pendingCreate를 서버 id로 재매핑하고 체인을 평탄화한다")
    func flushPendingCreatesRemapsIDsAndFlattensChains() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: -1, type: .expense, name: "로컬", state: .pendingCreate)
        ])
        let service = CustomCategoryServiceStub(created: [categoryDTO(id: 40, name: "로컬")])
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPending()
        store.recordRemap(from: 40, to: 70)

        #expect(service.createCalls.map(\.name) == ["로컬"])
        #expect(cache.categories == [cachedCategory(id: 40, type: .expense, name: "로컬")])
        #expect(store.resolvedID(for: -1) == 70)
        #expect(store.resolvedID(for: 40) == 70)
    }

    @Test("create 403은 큐를 멈추고 로컬 행과 남은 개수 안내를 보존한다")
    func flushPendingStopsAtLimitExceeded() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: -1, type: .expense, name: "첫째", state: .pendingCreate),
            cachedCategory(id: -2, type: .expense, name: "둘째", state: .pendingCreate)
        ])
        let service = CustomCategoryServiceStub(
            createError: APIError.server(
                code: "CUSTOM_CATEGORY_LIMIT_EXCEEDED",
                message: "limit"
            )
        )
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPending()

        #expect(service.createCalls.count == 1)
        #expect(cache.categories.allSatisfy { $0.syncState == .pendingCreate })
        #expect(store.lastSyncNotice == .limitExceeded(pendingCreateCount: 2))
    }

    /// ①은 개수 한도로 막혀도 ②는 개수를 늘리지 않는다. 여기서 큐 전체를 세우면 무관한 이름 변경이
    /// 생성 실패가 풀릴 때까지 영영 서버에 안 올라가 기기 간 표시가 갈린다.
    @Test("create 403으로 ①이 멈춰도 무관한 pendingUpdate는 서버에 반영된다")
    func flushPendingRunsUpdateQueueAfterLimitExceeded() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: -1, type: .expense, name: "새것", state: .pendingCreate),
            cachedCategory(id: 8, type: .income, name: "바뀐 이름", state: .pendingUpdate)
        ])
        let service = CustomCategoryServiceStub(
            createError: APIError.server(
                code: "CUSTOM_CATEGORY_LIMIT_EXCEEDED",
                message: "limit"
            )
        )
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPending()

        #expect(service.updateCalls.map(\.id) == [8])
        #expect(cache.categories.first { $0.id == 8 }?.syncState == .synced)
        #expect(cache.categories.first { $0.id == -1 }?.syncState == .pendingCreate)
        #expect(store.lastSyncNotice == .limitExceeded(pendingCreateCount: 1))
    }

    @Test("create 전송 오류로 ①이 멈춰도 무관한 pendingUpdate는 서버에 반영된다")
    func flushPendingRunsUpdateQueueAfterCreateTransportError() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: -1, type: .expense, name: "새것", state: .pendingCreate),
            cachedCategory(id: 8, type: .income, name: "바뀐 이름", state: .pendingUpdate)
        ])
        let service = CustomCategoryServiceStub(createError: StoreTestError.requestFailed)
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPending()

        #expect(service.updateCalls.map(\.id) == [8])
        #expect(cache.categories.first { $0.id == 8 }?.syncState == .synced)
        #expect(cache.categories.first { $0.id == -1 }?.syncState == .pendingCreate)
    }

    /// 로그인은 신원을 먼저 바꾸고 카테고리 이관을 나중에 한다. 그 사이에 도착한 목록 응답을
    /// 반영하면 익명 `synced` 행이 지워지고, 그 행을 참조하던 내역이 이관 대상에서 사라진다.
    @Test("신원이 바뀐 뒤 도착한 목록 응답은 익명 카테고리 행을 지우지 않는다")
    func refreshDiscardsResponseWhenIdentityChangedMidFlight() async throws {
        let auth = FakeAuthService()
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 501, type: .expense, name: "익명 것")
        ])
        let service = CustomCategoryServiceStub(
            expense: [categoryDTO(id: 900, name: "회원 것")],
            gateFetch: true
        )
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: auth
        )

        let refresh = Task { await store.refresh() }
        await waitUntil { service.fetchStarted }
        try await auth.signIn(.google)
        service.releaseFetch()
        await refresh.value

        #expect(cache.categories == [cachedCategory(id: 501, type: .expense, name: "익명 것")])
    }

    @Test("남은 큐가 전부 삭제 대기면 403은 큐만 멈추고 '0개' 안내를 띄우지 않는다")
    func flushPendingSkipsLimitNoticeWhenOnlyDeletesRemain() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: -1, type: .expense, name: "지울 것", state: .pendingDelete),
            cachedCategory(id: -2, type: .expense, name: "지울 것 둘", state: .pendingDelete)
        ])
        let service = CustomCategoryServiceStub(
            createError: APIError.server(
                code: "CUSTOM_CATEGORY_LIMIT_EXCEEDED",
                message: "limit"
            )
        )
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPending()

        #expect(service.createCalls.count == 1)
        // 사용자가 이미 지운 카테고리라 화면에 보이지 않는다 — "0개가 동기화되지 않았어요"는 틀린 안내다.
        #expect(store.lastSyncNotice == nil)
        #expect(cache.categories.allSatisfy { $0.syncState == .pendingDelete })
    }

    @Test("아직 올라가지 않은 내역이 참조하는 카테고리는 서버 삭제를 보류하고, 무관한 것은 지운다")
    func pendingDeleteWaitsOnlyForItsOwnUnpushedEntries() async throws {
        let cache = CustomCategoryCacheStub(
            categories: [
                cachedCategory(id: 9, type: .expense, name: "내역 있음", state: .pendingDelete),
                cachedCategory(id: 11, type: .expense, name: "무관", state: .pendingDelete)
            ],
            // 9만 아직 서버로 안 올라간 내역이 참조한다.
            pendingPushIDs: [9]
        )
        let service = CustomCategoryServiceStub()
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPendingDeletes()

        // 9를 먼저 지우면 그 내역이 push될 때 서버가 사용 불가 카테고리로 보고 영영 거부한다.
        #expect(service.deletedIDs == [11])
        #expect(cache.categories.first { $0.id == 9 }?.syncState == .pendingDelete)
        #expect(cache.categories.contains { $0.id == 11 } == false)
    }

    @Test("delete 404는 pendingDelete를 deleted로 수렴시키고 알림을 남긴다")
    func flushPendingDeleteNotFoundConvergesToDeleted() async throws {
        let cache = CustomCategoryCacheStub(
            categories: [cachedCategory(id: 9, type: .expense, name: "삭제", state: .pendingDelete)],
            referencedIDs: [9]
        )
        let service = CustomCategoryServiceStub(
            deleteError: APIError.server(code: "CATEGORY_NOT_FOUND", message: "missing")
        )
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPendingDeletes()

        #expect(service.deletedIDs == [9])
        #expect(cache.categories.first?.syncState == .deleted)
        #expect(store.lastSyncNotice == .categoryNotFound)
    }

    @Test("서버 delete 성공은 참조 없는 pendingDelete 행을 물리 삭제한다")
    func flushPendingDeleteRemovesUnreferencedRow() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 9, type: .expense, name: "삭제", state: .pendingDelete)
        ])
        let service = CustomCategoryServiceStub()
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPendingDeletes()

        #expect(service.deletedIDs == [9])
        #expect(cache.categories.isEmpty)
    }

    @Test("pendingUpdate는 PUT 성공 후 synced로 소진된다")
    func flushPendingUpdateMarksRowSynced() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 8, type: .income, name: "수정", state: .pendingUpdate)
        ])
        let service = CustomCategoryServiceStub()
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPending()

        #expect(service.updateCalls.count == 1)
        #expect(service.updateCalls.first?.id == 8)
        #expect(service.updateCalls.first?.name == "수정")
        #expect(cache.categories.first?.syncState == .synced)
    }

    @Test("pendingUpdate PUT 404는 행을 제거하고 알림을 남긴다")
    func flushPendingUpdateNotFoundRemovesRow() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 8, type: .income, name: "수정", state: .pendingUpdate)
        ])
        let service = CustomCategoryServiceStub(
            updateError: APIError.server(code: "CATEGORY_NOT_FOUND", message: "missing")
        )
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPending()

        #expect(service.updateCalls.count == 1)
        #expect(service.updateCalls.first?.id == 8)
        #expect(service.updateCalls.first?.name == "수정")
        #expect(cache.categories.isEmpty)
        #expect(store.lastSyncNotice == .categoryNotFound)
    }

    /// ①의 POST와 달리 PUT은 응답에서 받아 쓸 값이 없다. 게이트를 쥔 채 기다리면
    /// 그동안 사용자의 저장이 통째로 멈춘다.
    @Test("PUT 응답을 기다리는 동안에도 로컬 저장은 진행된다")
    func localWriteProceedsWhileUpdateInFlight() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 8, type: .income, name: "수정", state: .pendingUpdate)
        ])
        let service = CustomCategoryServiceStub(gateUpdate: true)
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        let flush = Task { await store.flushPending() }
        await waitUntil { service.updateStarted }
        // 저장을 여기서 그대로 await하면, 게이트를 쥔 채 기다리는 회귀가 났을 때 테스트가
        // 실패하는 대신 영원히 멈춘다. 별도 Task로 띄워야 유계 대기가 실패로 남긴다.
        let write = Task { try await store.create(name: "그 사이 추가", type: .expense) }
        await waitUntil { cache.categories.contains { $0.name == "그 사이 추가" } }

        service.releaseUpdate()
        let createdID = try await write.value
        await flush.value

        #expect(createdID < 0)
        #expect(cache.categories.contains { $0.id == createdID && $0.name == "그 사이 추가" })
        #expect(cache.categories.first { $0.id == 8 }?.syncState == .synced)
    }

    /// 게이트 밖에서 기다리는 대가로 "보내는 사이에 또 바뀌는" 창이 생긴다. 그때 synced로
    /// 내리면 최신 이름이 큐에서 빠져 영영 안 올라간다.
    @Test("PUT을 보내는 사이에 이름이 또 바뀌면 큐에 남겨 다시 올린다")
    func renameDuringUpdateFlushStaysQueued() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 8, type: .income, name: "이전", state: .pendingUpdate)
        ])
        let service = CustomCategoryServiceStub(gateUpdate: true)
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        let flush = Task { await store.flushPending() }
        await waitUntil { service.updateStarted }
        let rename = Task { try await store.rename(id: 8, name: "새 이름") }
        await waitUntil { cache.categories.first { $0.id == 8 }?.name == "새 이름" }

        service.releaseUpdate()
        try await rename.value
        await flush.value

        #expect(service.updateCalls.map(\.name) == ["이전"])
        #expect(cache.categories.first { $0.id == 8 }?.syncState == .pendingUpdate)
        #expect(cache.categories.first { $0.id == 8 }?.name == "새 이름")
    }

    /// 삭제는 이름을 그대로 두고 상태만 바꾼다. 재검사가 이름만 본다면 삭제 대기 행을
    /// synced로 되돌려 사용자의 삭제 요청이 조용히 사라진다.
    @Test("PUT을 보내는 사이에 삭제하면 삭제 의도가 살아남는다")
    func removeDuringUpdateFlushKeepsDeleteIntent() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 8, type: .income, name: "수정", state: .pendingUpdate)
        ])
        let service = CustomCategoryServiceStub(gateUpdate: true)
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        let flush = Task { await store.flushPending() }
        await waitUntil { service.updateStarted }
        let remove = Task { try await store.remove(id: 8) }
        await waitUntil { cache.categories.first { $0.id == 8 }?.syncState == .pendingDelete }

        service.releaseUpdate()
        try await remove.value
        await flush.value

        #expect(cache.categories.first { $0.id == 8 }?.syncState == .pendingDelete)
        await store.flushPendingDeletes()
        #expect(service.deletedIDs == [8])
        #expect(cache.categories.isEmpty)
    }

    @Test("pendingUpdate PUT 전송 오류는 큐에 남겨 재시도한다")
    func flushPendingUpdateTransportFailureStaysQueued() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 8, type: .income, name: "수정", state: .pendingUpdate)
        ])
        let service = CustomCategoryServiceStub(updateError: StoreTestError.requestFailed)
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )

        await store.flushPending()

        #expect(service.updateCalls.count == 1)
        #expect(service.updateCalls.first?.id == 8)
        #expect(service.updateCalls.first?.name == "수정")
        #expect(cache.categories.first?.syncState == .pendingUpdate)
        #expect(store.lastSyncNotice == nil)
    }

    @Test("update 404 수렴 처리는 pendingUpdate 행을 제거한다")
    func pendingUpdateNotFoundRemovesRow() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 8, type: .income, name: "수정", state: .pendingUpdate)
        ])
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        try await store.resolveCategoryNotFound(id: 8)

        #expect(cache.categories.isEmpty)
        #expect(store.lastSyncNotice == .categoryNotFound)
    }

    @Test("주입한 local write gate가 중단 오류를 내면 create는 로컬에 쓰지 않는다")
    func createUsesConfiguredLocalWriteGate() async throws {
        let cache = CustomCategoryCacheStub()
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )
        store.configure { _ in throw SyncEngineError.localWritesSuspended }

        await #expect(throws: SyncEngineError.localWritesSuspended) {
            _ = try await store.create(name: "차단", type: .expense)
        }
        #expect(cache.categories.isEmpty)
    }

    @Test("POST 중 rename은 재매핑 뒤 pendingUpdate로 보존된다")
    func renameDuringCreateFlushIsNotLost() async throws {
        let cache = CustomCategoryCacheStub()
        let service = CustomCategoryServiceStub(
            created: [categoryDTO(id: 40, name: "이전")],
            gateCreate: true
        )
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        let localID = try await store.create(name: "이전", type: .expense)

        let flush = Task { await store.flushPending() }
        await waitUntil { service.createStarted }
        let rename = Task { try await store.rename(id: localID, name: "새 이름") }
        service.releaseCreate()
        await flush.value
        try await rename.value

        #expect(cache.categories == [
            cachedCategory(id: 40, type: .expense, name: "새 이름", state: .pendingUpdate)
        ])
    }

    @Test("POST 중 remove는 재매핑 뒤 pendingDelete로 보존돼 서버 고아를 만들지 않는다")
    func removeDuringCreateFlushBecomesPendingDelete() async throws {
        let cache = CustomCategoryCacheStub()
        let service = CustomCategoryServiceStub(
            created: [categoryDTO(id: 40, name: "삭제")],
            gateCreate: true
        )
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        let localID = try await store.create(name: "삭제", type: .expense)

        let flush = Task { await store.flushPending() }
        await waitUntil { service.createStarted }
        let remove = Task { try await store.remove(id: localID) }
        service.releaseCreate()
        await flush.value
        try await remove.value

        #expect(cache.categories == [
            cachedCategory(id: 40, type: .expense, name: "삭제", state: .pendingDelete)
        ])
        await store.flushPendingDeletes()
        #expect(service.deletedIDs == [40])
        #expect(cache.categories.isEmpty)
    }
}

// MARK: - 순서 재배치

extension CustomCategoryStoreTests {
    @Test("sortOrder가 1차 키이고 값이 같을 때만 기존 생성순 키로 갈린다")
    func sortUsesSortOrderBeforeCreationKey() throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 5, type: .expense, name: "재정렬 둘째", sortOrder: 1002),
            cachedCategory(id: 3, type: .expense, name: "재정렬 첫째", sortOrder: 1001),
            cachedCategory(id: 9, type: .expense, name: "미정렬 서버"),
            cachedCategory(id: -1, type: .expense, name: "미정렬 로컬", state: .pendingCreate)
        ])

        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        #expect(store.expenseCategories.map(\.id) == [-1, 9, 3, 5])
    }

    @Test("reorder는 순서와 전송 큐를 로컬에 함께 커밋하고 PUT은 보내지 않는다")
    func reorderCommitsOrderAndQueueWithoutSending() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 10, type: .expense, name: "먼저 만든 것"),
            cachedCategory(id: 20, type: .expense, name: "나중 만든 것")
        ])
        let service = CustomCategoryServiceStub()
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        #expect(store.expenseCategories.map(\.id) == [20, 10])

        try await store.reorder(orderedIDs: [10, 20], type: .expense)

        #expect(store.expenseCategories.map(\.id) == [10, 20])
        #expect(cache.categories.first { $0.id == 10 }?.sortOrder == 1001)
        #expect(cache.orderQueue == [.expense])
        // 전송은 로컬 커밋이 예약한 push 경로가 맡는다 — 게이트 밖에서 직접 쏘지 않는다.
        #expect(service.reorderCalls.isEmpty)
    }

    @Test("로컬 쓰기가 거부되면 reorder는 순서도 큐도 남기지 않는다")
    func reorderRejectedByLocalWriteGateWritesNothing() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 10, type: .expense, name: "먼저 만든 것"),
            cachedCategory(id: 20, type: .expense, name: "나중 만든 것")
        ])
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )
        store.configure { _ in throw SyncEngineError.localWritesSuspended }

        await #expect(throws: SyncEngineError.localWritesSuspended) {
            try await store.reorder(orderedIDs: [10, 20], type: .expense)
        }
        #expect(cache.orderQueue.isEmpty)
        #expect(store.expenseCategories.map(\.id) == [20, 10])
    }

    @Test("커밋 시점 목록 구성이 달라지면 reorder는 staleOperation으로 던진다")
    func reorderThrowsWhenListComposisionChanged() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 10, type: .expense, name: "먼저 만든 것"),
            cachedCategory(id: 20, type: .expense, name: "나중 만든 것")
        ])
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        // 드래그하는 사이 다른 기기 것이 내려왔거나(추가), 다른 화면에서 지워졌다(누락).
        await #expect(throws: CustomCategoryStoreError.staleOperation) {
            try await store.reorder(orderedIDs: [10, 20, 30], type: .expense)
        }
        await #expect(throws: CustomCategoryStoreError.staleOperation) {
            try await store.reorder(orderedIDs: [10], type: .expense)
        }
        #expect(cache.orderQueue.isEmpty)
        #expect(store.expenseCategories.map(\.id) == [20, 10])
    }

    /// `clear()`는 게이트 밖에서 lifecycle을 올린다. 가드가 없으면 쓰기가 진행되는 사이 계정이
    /// 바뀌어도 옛 화면의 순서가 새 lifecycle 캐시에 남는다.
    ///
    /// 끼어드는 지점은 캐시 스텁 게이트로 만든다. `configure`에 넘긴 클로저 안에서 MainActor
    /// 격리된 `store.clear()`를 await 하면 CI 툴체인(Xcode 26.3)에서 async 재개 시 SIGBUS로
    /// 죽는다(실측 2026-08-21, xcresult 크래시 심볼이 그 클로저를 지목).
    @Test("쓰기 도중 clear가 끼어들면 reorder는 새 캐시를 건드리지 않는다")
    func reorderThrowsWhenLifecycleChangedWhileWaiting() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 10, type: .expense, name: "먼저 만든 것"),
            cachedCategory(id: 20, type: .expense, name: "나중 만든 것")
        ], gateNextApplyOrder: true)
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )

        let reorder = Task { try await store.reorder(orderedIDs: [10, 20], type: .expense) }
        await waitUntil { cache.applyOrderStarted }

        // clear는 lifecycle과 메모리를 게이트 밖에서 먼저 비우고, 캐시 삭제만 FIFO 뒤에 선다.
        let clear = Task { try await store.clear() }
        await waitUntil { store.expenseCategories.isEmpty }
        cache.releaseApplyOrder()

        await #expect(throws: CustomCategoryStoreError.staleOperation) {
            try await reorder.value
        }
        try await clear.value
        #expect(cache.categories.isEmpty)
        #expect(cache.orderQueue.isEmpty)
    }

    /// R7 — 서버 기본 규칙과 같다: 미정렬 1000 < 재정렬 1001+.
    @Test("재정렬 뒤 새로 만든 카테고리가 맨 앞에 온다")
    func createdCategoryAfterReorderComesFirst() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 10, type: .expense, name: "먼저 만든 것"),
            cachedCategory(id: 20, type: .expense, name: "나중 만든 것")
        ])
        let store = try CustomCategoryStore(
            service: CustomCategoryServiceStub(),
            cache: cache,
            authProvider: FakeAuthService()
        )
        try await store.reorder(orderedIDs: [10, 20], type: .expense)

        let createdID = try await store.create(name: "새 카테고리", type: .expense)

        #expect(store.expenseCategories.map(\.id) == [createdID, 10, 20])
        #expect(cache.categories.first { $0.id == createdID }?.sortOrder == 1000)
    }

    @Test("refresh는 큐 없는 타입만 서버 순서를 채택하고 큐에 있는 타입은 로컬 순서를 지킨다")
    func refreshAdoptsServerOrderOnlyForUnqueuedType() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 1, type: .expense, name: "지출 A"),
            cachedCategory(id: 2, type: .expense, name: "지출 B"),
            cachedCategory(id: 3, type: .income, name: "수입 C"),
            cachedCategory(id: 4, type: .income, name: "수입 D")
        ])
        let service = CustomCategoryServiceStub(
            expense: [
                categoryDTO(id: 1, name: "지출 A", sortOrder: 1002),
                categoryDTO(id: 2, name: "지출 B", sortOrder: 1001)
            ],
            income: [
                categoryDTO(id: 3, name: "수입 C", sortOrder: 1001),
                categoryDTO(id: 4, name: "수입 D", sortOrder: 1002)
            ]
        )
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        try await store.reorder(orderedIDs: [1, 2], type: .expense)

        await store.refresh()

        // 아직 못 올린 드래그가 서버 순서를 이긴다(R4).
        #expect(store.expenseCategories.map(\.id) == [1, 2])
        // 큐가 없는 타입은 서버 순서를 그대로 받는다 — id DESC 폴백이면 [4, 3]이 된다.
        #expect(store.incomeCategories.map(\.id) == [3, 4])
    }

    @Test("서버 id가 없는 행이 남아 있으면 순서를 보내지 않고 큐를 유지한다")
    func flushPendingOrderWaitsForServerIDs() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 5, type: .expense, name: "서버 것"),
            cachedCategory(id: -1, type: .expense, name: "로컬 것", state: .pendingCreate)
        ])
        let service = CustomCategoryServiceStub(createError: StoreTestError.requestFailed)
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        try await store.reorder(orderedIDs: [5, -1], type: .expense)

        await store.flushPending()

        #expect(service.reorderCalls.isEmpty)
        #expect(cache.orderQueue == [.expense])
    }

    /// 큐에 타입이 남았는데 그 타입 행이 전부 사라진 경우다. 큐를 비우지 않으면 push가
    /// 사이클마다 헛돈다.
    @Test("큐에 남은 타입의 카테고리가 모두 사라지면 전송 없이 큐만 비운다")
    func flushPendingOrderDrainsQueueWhenNothingToSend() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 5, type: .expense, name: "곧 지울 것")
        ])
        let service = CustomCategoryServiceStub()
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        try await store.reorder(orderedIDs: [5], type: .expense)
        try await store.remove(id: 5)

        await store.flushPending()

        #expect(service.reorderCalls.isEmpty)
        #expect(cache.orderQueue.isEmpty)
    }

    @Test("생성이 끝나면 같은 사이클에서 서버 id로 순서를 보낸다")
    func flushPendingOrderSendsAfterCreateInSameCycle() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 5, type: .expense, name: "서버 것"),
            cachedCategory(id: -1, type: .expense, name: "로컬 것", state: .pendingCreate)
        ])
        let service = CustomCategoryServiceStub(created: [categoryDTO(id: 40, name: "로컬 것")])
        service.reorderResponse = [
            categoryDTO(id: 5, name: "서버 것", sortOrder: 1001),
            categoryDTO(id: 40, name: "로컬 것", sortOrder: 1002)
        ]
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        try await store.reorder(orderedIDs: [5, -1], type: .expense)

        await store.flushPending()

        #expect(service.reorderCalls.map(\.orderedIDs) == [[5, 40]])
        #expect(service.reorderCalls.map(\.type) == ["EXPENSE"])
        #expect(store.expenseCategories.map(\.id) == [5, 40])
        #expect(cache.orderQueue.isEmpty)
    }

    /// 순서는 타입 단위 계약인데 큐 루프는 타입 구분 없이 돈다.
    @Test("순서 전송은 큐에 있는 타입만, 지출·수입 양쪽을 모두 처리한다")
    func flushPendingOrderCoversBothTypes() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 1, type: .expense, name: "지출 A"),
            cachedCategory(id: 2, type: .expense, name: "지출 B"),
            cachedCategory(id: 3, type: .income, name: "수입 C"),
            cachedCategory(id: 4, type: .income, name: "수입 D")
        ])
        let service = CustomCategoryServiceStub()
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        try await store.reorder(orderedIDs: [3, 4], type: .income)

        await store.flushPending()

        #expect(service.reorderCalls.map(\.type) == ["INCOME"])

        try await store.reorder(orderedIDs: [1, 2], type: .expense)
        try await store.reorder(orderedIDs: [4, 3], type: .income)
        await store.flushPending()

        #expect(service.reorderCalls.map(\.type) == ["INCOME", "EXPENSE", "INCOME"])
        #expect(cache.orderQueue.isEmpty)
    }

    /// 게이트 밖에서 기다리는 대가로 "보내는 사이에 또 바뀌는" 창이 생긴다. 그때 응답을 반영하면
    /// 최신 순서가 큐에서 빠져 영영 안 올라간다.
    @Test("보내는 사이에 순서가 또 바뀌면 응답을 반영하지 않고 큐를 유지한다")
    func reorderDuringOrderFlushStaysQueued() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 10, type: .expense, name: "먼저 만든 것"),
            cachedCategory(id: 20, type: .expense, name: "나중 만든 것")
        ])
        let service = CustomCategoryServiceStub(gateReorder: true)
        service.reorderResponse = [
            categoryDTO(id: 10, name: "먼저 만든 것", sortOrder: 1001),
            categoryDTO(id: 20, name: "나중 만든 것", sortOrder: 1002)
        ]
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        try await store.reorder(orderedIDs: [10, 20], type: .expense)

        let flush = Task { await store.flushPending() }
        await waitUntil { service.reorderStarted }
        let second = Task { try await store.reorder(orderedIDs: [20, 10], type: .expense) }
        await waitUntil { store.expenseCategories.map(\.id) == [20, 10] }

        service.releaseReorder()
        try await second.value
        await flush.value

        #expect(service.reorderCalls.map(\.orderedIDs) == [[10, 20]])
        #expect(store.expenseCategories.map(\.id) == [20, 10])
        #expect(cache.orderQueue == [.expense])
    }

    @Test("순서 PUT 404는 큐를 유지한 채 refresh를 한 번 돌린다")
    func flushPendingOrderNotFoundRefreshesOnce() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 10, type: .expense, name: "먼저 만든 것"),
            cachedCategory(id: 20, type: .expense, name: "다른 기기가 지운 것")
        ])
        let service = CustomCategoryServiceStub(expense: [categoryDTO(id: 10, name: "먼저 만든 것")])
        service.reorderError = APIError.server(code: "CATEGORY_NOT_FOUND", message: "missing")
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        try await store.reorder(orderedIDs: [10, 20], type: .expense)

        await store.flushPending()

        #expect(service.reorderCalls.count == 1)
        // refresh 없이 큐만 유지하면 같은 404가 영구히 반복된다.
        #expect(service.fetchCalls == [.expense, .income])
        #expect(store.expenseCategories.map(\.id) == [10])
        #expect(cache.orderQueue == [.expense])
    }

    @Test("순서 PUT 전송 오류는 큐를 유지하고 뒤따르는 이름 큐를 막지 않는다")
    func flushPendingOrderTransportFailureStaysQueued() async throws {
        let cache = CustomCategoryCacheStub(categories: [
            cachedCategory(id: 10, type: .expense, name: "먼저 만든 것"),
            cachedCategory(id: 20, type: .expense, name: "나중 만든 것"),
            cachedCategory(id: 8, type: .income, name: "바뀐 이름", state: .pendingUpdate)
        ])
        let service = CustomCategoryServiceStub()
        service.reorderError = StoreTestError.requestFailed
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        try await store.reorder(orderedIDs: [10, 20], type: .expense)

        await store.flushPending()

        #expect(cache.orderQueue == [.expense])
        #expect(store.expenseCategories.map(\.id) == [10, 20])
        #expect(service.updateCalls.map(\.id) == [8])
        #expect(cache.categories.first { $0.id == 8 }?.syncState == .synced)
        #expect(store.lastSyncNotice == nil)
    }

    /// 큐가 남지 않으면 새 계정에 카테고리는 다시 만들어지되 순서만 서버 기본값으로 남아
    /// 기기 간에 갈린다.
    @Test("계정 전환은 재생성 대상 타입의 순서 큐를 남겨 새 서버 id로 다시 올린다")
    func accountSwitchKeepsOrderQueueForRecreatedType() async throws {
        let database = try AppDatabase.inMemory()
        let cache = CustomCategoryCacheRepository(database: database)
        try await cache.upsert(cachedCategory(id: 10, type: .expense, name: "먼저 만든 것"))
        try await cache.upsert(cachedCategory(id: 20, type: .expense, name: "나중 만든 것"))
        let service = CustomCategoryServiceStub(created: [
            categoryDTO(id: 40, name: "나중 만든 것"),
            categoryDTO(id: 41, name: "먼저 만든 것")
        ])
        let store = try CustomCategoryStore(
            service: service,
            cache: cache,
            authProvider: FakeAuthService()
        )
        try await store.reorder(orderedIDs: [10, 20], type: .expense)

        try await store.resetForAccountSwitch()
        await store.flushPending()

        #expect(service.reorderCalls.map(\.orderedIDs) == [[41, 40]])
        #expect(try cache.pendingOrderTypes().isEmpty)
    }
}

@MainActor
private final class CustomCategoryServiceStub: CustomCategoryServicing {
    var expense: [CategoryDTO]
    var income: [CategoryDTO]
    var fetchError: Error?
    var fetchCalls: [CatalogTransactionType] = []
    var createCalls: [(name: String, type: String)] = []
    var updateCalls: [(id: Int, name: String)] = []
    var reorderCalls: [(orderedIDs: [Int], type: String)] = []
    var reorderResponse: [CategoryDTO] = []
    var reorderError: Error?
    var deletedIDs: [Int] = []
    var fetchStarted = false

    private var gateFetch: Bool
    private var gateCreate: Bool
    private var gateUpdate: Bool
    private var gateReorder: Bool
    private var created: [CategoryDTO]
    private let createError: Error?
    private let updateError: Error?
    private let deleteError: Error?
    private let identityAvailable: (() -> Bool)?
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private var createContinuation: CheckedContinuation<Void, Never>?
    private var updateContinuation: CheckedContinuation<Void, Never>?
    private var reorderContinuation: CheckedContinuation<Void, Never>?
    private(set) var createStarted = false
    private(set) var updateStarted = false
    private(set) var reorderStarted = false

    init(
        expense: [CategoryDTO] = [],
        income: [CategoryDTO] = [],
        fetchError: Error? = nil,
        gateFetch: Bool = false,
        identityAvailable: (() -> Bool)? = nil,
        created: [CategoryDTO] = [],
        createError: Error? = nil,
        updateError: Error? = nil,
        deleteError: Error? = nil,
        gateCreate: Bool = false,
        gateUpdate: Bool = false,
        gateReorder: Bool = false
    ) {
        self.expense = expense
        self.income = income
        self.fetchError = fetchError
        self.gateFetch = gateFetch
        self.identityAvailable = identityAvailable
        self.gateCreate = gateCreate
        self.gateUpdate = gateUpdate
        self.gateReorder = gateReorder
        self.created = created
        self.createError = createError
        self.updateError = updateError
        self.deleteError = deleteError
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
        if gateCreate {
            gateCreate = false
            createStarted = true
            await withCheckedContinuation { createContinuation = $0 }
        }
        if let createError {
            throw createError
        }
        guard !created.isEmpty else {
            throw StoreTestError.unexpectedServerMutation
        }
        return created.removeFirst()
    }

    func updateCustomCategory(id: Int, name: String) async throws -> CategoryDTO {
        updateCalls.append((id, name))
        if gateUpdate {
            gateUpdate = false
            updateStarted = true
            await withCheckedContinuation { updateContinuation = $0 }
        }
        if let updateError {
            throw updateError
        }
        return categoryDTO(id: id, name: name)
    }

    func reorderCustomCategories(orderedIDs: [Int], transactionType: String) async throws -> [CategoryDTO] {
        reorderCalls.append((orderedIDs, transactionType))
        if gateReorder {
            gateReorder = false
            reorderStarted = true
            await withCheckedContinuation { reorderContinuation = $0 }
        }
        if let reorderError {
            throw reorderError
        }
        return reorderResponse
    }

    func deleteCustomCategory(id: Int) async throws {
        deletedIDs.append(id)
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
        createContinuation?.resume()
        createContinuation = nil
    }

    func releaseUpdate() {
        // 대기가 걸리기 전에 release가 오면 신호를 버려선 안 된다. 버리면 뒤늦게 도착한
        // PUT이 아무도 깨우지 않는 continuation에 걸려 테스트가 멈춘다.
        gateUpdate = false
        updateContinuation?.resume()
        updateContinuation = nil
    }

    func releaseReorder() {
        gateReorder = false
        reorderContinuation?.resume()
        reorderContinuation = nil
    }
}

private enum StoreTestError: Error {
    case requestFailed
    case identityMissing
    case unexpectedServerMutation
}
