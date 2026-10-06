//
//  GuestBudgetImportTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 비회원 예산 옮기기 부품 — 요청 모양, 카테고리 대응표, 둘을 묶은 옮기기.
/// 요청은 공용 스텁 세션에 회원 토큰을 든 `APIClient` 로 본다 — 토큰 없는 클라이언트는 헤더와 갱신을 단언할 수 없다.
/// 대응표는 실제 저장소(메모리 DB)로 본다 — 캐시 페이크의 리셋은 늘 빈 대응을 돌려 운영과 다른 상태에서 통과한다.
@MainActor
struct GuestBudgetImportTests {
    @Test("GBI.S0-R1 옮기기는 회원 토큰 헤더로 POST 하고 비회원 토큰과 대응표는 계약 키 그대로 본문에만 싣는다")
    func importSendsGuestTokenOnlyInBody() async throws {
        let auth = FakeAuthService(initialValue: "member-token-r1")
        let (client, log) = try await makeMemberClient(auth: auth) { request in
            try URLProtocolStub.response(for: request, body: successEnvelope(countsJSON(imported: 2, skipped: 1)))
        }
        let service = BudgetService(client: client)
        let mappedGuestToken = "guest-token-r1-mapped"
        let emptyGuestToken = "guest-token-r1-empty"

        _ = try await service.importFromGuest(GuestBudgetImportRequest(
            guestAccessToken: mappedGuestToken,
            categoryMappings: [GuestCategoryMapping(guestCategoryId: 10012, memberCategoryId: 10234)]
        ))
        _ = try await service.importFromGuest(GuestBudgetImportRequest(
            guestAccessToken: emptyGuestToken,
            categoryMappings: []
        ))

        let requests = log.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.method == "POST")
            #expect(request.url?.path == "/api/v1/budgets/import-from-guest")
            #expect(request.url?.query == nil)
            #expect(request.headers["Content-Type"] == "application/json")
            #expect(request.headers["Authorization"] == "Bearer member-token-r1")
            // 헤더는 지금 회원 토큰 그대로다 — 비회원 토큰이 어느 헤더에 실려도 안 된다.
            #expect(request.headers.values.contains { $0.contains("guest-token-r1") } == false)
        }

        let mapped = try jsonObject(requests.first?.body)
        #expect(Set(mapped.keys) == ["guestAccessToken", "categoryMappings"])
        #expect(mapped["guestAccessToken"] as? String == mappedGuestToken)
        let mappings = try #require(mapped["categoryMappings"] as? [[String: Any]])
        #expect(mappings.count == 1)
        let mapping = try #require(mappings.first)
        #expect(Set(mapping.keys) == ["guestCategoryId", "memberCategoryId"])
        #expect(mapping["guestCategoryId"] as? Int == 10012)
        #expect(mapping["memberCategoryId"] as? Int == 10234)

        // 키를 빼면 서버가 VALIDATION_ERROR 로 거부한다 — 대응이 없어도 빈 배열로 간다.
        let empty = try jsonObject(requests.last?.body)
        #expect(Set(empty.keys) == ["guestAccessToken", "categoryMappings"])
        #expect(empty["guestAccessToken"] as? String == emptyGuestToken)
        #expect((empty["categoryMappings"] as? [Any])?.isEmpty == true)
        #expect(auth.refreshCount == 0)
    }

    @Test("GBI.S0-R2 성공 봉투의 옮긴 달·건너뛴 달 수를 그대로 돌려준다")
    func importReturnsEnvelopeCounts() async throws {
        let (client, _) = try await makeMemberClient(auth: FakeAuthService(initialValue: "member-token-r2-ok")) {
            try URLProtocolStub.response(for: $0, body: successEnvelope(countsJSON(imported: 3, skipped: 4)))
        }
        let guestToken = "guest-token-r2-ok"

        let result = try await BudgetService(client: client).importFromGuest(GuestBudgetImportRequest(
            guestAccessToken: guestToken,
            categoryMappings: []
        ))

        #expect(result == GuestBudgetImportResult(importedMonthCount: 3, skippedMonthCount: 4))
    }

    /// 401 이면 `APIClient` 가 회원 토큰을 갱신한다. 비회원 토큰 문제로 회원 세션을 건드리면 안 된다(인계 §6).
    @Test("GBI.S0-R2 403 BUDGET_GUEST_TOKEN_INVALID 는 APIError 로 던지고 회원 토큰 갱신을 부르지 않는다")
    func guestTokenRejectionDoesNotRefreshMemberToken() async throws {
        let auth = FakeAuthService(initialValue: "member-token-r2-403")
        let (client, log) = try await makeMemberClient(auth: auth) { request in
            try URLProtocolStub.response(
                for: request,
                statusCode: 403,
                body: failureEnvelope("BUDGET_GUEST_TOKEN_INVALID")
            )
        }
        let guestToken = "guest-token-r2-403"

        await #expect {
            _ = try await BudgetService(client: client).importFromGuest(GuestBudgetImportRequest(
                guestAccessToken: guestToken,
                categoryMappings: []
            ))
        } throws: { error in
            guard case let APIError.server(code, _) = error else {
                return false
            }
            return code == "BUDGET_GUEST_TOKEN_INVALID"
        }

        // 헤더에 회원 토큰이 실렸다 = 세션이 있다 = 갱신을 부르면 셈이 오른다. 0 은 빈 셈이 아니다.
        #expect(log.requests.first?.headers["Authorization"] == "Bearer member-token-r2-403")
        #expect(log.requests.count == 1)
        #expect(auth.refreshCount == 0)
    }

    @Test("GBI.S0-R3 대응표는 마지막 리셋이 옮긴 비회원 서버 id → 회원 계정에 만든 id 이고 거래 없던 삭제 카테고리와 비회원 시절 음수 키는 뺀다")
    func mappingsCoverGuestServerCategoriesRecreatedForMember() async throws {
        let database = try AppDatabase.inMemory()
        let cache = CustomCategoryCacheRepository(database: database)
        try await cache.upsert(cachedCategory(id: 10012, type: .expense, name: "R3 식비"))
        // 거래를 쓴 뒤 지운 카테고리 — 삭제된 카테고리에는 거래를 저장할 수 없으므로 순서가 이렇다.
        try await cache.upsert(cachedCategory(id: 10013, type: .expense, name: "R3 삭제·거래 있음"))
        try await TransactionRepository(database: database).insert(makeEditableTransaction(categoryID: 10013))
        try await cache.updateSyncState(id: 10013, to: .deleted)
        try await cache.upsert(cachedCategory(
            id: 10014,
            type: .expense,
            name: "R3 삭제·거래 없음",
            state: .pendingDelete
        ))
        try await cache.upsert(cachedCategory(id: -1, type: .expense, name: "R3 비회원 때 못 올림", state: .pendingCreate))
        let service = MemberCategoryServiceStub(createdIDs: [
            "R3 식비": 10234,
            "R3 삭제·거래 있음": 10235,
            "R3 비회원 때 못 올림": 10236
        ])
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: FakeAuthService())

        try await store.resetForAccountSwitch()
        await store.flushPending()

        // 비회원 시절 음수 키(-1)는 회원 계정에 만들어졌어도 비회원 서버 id 가 아니라 표에 없다.
        #expect(service.createdNames.sorted() == ["R3 비회원 때 못 올림", "R3 삭제·거래 있음", "R3 식비"])
        #expect(await store.guestCategoryMappings() == [10012: 10234, 10013: 10235])
    }

    /// 덜 찬 표로 옮기면 그 몫이 "그 외"가 되고, 서버는 두 번째 요청에서 옮긴 달을 건너뛰어 되돌릴 길이 없다(인계 §4).
    @Test("GBI.S0-R4 회원 계정에 못 만든 카테고리가 남으면 nil, 만든 뒤에는 표, 리셋 전에는 빈 표다")
    func mappingsAreNilWhileAnyCategoryIsNotCreated() async throws {
        let database = try AppDatabase.inMemory()
        let cache = CustomCategoryCacheRepository(database: database)
        try await cache.upsert(cachedCategory(id: 20031, type: .expense, name: "R4 교통"))
        try await cache.upsert(cachedCategory(id: 20032, type: .expense, name: "R4 간식"))
        let service = MemberCategoryServiceStub(createdIDs: ["R4 교통": 20431, "R4 간식": 20432])
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: FakeAuthService())

        // 비회원 카테고리가 캐시에 있어도 리셋이 옮긴 대상이 없으면 보낼 대응도 없다.
        #expect(await store.guestCategoryMappings()?.isEmpty == true)

        try await store.resetForAccountSwitch()
        service.failingNames = ["R4 교통"]
        await store.flushPending()
        #expect(await store.guestCategoryMappings() == nil)

        service.failingNames = []
        await store.flushPending()
        #expect(await store.guestCategoryMappings() == [20031: 20431, 20032: 20432])
    }

    @Test("GBI.S0-R5 대응표가 nil 이면 요청을 보내지 않고 incompleteCategoryMapping 을 던진다")
    func importerRefusesIncompleteMappings() async throws {
        let (client, log) = try await makeMemberClient(auth: FakeAuthService(initialValue: "member-token-r5-nil")) {
            try URLProtocolStub.response(for: $0, body: successEnvelope(countsJSON(imported: 1, skipped: 0)))
        }
        let importer = GuestBudgetImporter(service: BudgetService(client: client), categoryMappings: { nil })
        let guestToken = "guest-token-r5-nil"

        await #expect(throws: GuestBudgetImportError.incompleteCategoryMapping) {
            try await importer.importGuestBudget(guestAccessToken: guestToken)
        }
        #expect(log.requests.isEmpty)
    }

    @Test("GBI.S0-R5 대응표가 있으면 받은 토큰과 guestCategoryId 오름차순 대응으로 요청 1건을 보낸다")
    func importerSendsSortedMappingsOnce() async throws {
        let auth = FakeAuthService(initialValue: "member-token-r5-sorted")
        let (client, log) = try await makeMemberClient(auth: auth) { request in
            try URLProtocolStub.response(for: request, body: successEnvelope(countsJSON(imported: 5, skipped: 2)))
        }
        let importer = GuestBudgetImporter(service: BudgetService(client: client), categoryMappings: {
            [50105: 60105, 50101: 60101, 50104: 60104, 50102: 60102, 50103: 60103]
        })
        let guestToken = "guest-token-r5-sorted"

        try await importer.importGuestBudget(guestAccessToken: guestToken)

        #expect(log.requests.count == 1)
        let body = try JSONDecoder().decode(SentImportBody.self, from: #require(log.requests.first?.body))
        #expect(body == SentImportBody(
            guestAccessToken: guestToken,
            categoryMappings: [
                .init(guestCategoryId: 50101, memberCategoryId: 60101),
                .init(guestCategoryId: 50102, memberCategoryId: 60102),
                .init(guestCategoryId: 50103, memberCategoryId: 60103),
                .init(guestCategoryId: 50104, memberCategoryId: 60104),
                .init(guestCategoryId: 50105, memberCategoryId: 60105)
            ]
        ))
    }

    /// 빈 표가 가면 서버는 그 몫을 조용히 "그 외"로 옮긴다 — 읽기 실패는 덜 찬 표와 같다.
    @Test("GBI.S0-R6 리셋이 옮긴 대상이 있는데 캐시를 못 읽으면 nil 이고 대상이 없으면 캐시를 읽지 않고 빈 표다")
    func mappingsAreNilWhenCacheReadFails() async throws {
        let cache = try LoadAllFailingCache(base: CustomCategoryCacheRepository(database: AppDatabase.inMemory()))
        try await cache.upsert(cachedCategory(id: 30051, type: .expense, name: "R6 여가"))
        let service = MemberCategoryServiceStub(createdIDs: ["R6 여가": 30451])
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: FakeAuthService())

        cache.loadAllError = GuestBudgetImportTestError.readFailed
        #expect(await store.guestCategoryMappings()?.isEmpty == true)
        cache.loadAllError = nil

        try await store.resetForAccountSwitch()
        await store.flushPending()
        #expect(await store.guestCategoryMappings() == [30051: 30451])

        cache.loadAllError = GuestBudgetImportTestError.readFailed
        #expect(await store.guestCategoryMappings() == nil)
    }

    /// 대상이 남으면 비워진 `idRemap` 때문에 `{g: g}` 가 가고, 서버는 그 id 가 회원 것이 아니라 404 를 낸다.
    @Test("GBI.S0-R7 clear() 뒤에는 옮길 대상이 비어 빈 표다")
    func clearEmptiesMappingTargets() async throws {
        let database = try AppDatabase.inMemory()
        let cache = CustomCategoryCacheRepository(database: database)
        try await cache.upsert(cachedCategory(id: 40071, type: .expense, name: "R7 선물"))
        let service = MemberCategoryServiceStub(createdIDs: ["R7 선물": 40471])
        let store = try CustomCategoryStore(service: service, cache: cache, authProvider: FakeAuthService())
        try await store.resetForAccountSwitch()
        await store.flushPending()
        #expect(await store.guestCategoryMappings() == [40071: 40471])

        try await store.clear()

        #expect(await store.guestCategoryMappings()?.isEmpty == true)
    }
}

