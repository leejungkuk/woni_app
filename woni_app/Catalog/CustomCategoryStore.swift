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
        expenseCategories = try cache.load(for: .expense).map(Self.toDomain)
        incomeCategories = try cache.load(for: .income).map(Self.toDomain)
    }

    /// 회원 세션 판정(관리·추가 진입 게이트 겸용). isAnonymous 단독은 "세션 없음"을 회원으로
    /// 오판하므로 복합 조건을 쓴다.
    var isMemberSession: Bool {
        authProvider.currentUserID != nil && !authProvider.isAnonymous
    }

    func categories(for type: CatalogTransactionType) -> [Category] {
        switch type {
        case .expense:
            expenseCategories
        case .income:
            incomeCategories
        }
    }

    func refresh() async {
        guard isMemberSession else {
            return
        }
        let capturedRevision = revision

        do {
            let expenseDTOs = try await service.fetchCustomCategories(
                transactionType: CatalogTransactionType.expense.rawValue
            )
            let incomeDTOs = try await service.fetchCustomCategories(
                transactionType: CatalogTransactionType.income.rawValue
            )
            let expense = expenseDTOs.sorted { $0.id < $1.id }.map { $0.toDomain() }
            let income = incomeDTOs.sorted { $0.id < $1.id }.map { $0.toDomain() }
            try await commitGate.run { [self] in
                guard revision == capturedRevision else {
                    return
                }
                try await cache.replaceAll(Self.cached(expense, type: .expense)
                    + Self.cached(income, type: .income))
                guard revision == capturedRevision else {
                    return
                }
                expenseCategories = expense
                incomeCategories = income
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
        let capturedRevision = revision
        let dto = try await service.createCustomCategory(
            name: name,
            transactionType: type.rawValue
        )
        return try await commitGate.run { [self] in
            guard revision == capturedRevision else {
                throw CustomCategoryStoreError.staleOperation
            }

            var expense = expenseCategories
            var income = incomeCategories
            switch type {
            case .expense:
                expense.append(dto.toDomain())
                expense.sort { $0.id < $1.id }
            case .income:
                income.append(dto.toDomain())
                income.sort { $0.id < $1.id }
            }

            try await cache.replaceAll(Self.cached(expense, type: .expense)
                + Self.cached(income, type: .income))
            guard revision == capturedRevision else {
                throw CustomCategoryStoreError.staleOperation
            }
            expenseCategories = expense
            incomeCategories = income
            revision += 1
            return dto.id
        }
    }

    func remove(id: Int) async throws {
        let capturedRevision = revision
        do {
            try await service.deleteCustomCategory(id: id)
        } catch {
            guard revision == capturedRevision else {
                throw CustomCategoryStoreError.staleOperation
            }
            if Self.isCategoryNotFound(error) {
                await refresh()
            }
            throw error
        }
        try await commitGate.run { [self] in
            guard revision == capturedRevision else {
                throw CustomCategoryStoreError.staleOperation
            }
            let expense = expenseCategories.filter { $0.id != id }
            let income = incomeCategories.filter { $0.id != id }
            try await cache.replaceAll(Self.cached(expense, type: .expense)
                + Self.cached(income, type: .income))
            guard revision == capturedRevision else {
                throw CustomCategoryStoreError.staleOperation
            }
            expenseCategories = expense
            incomeCategories = income
            revision += 1
        }
    }

    func clear() async throws {
        // revision·메모리는 게이트 밖에서 즉시 비운다 — 계정 전환 직후 이전 계정 목록이 남지 않게.
        // 캐시는 FIFO 게이트 뒤라 진행 중 쓰기가 남아도 clearAll이 마지막에 실행돼 최종 상태는 빈다.
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

    static func isCategoryNotFound(_ error: Error) -> Bool {
        guard case let APIError.server(code, _) = error else {
            return false
        }
        return code == "CATEGORY_NOT_FOUND"
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
