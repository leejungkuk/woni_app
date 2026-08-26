//
//  CustomCategoryStore.swift
//  woni_app
//

import Foundation
import Observation
import OSLog

enum CustomCategoryStoreError: Error, Equatable {
    case staleOperation
}

enum CustomCategorySyncNotice: Equatable {
    case limitExceeded(pendingCreateCount: Int)
    case categoryNotFound
}

@Observable
final class CustomCategoryStore {
    private let service: any CustomCategoryServicing
    private let cache: any CustomCategoryCaching
    private let authProvider: any AuthProviding
    private let commitGate = CustomCategoryCommitGate()
    /// 주입 의존성이지 화면이 읽는 상태가 아니다. `@Observable`이 함수 타입 `var`에 만드는
    /// `_modify` 접근자는 Swift 버전에 따라 클로저의 격리 추론과 충돌해 컴파일이 깨진다.
    @ObservationIgnored
    private var localWriteGate: @MainActor (@escaping @MainActor () async throws -> Void)
        async throws -> Void = {
            try await $0()
        }

    nonisolated static let logger = Logger(subsystem: "woni_app", category: "CustomCategory")

    private var revision = 0
    private var lifecycleRevision = 0

    private(set) var expenseCategories: [Category]
    private(set) var incomeCategories: [Category]
    private(set) var lastRefreshError: Error?
    private(set) var lastSyncNotice: CustomCategorySyncNotice?
    private(set) var idRemap: [Int: Int] = [:]

    init(
        service: any CustomCategoryServicing,
        cache: any CustomCategoryCaching,
        authProvider: any AuthProviding
    ) throws {
        self.service = service
        self.cache = cache
        self.authProvider = authProvider
        expenseCategories = try Self.sorted(cache.load(for: .expense)).map(Self.toDomain)
        incomeCategories = try Self.sorted(cache.load(for: .income)).map(Self.toDomain)
    }

    func categories(for type: CatalogTransactionType) -> [Category] {
        switch type {
        case .expense:
            expenseCategories
        case .income:
            incomeCategories
        }
    }

    func configure(
        localWriteGate: @escaping @MainActor (@escaping @MainActor () async throws -> Void)
        async throws -> Void
    ) {
        self.localWriteGate = localWriteGate
    }

    func hasPendingWork() -> Bool {
        do {
            return try cache.hasPendingSyncWork()
        } catch {
            // 조용히 false를 돌려주면 큐가 영영 돌지 않는다 — 최소한 흔적을 남긴다.
            Self.logger.error("카테고리 큐 조회 실패: \(String(describing: error), privacy: .private)")
            return false
        }
    }

    func resolvedID(for id: Int) -> Int {
        idRemap[id] ?? id
    }

    /// 재매핑에 얽힌 id 전부. 새 로컬 id는 이것들과 겹치면 안 된다 — 겹치면 새 카테고리가
    /// 옛 매핑을 타고 다른 카테고리로 해석된다.
    private var reservedRemapIDs: Set<Int> {
        Set(idRemap.keys).union(idRemap.values)
    }

    func recordRemap(from old: Int, to new: Int) {
        for (key, value) in idRemap where value == old {
            idRemap[key] = new
        }
        idRemap[old] = new
    }

    func consumeSyncNotice() -> CustomCategorySyncNotice? {
        defer { lastSyncNotice = nil }
        return lastSyncNotice
    }

    /// 로컬(음수)이 항상 먼저, 각 그룹 안에서는 최근 생성이 먼저.
    static func sortKey(_ id: Int) -> (Int, Int) {
        id < 0 ? (1, -id) : (0, id)
    }

