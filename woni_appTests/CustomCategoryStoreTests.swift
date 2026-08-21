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
    private var created: [CategoryDTO]
    private let createError: Error?
    private let updateError: Error?
    private let deleteError: Error?
    private let identityAvailable: (() -> Bool)?
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private var createContinuation: CheckedContinuation<Void, Never>?
    private var updateContinuation: CheckedContinuation<Void, Never>?
    private(set) var createStarted = false
    private(set) var updateStarted = false

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
        gateUpdate: Bool = false
    ) {
        self.expense = expense
        self.income = income
        self.fetchError = fetchError
        self.gateFetch = gateFetch
        self.identityAvailable = identityAvailable
        self.gateCreate = gateCreate
        self.gateUpdate = gateUpdate
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
}

private enum StoreTestError: Error {
    case requestFailed
    case identityMissing
    case unexpectedServerMutation
}