private extension GuestBudgetImportTests {
    /// 회원 세션을 든 클라이언트 — 헤더 단언과 "갱신 0회" 단언이 빈 셈이 되지 않게 세션을 먼저 만든다.
    func makeMemberClient(
        auth: FakeAuthService,
        handler: @escaping URLProtocolStub.Handler
    ) async throws -> (APIClient, StubbedRequestLog) {
        let (session, log) = URLProtocolStub.makeSession(handler: handler)
        try await auth.ensureIdentity()
        return (APIClient(session: session, authProvider: auth), log)
    }

    func jsonObject(_ data: Data?) throws -> [String: Any] {
        let body = try #require(data)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

/// 보낸 본문을 다시 읽는 모양. 앱 DTO 는 보내기만 하므로(Encodable) 테스트가 따로 둔다.
private struct SentImportBody: Decodable, Equatable {
    struct Mapping: Decodable, Equatable {
        let guestCategoryId: Int
        let memberCategoryId: Int
    }

    let guestAccessToken: String
    let categoryMappings: [Mapping]
}

/// 로그인 때 회원 계정에 카테고리를 만드는 서버. 이름마다 정해 둔 id 를 주고, 실패할 이름은 던진다.
@MainActor
private final class MemberCategoryServiceStub: CustomCategoryServicing {
    var failingNames: Set<String> = []
    private(set) var createdNames: [String] = []
    private let createdIDs: [String: Int]

    init(createdIDs: [String: Int]) {
        self.createdIDs = createdIDs
    }

    func fetchCustomCategories(transactionType _: String) async throws -> [CategoryDTO] {
        []
    }

    func createCustomCategory(name: String, transactionType _: String) async throws -> CategoryDTO {
        guard !failingNames.contains(name), let id = createdIDs[name] else {
            throw GuestBudgetImportTestError.createFailed
        }
        createdNames.append(name)
        return categoryDTO(id: id, name: name)
    }

    func updateCustomCategory(id: Int, name: String) async throws -> CategoryDTO {
        categoryDTO(id: id, name: name)
    }

    func reorderCustomCategories(orderedIDs _: [Int], transactionType _: String) async throws -> [CategoryDTO] {
        []
    }

    func deleteCustomCategory(id _: Int) async throws {}
}

/// 실제 저장소를 그대로 쓰되 `loadAll` 만 던지게 할 수 있는 캐시.
@MainActor
private final class LoadAllFailingCache: CustomCategoryCaching {
    var loadAllError: Error?
    private let base: CustomCategoryCacheRepository

    init(base: CustomCategoryCacheRepository) {
        self.base = base
    }

    func load(for transactionType: CatalogTransactionType) throws -> [CachedCustomCategory] {
        try base.load(for: transactionType)
    }

    func loadAll() throws -> [CachedCustomCategory] {
        if let loadAllError {
            throw loadAllError
        }
        return try base.loadAll()
    }

    func replaceSynced(_ categories: [CachedCustomCategory]) async throws {
        try await base.replaceSynced(categories)
    }

    func upsert(_ category: CachedCustomCategory) async throws {
        try await base.upsert(category)
    }

    func renameLocally(id: Int, name: String) async throws {
        try await base.renameLocally(id: id, name: name)
    }

    func removeLocally(id: Int) async throws {
        try await base.removeLocally(id: id)
    }

    func updateSyncState(id: Int, to state: CustomCategorySyncState) async throws {
        try await base.updateSyncState(id: id, to: state)
    }

    func deleteRow(id: Int) async throws {
        try await base.deleteRow(id: id)
    }

    func nextLocalID(reserving reservedIDs: Set<Int>) throws -> Int {
        try base.nextLocalID(reserving: reservedIDs)
    }

    func activeCount() throws -> Int {
        try base.activeCount()
    }

    func hasPendingSyncWork() throws -> Bool {
        try base.hasPendingSyncWork()
    }

    func applyOrder(_ orderedIDs: [Int], type: CatalogTransactionType) async throws {
        try await base.applyOrder(orderedIDs, type: type)
    }

    func applySortOrders(_ pairs: [(id: Int, sortOrder: Int)], type: CatalogTransactionType) async throws {
        try await base.applySortOrders(pairs, type: type)
    }

    func pendingOrderTypes() throws -> Set<CatalogTransactionType> {
        try base.pendingOrderTypes()
    }

    func remap(from oldID: Int, to newID: Int) async throws {
        try await base.remap(from: oldID, to: newID)
    }

    func remapForServerCreate(
        from oldID: Int,
        to newID: Int,
        originalState: CustomCategorySyncState
    ) async throws {
        try await base.remapForServerCreate(from: oldID, to: newID, originalState: originalState)
    }

    func finalizeServerDelete(id: Int) async throws {
        try await base.finalizeServerDelete(id: id)
    }

    func referencedCategoryIDs() throws -> Set<Int> {
        try base.referencedCategoryIDs()
    }

    func pendingPushCategoryIDs() throws -> Set<Int> {
        try base.pendingPushCategoryIDs()
    }

    func resetForAccountSwitch(reserving reservedIDs: Set<Int>) async throws -> [Int: Int] {
        try await base.resetForAccountSwitch(reserving: reservedIDs)
    }

    func clearAll() async throws {
        try await base.clearAll()
    }
}

private enum GuestBudgetImportTestError: Error {
    case createFailed
    case readFailed
}

// MARK: - Fixtures (백엔드 ApiResponse·ErrorResponse 봉투 + GuestBudgetImportResponse 모양)

private func countsJSON(imported: Int, skipped: Int) -> String {
    #"{"importedMonthCount": \#(imported), "skippedMonthCount": \#(skipped)}"#
}

private func successEnvelope(_ data: String) -> String {
    """
    {"success": true, "code": null, "data": \(data), "message": null,
     "timestamp": "2026-10-06T15:30:00.123456"}
    """
}

private func failureEnvelope(_ code: String) -> String {
    """
    {"success": false, "code": "\(code)", "message": "서버 메시지",
     "timestamp": "2026-10-06T15:30:00.123456"}
    """
}
