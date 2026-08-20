//
//  CustomCategoryStore.swift
//  woni_app
//

import Foundation
import Observation

enum CustomCategoryStoreError: Error, Equatable {
    case staleOperation
}

@Observable
final class CustomCategoryStore {
    private let service: any CustomCategoryServicing
    private let cache: any CustomCategoryCaching
    private let authProvider: any AuthProviding
    private let commitGate = CustomCategoryCommitGate()
    private var revision = 0
    private var lifecycleRevision = 0

    private(set) var expenseCategories: [Category]
    private(set) var incomeCategories: [Category]
    private(set) var lastRefreshError: Error?

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

    /// 로컬(음수)이 항상 먼저, 각 그룹 안에서는 최근 생성이 먼저.
    static func sortKey(_ id: Int) -> (Int, Int) {
        id < 0 ? (1, -id) : (0, id)
    }

    func refresh() async {
        let capturedRevision = revision

        do {
            try await authProvider.ensureIdentity()
            let expenseDTOs = try await service.fetchCustomCategories(
                transactionType: CatalogTransactionType.expense.rawValue
            )
            let incomeDTOs = try await service.fetchCustomCategories(
                transactionType: CatalogTransactionType.income.rawValue
            )
            try await commitGate.run { [self] in
                guard revision == capturedRevision else {
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
        return try await commitGate.run { [self] in
            guard lifecycleRevision == capturedLifecycleRevision else {
                throw CustomCategoryStoreError.staleOperation
            }
            guard try cache.activeCount() < 100 else {
                throw APIError.server(
                    code: "CUSTOM_CATEGORY_LIMIT_EXCEEDED",
                    message: "Custom category limit exceeded"
                )
            }
            let id = try cache.nextLocalID()
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

    func rename(id: Int, name: String) async throws {
        let capturedLifecycleRevision = lifecycleRevision
        try await commitGate.run { [self] in
            guard lifecycleRevision == capturedLifecycleRevision else {
                throw CustomCategoryStoreError.staleOperation
            }
            // 판정·이름·스냅샷·상태 전이는 저장소가 한 트랜잭션으로 처리한다.
            // 대상이 없거나 이미 삭제됐으면 categoryNotFound로 던진다(조용한 성공 금지).
            try await cache.renameLocally(id: id, name: name)
            guard lifecycleRevision == capturedLifecycleRevision else {
                throw CustomCategoryStoreError.staleOperation
            }
            try reloadCategories()
            revision += 1
        }
    }

    func remove(id: Int) async throws {
        let capturedLifecycleRevision = lifecycleRevision
        try await commitGate.run { [self] in
            guard lifecycleRevision == capturedLifecycleRevision else {
                throw CustomCategoryStoreError.staleOperation
            }
            // 참조 판정과 삭제를 같은 트랜잭션에서 해야 그 사이 저장된 내역을 놓치지 않는다.
            try await cache.removeLocally(id: id)
            guard lifecycleRevision == capturedLifecycleRevision else {
                throw CustomCategoryStoreError.staleOperation
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
        try await commitGate.run { [self] in
            try await cache.clearAll()
        }
    }
}

private extension CustomCategoryStore {
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