    func refresh() async {
        let capturedRevision = revision
        guard let capturedUserID = currentRefreshIdentity() else {
            return
        }

        do {
            // 두 GET은 각각 호출 시점의 토큰을 쓴다. 로그인은 신원을 먼저 바꾸고 이관을 나중에 하므로,
            // 그 사이에 도착한 응답을 그대로 반영하면 replaceSynced가 익명 synced 행을 지우고 회원
            // 목록으로 갈아끼워, 그 행을 참조하던 내역이 이관 대상에서 사라진 채 고아가 된다.
            let expenseDTOs = try await service.fetchCustomCategories(
                transactionType: CatalogTransactionType.expense.rawValue
            )
            let incomeDTOs = try await service.fetchCustomCategories(
                transactionType: CatalogTransactionType.income.rawValue
            )
            try await commitGate.run { [self] in
                guard revision == capturedRevision, authProvider.currentUserID == capturedUserID else {
                    return
                }
                let protectedIDs = try Set(cache.loadAll()
                    .filter { [.pendingUpdate, .pendingDelete, .deleted].contains($0.syncState) }
                    .map(\.id))
                let expense = expenseDTOs
                    .filter { !protectedIDs.contains($0.id) }
                    .map { $0.toDomain() }
                let income = incomeDTOs
                    .filter { !protectedIDs.contains($0.id) }
                    .map { $0.toDomain() }
                try await cache.replaceSynced(
                    Self.cached(expense, type: .expense)
                        + Self.cached(income, type: .income)
                )
                guard revision == capturedRevision else {
                    return
                }
                try reloadCategories()
                lastRefreshError = nil
                revision += 1
            }
        } catch {
            guard revision == capturedRevision else {
                return
            }
            lastRefreshError = error
        }
    }

    func create(name: String, type: CatalogTransactionType) async throws -> Int {
        let capturedLifecycleRevision = lifecycleRevision
        var createdID: Int?
        try await localWriteGate { [self] in
            createdID = try await commitGate.run { [self] in
                guard lifecycleRevision == capturedLifecycleRevision else {
                    throw CustomCategoryStoreError.staleOperation
                }
                guard try cache.activeCount() < 100 else {
                    throw APIError.server(
                        code: "CUSTOM_CATEGORY_LIMIT_EXCEEDED",
                        message: "Custom category limit exceeded"
                    )
                }
                let id = try cache.nextLocalID(reserving: reservedRemapIDs)
                try await cache.upsert(CachedCustomCategory(
                    id: id,
                    transactionType: type,
                    name: name,
                    syncState: .pendingCreate
                ))
                guard lifecycleRevision == capturedLifecycleRevision else {
                    throw CustomCategoryStoreError.staleOperation
                }
                try reloadCategories()
                revision += 1
                return id
            }
        }
        guard let createdID else {
            throw CustomCategoryStoreError.staleOperation
        }
        return createdID
    }

    func rename(id: Int, name: String) async throws {
        let capturedLifecycleRevision = lifecycleRevision
        try await localWriteGate { [self] in
            try await commitGate.run { [self] in
                guard lifecycleRevision == capturedLifecycleRevision else {
                    throw CustomCategoryStoreError.staleOperation
                }
                // 판정·이름·스냅샷·상태 전이는 저장소가 한 트랜잭션으로 처리한다.
                // 대상이 없거나 이미 삭제됐으면 categoryNotFound로 던진다(조용한 성공 금지).
                try await cache.renameLocally(id: resolvedID(for: id), name: name)
                guard lifecycleRevision == capturedLifecycleRevision else {
                    throw CustomCategoryStoreError.staleOperation
                }
                try reloadCategories()
                revision += 1
            }
        }
    }

    func remove(id: Int) async throws {
        let capturedLifecycleRevision = lifecycleRevision
        try await localWriteGate { [self] in
            try await commitGate.run { [self] in
                guard lifecycleRevision == capturedLifecycleRevision else {
                    throw CustomCategoryStoreError.staleOperation
                }
                // 참조 판정과 삭제를 같은 트랜잭션에서 해야 그 사이 저장된 내역을 놓치지 않는다.
                try await cache.removeLocally(id: resolvedID(for: id))
                guard lifecycleRevision == capturedLifecycleRevision else {
                    throw CustomCategoryStoreError.staleOperation
                }
                try reloadCategories()
                revision += 1
            }
        }
    }

