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
    private var localWriteGate: (@escaping () async throws -> Void) async throws -> Void = {
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
        localWriteGate: @escaping (@escaping () async throws -> Void) async throws -> Void
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

        do {
            try await authProvider.ensureIdentity()
            // 두 GET은 각각 호출 시점의 토큰을 쓴다. 로그인은 신원을 먼저 바꾸고 이관을 나중에 하므로,
            // 그 사이에 도착한 응답을 그대로 반영하면 replaceSynced가 익명 synced 행을 지우고 회원
            // 목록으로 갈아끼워, 그 행을 참조하던 내역이 이관 대상에서 사라진 채 고아가 된다.
            let capturedUserID = authProvider.currentUserID
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
                try await commitGate.run { [self] in
                    guard
                        let current = try cache.loadAll().first(where: { $0.id == row.id }),
                        current.syncState == .pendingUpdate
                    else {
                        return
                    }
                    _ = try await service.updateCustomCategory(id: current.id, name: current.name)
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
        categories.sorted { sortKey($0.id) > sortKey($1.id) }
    }

    static func cached(
        _ categories: [Category],
        type: CatalogTransactionType
    ) -> [CachedCustomCategory] {
        categories.map {
            CachedCustomCategory(
                id: $0.id,
                transactionType: type,
                name: $0.displayNameKo
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
            sortOrder: 1000
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