    /// 내역 push 전에 서버 id가 없는 행을 먼저 생성하고 로컬 참조를 재매핑한다.
    func flushPending() async {
        let rows: [CachedCustomCategory]
        do {
            rows = try cache.loadAll()
                .filter { $0.id < 0 && [.pendingCreate, .pendingDelete].contains($0.syncState) }
                .sorted { $0.id > $1.id }
        } catch {
            Self.logger.error("카테고리 큐 로드 실패: \(String(describing: error), privacy: .private)")
            return
        }

        for (index, row) in rows.enumerated() {
            do {
                try await commitGate.run { [self] in
                    guard
                        let current = try cache.loadAll().first(where: { $0.id == row.id }),
                        current.id < 0,
                        [.pendingCreate, .pendingDelete].contains(current.syncState)
                    else {
                        return
                    }
                    let created = try await service.createCustomCategory(
                        name: current.name,
                        transactionType: current.transactionType.rawValue
                    )
                    try await cache.remapForServerCreate(
                        from: current.id,
                        to: created.id,
                        originalState: current.syncState
                    )
                    recordRemap(from: row.id, to: created.id)
                    try reloadCategories()
                    revision += 1
                }
            } catch let APIError.server(code, _) where code == "CUSTOM_CATEGORY_LIMIT_EXCEEDED" {
                // 이미 손에 든 큐에서 센다 — 여기서 DB를 다시 읽으면 그 조회 실패가
                // "0개 남음"이라는 틀린 안내로 둔갑한다.
                let remaining = rows[index...].count { $0.syncState == .pendingCreate }
                // 큐가 한도로 멈춘 사실은 안내와 별개로 남긴다 — 안 남기면 조용한 정지가 된다.
                Self.logger.error("카테고리 큐 한도 초과로 중단: 남은 생성 \(remaining, privacy: .public)건")
                // 남은 게 전부 삭제 대기면 사용자 눈에 보이는 미동기 카테고리가 없다.
                // 그대로 안내하면 "0개가 동기화되지 않았어요"라는 틀린 토스트가 뜬다.
                if remaining > 0 {
                    lastSyncNotice = .limitExceeded(pendingCreateCount: remaining)
                }
                // ①만 멈춘다. return하면 뒤의 ②까지 건너뛰어, 개수 한도와 무관한 이름 변경이
                // 무관한 생성 실패에 영구히 묶인다.
                break
            } catch {
                // 전송 오류는 큐에 남겨 다음 기회에 재시도한다(D3). DB·불변식 오류도 여기 걸리므로
                // 무엇 때문에 큐가 멈췄는지는 남긴다.
                Self.logger.error("카테고리 큐 처리 중단: \(String(describing: error), privacy: .private)")
                break
            }
        }

        // 순서는 타입 단위 계약인데 이 큐는 타입 구분 없이 돈다. 한쪽만 돌리면 반대 탭의
        // 순서가 영영 올라가지 않는다.
        for type in [CatalogTransactionType.expense, .income] {
            await flushPendingOrder(type: type)
        }

        await flushPendingUpdates()
    }

    /// 내역 push가 끝난 뒤 서버 삭제를 반영한다.
    func flushPendingDeletes() async {
        let rows: [CachedCustomCategory]
        do {
            // 아직 안 올라간 내역이 참조하는 카테고리만 보류한다. 무관한 내역 하나가 계속
            // 실패한다고 모든 삭제를 막으면 로컬에만 쌓인다(D3 ④는 "그 카테고리를 참조하는
            // 내역"의 순서를 요구하지 전역 직렬화를 요구하지 않는다).
            // 그 내역이 영구히 push 실패하면 이 카테고리도 로컬 pendingDelete로 남는다 —
            // 의도된 트레이드오프다. 먼저 지우면 그 내역이 서버에서 영구 거부돼 더 나쁘다(E4).
            let blockedIDs = try cache.pendingPushCategoryIDs()
            rows = try cache.loadAll()
                .filter { $0.id > 0 && $0.syncState == .pendingDelete && !blockedIDs.contains($0.id) }
                .sorted { $0.id < $1.id }
        } catch {
            Self.logger.error("카테고리 큐 로드 실패: \(String(describing: error), privacy: .private)")
            return
        }

        for row in rows {
            do {
                try await service.deleteCustomCategory(id: row.id)
                try await commitGate.run { [self] in
                    try await cache.finalizeServerDelete(id: row.id)
                    try reloadCategories()
                    revision += 1
                }
            } catch let APIError.server(code, _) where code == "CATEGORY_NOT_FOUND" {
                do {
                    try await resolveCategoryNotFound(id: row.id)
                } catch {
                    // 수렴에 실패하면 pendingDelete가 남아 같은 404가 반복된다.
                    Self.logger.error("카테고리 404 수렴 실패: \(String(describing: error), privacy: .private)")
                }
            } catch {
                // 전송 오류는 큐에 남겨 다음 기회에 재시도한다(D3). DB·불변식 오류도 여기 걸리므로
                // 무엇 때문에 큐가 멈췄는지는 남긴다.
                Self.logger.error("카테고리 큐 처리 중단: \(String(describing: error), privacy: .private)")
                return
            }
        }
    }

    func resolveCategoryNotFound(id: Int) async throws {
        try await commitGate.run { [self] in
            guard let row = try cache.loadAll().first(where: { $0.id == id }) else {
                return
            }
            switch row.syncState {
            case .pendingUpdate:
                try await cache.deleteRow(id: id)
            case .pendingDelete:
                try await cache.updateSyncState(id: id, to: .deleted)
            case .synced, .pendingCreate, .deleted:
                return
            }
            try reloadCategories()
            lastSyncNotice = .categoryNotFound
            revision += 1
        }
    }

    /// 다른 로컬 쓰기와 달리 `localWriteGate`(엔진의 push 게이트)를 거치지 않는다. 이 구간은
    /// `beginAccountSwitch()`로 push가 이미 멈춘 뒤라 큐(`flushPending`·`flushPendingDeletes`)가
    /// 동시에 돌 수 없고, UI에서 오는 create/rename/remove와의 순서는 FIFO인 `commitGate`가 잡는다.
    /// 게이트를 거치면 엔진→훅→Store→게이트→엔진으로 되돌아가므로 거칠 수도 없다.
    func resetForAccountSwitch() async throws {
        try await commitGate.run { [self] in
            let remap = try await cache.resetForAccountSwitch(reserving: reservedRemapIDs)
            for (oldID, newID) in remap {
                recordRemap(from: oldID, to: newID)
            }
            try reloadCategories()
            revision += 1
        }
    }

    func clear() async throws {
        // revision·메모리는 게이트 밖에서 즉시 비운다 — 계정 전환 직후 이전 계정 목록이 남지 않게.
        // 캐시는 FIFO 게이트 뒤라 진행 중 쓰기가 남아도 clearAll이 마지막에 실행돼 최종 상태는 빈다.
        lifecycleRevision += 1
        revision += 1
        expenseCategories = []
        incomeCategories = []
        lastRefreshError = nil
        lastSyncNotice = nil
        idRemap = [:]
        try await commitGate.run { [self] in
            try await cache.clearAll()
        }
    }
}

private extension CustomCategoryStore {
    func currentRefreshIdentity() -> UUID? {
        guard let userID = authProvider.currentUserID else {
            Self.logger.notice("Skipping category refresh because no current identity is available.")
            return nil
        }
        return userID
    }
}

// MARK: - 순서 재배치

extension CustomCategoryStore {
    /// 1차 키는 서버와 같은 `sortOrder`(미정렬 1000 < 재정렬 1001+), 2차 키는 기존 `sortKey`다.
    /// 서버의 2차 키는 id DESC인데 서버에 음수 id가 없어, 서버가 아는 행에 대해 두 규칙은 같다.
    static func isOrderedBefore(_ lhs: CachedCustomCategory, _ rhs: CachedCustomCategory) -> Bool {
        lhs.sortOrder == rhs.sortOrder ? sortKey(lhs.id) > sortKey(rhs.id) : lhs.sortOrder < rhs.sortOrder
    }

    /// 드래그로 확정한 순서를 로컬에 커밋한다. 전송은 하지 않는다 — 게이트를 통과한 로컬 쓰기가
    /// `schedulePushPending()`을 이미 예약하므로(`SyncEngine.swift:136`), 순서도 create·rename과
    /// 같은 push 경로를 타 suspension·계정 전환 대기·직렬화 보호를 그대로 받는다.
    func reorder(orderedIDs: [Int], type: CatalogTransactionType) async throws {
        let capturedLifecycleRevision = lifecycleRevision
        try await localWriteGate { [self] in
            try await commitGate.run { [self] in
                guard lifecycleRevision == capturedLifecycleRevision else {
                    throw CustomCategoryStoreError.staleOperation
                }
                // 드래그하는 사이 목록 구성 자체가 바뀌었으면(refresh·다른 경로의 생성·삭제) 화면이
                // 본 목록과 다른 순서를 쓰게 된다. 조용히 부분 적용하지 않고 명시적으로 실패시켜
                // 화면이 최신 목록으로 되돌아가게 한다. 순서가 다른 것은 이 호출의 목적이므로
                // 구성만 비교한다.
                guard categories(for: type).map(\.id).sorted() == orderedIDs.sorted() else {
                    throw CustomCategoryStoreError.staleOperation
                }
                // 순서 적용과 전송 큐 등록은 한 트랜잭션이다(저장소 계약).
                try await cache.applyOrder(orderedIDs, type: type)
                guard lifecycleRevision == capturedLifecycleRevision else {
                    throw CustomCategoryStoreError.staleOperation
                }
                try reloadCategories()
                revision += 1
            }
        }
    }

    /// ①(생성)과 ②(이름) 사이에 돈다 — 서버 id가 확보된 직후여야 그 타입의 전체 목록을 보낼 수 있다.
    private func flushPendingOrder(type: CatalogTransactionType) async {
        do {
            guard try cache.pendingOrderTypes().contains(type) else {
                return
            }
            // 순서의 원천은 언제나 Store 목록이다 — 캐시 반환 순서(id DESC)는 표시 순서가 아니다.
            let orderedIDs = categories(for: type).map(\.id)
            // 서버 id가 없는 행이 섞여 있으면 전체 목록을 보낼 수 없다. 큐를 유지해 생성이
            // 끝난 다음 기회에 보낸다(R3).
            guard !orderedIDs.contains(where: { $0 < 0 }) else {
                return
            }
            guard !orderedIDs.isEmpty else {
                // 보낼 행이 없으면 큐만 소진한다 — 남겨두면 push가 매번 헛돈다. 다른 커밋과
                // 같은 게이트 안에서 비우되, 기다리는 사이 새 reorder가 큐를 다시 넣었을 수
                // 있으니 목록이 아직 비어 있는지 확인한다. 확인 없이 지우면 방금 확정한
                // 순서가 이 사이클에 올라가지 않는다.
                try await commitGate.run { [self] in
                    guard categories(for: type).isEmpty else {
                        return
                    }
                    try await cache.applySortOrders([], type: type)
                }
                return
            }
            // ②와 같은 이유로 게이트 밖에서 기다린다 — 쥔 채 기다리면 로컬 저장이 통째로 멈춘다.
            let response = try await service.reorderCustomCategories(
                orderedIDs: orderedIDs,
                transactionType: type.rawValue
            )
            try await commitGate.run { [self] in
                // 보내는 사이에 또 드래그했다면 그 순서는 아직 서버에 없다. 큐를 유지해 다시 올린다.
                guard categories(for: type).map(\.id) == orderedIDs else {
                    return
                }
                // 응답 전체가 아니라 순서만 넘긴다 — 행을 통째로 저장하면 pendingUpdate의
                // 로컬 이름·상태가 서버 값에 덮인다.
                try await cache.applySortOrders(
                    response.map { (id: $0.id, sortOrder: $0.sortOrder) },
                    type: type
                )
                try reloadCategories()
                revision += 1
            }
        } catch let APIError.server(code, _) where code == "CATEGORY_NOT_FOUND" {
            // 다른 기기가 지운 카테고리를 보냈다. 큐는 유지한 채 목록만 서버와 맞추고 재전송은
            // 다음 사이클에 맡긴다 — 이 refresh가 없으면 같은 404가 영구히 반복된다.
            // refresh는 큐에 있는 타입의 로컬 순서를 덮지 않으므로(R4) 사라진 id만 빠진다.
            await refresh()
        } catch {
            // 전송 오류는 큐에 남겨 다음 기회에 재시도한다(R8).
            Self.logger.error("카테고리 순서 전송 중단: \(String(describing: error), privacy: .private)")
        }
    }
}

private extension CustomCategoryStore {
    func flushPendingUpdates() async {
        let rows: [CachedCustomCategory]
        do {
            rows = try cache.loadAll()
                .filter { $0.id > 0 && $0.syncState == .pendingUpdate }
                .sorted { $0.id < $1.id }
        } catch {
            Self.logger.error("카테고리 큐 로드 실패: \(String(describing: error), privacy: .private)")
            return
        }

        for row in rows {
            do {
                // ①과 달리 응답에서 받아 쓸 값이 없으므로 게이트 밖에서 기다린다(④와 같은 패턴).
                // 게이트를 쥔 채 응답을 기다리면 그동안 사용자의 로컬 저장이 통째로 멈춘다.
                _ = try await service.updateCustomCategory(id: row.id, name: row.name)
                try await commitGate.run { [self] in
                    // 보내는 사이에 이름이 또 바뀌었다면 그 변경은 아직 서버에 없다. 여기서
                    // synced로 내리면 최신 이름이 큐에서 빠져 영영 올라가지 않는다.
                    guard
                        let current = try cache.loadAll().first(where: { $0.id == row.id }),
                        current.syncState == .pendingUpdate,
                        current.name == row.name
                    else {
                        return
                    }
                    try await cache.updateSyncState(id: current.id, to: .synced)
                    try reloadCategories()
                    revision += 1
                }
            } catch let APIError.server(code, _) where code == "CATEGORY_NOT_FOUND" {
                do {
                    try await resolveCategoryNotFound(id: row.id)
                } catch {
                    Self.logger.error("카테고리 404 수렴 실패: \(String(describing: error), privacy: .private)")
                }
            } catch {
                Self.logger.error("카테고리 큐 처리 중단: \(String(describing: error), privacy: .private)")
                return
            }
        }
    }

    func reloadCategories() throws {
        expenseCategories = try Self.sorted(cache.load(for: .expense)).map(Self.toDomain)
        incomeCategories = try Self.sorted(cache.load(for: .income)).map(Self.toDomain)
    }

    static func sorted(_ categories: [CachedCustomCategory]) -> [CachedCustomCategory] {
        categories.sorted(by: isOrderedBefore)
    }

    static func cached(
        _ categories: [Category],
        type: CatalogTransactionType
    ) -> [CachedCustomCategory] {
        categories.map {
            CachedCustomCategory(
                id: $0.id,
                transactionType: type,
                name: $0.displayNameKo,
                sortOrder: $0.sortOrder
            )
        }
    }

    static func toDomain(_ cached: CachedCustomCategory) -> Category {
        CategoryDTO(
            id: cached.id,
            code: "CUSTOM",
            displayNameKo: cached.name,
            displayNameEn: cached.name,
            icon: nil,
            sortOrder: cached.sortOrder
        ).toDomain()
    }
}

@MainActor
private final class CustomCategoryCommitGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }
        waiters.removeFirst().resume()
    }
}
