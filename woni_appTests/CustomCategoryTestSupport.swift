//
//  CustomCategoryTestSupport.swift
//  woni_appTests
//
//  커스텀 카테고리 스위트 3벌이 각자 복사해 쓰던 캐시 페이크를 한 곳으로 모은다.
//  실 저장소 계약(load DESC · replaceSynced 순서 · pendingCreate 물리 삭제)을 재현하므로
//  계약이 바뀌면 여기만 고치면 된다.
//
//  서비스 스텁은 합치지 않는다 — 스위트마다 "이 계층은 서버를 호출하면 안 된다"는
//  서로 다른 단언을 담고 있어 하나로 합치면 그 단언이 사라진다.
//

import Foundation
import Testing
@testable import woni_app

@MainActor
final class CustomCategoryCacheStub: CustomCategoryCaching {
    var categories: [CachedCustomCategory]
    var replaceCount = 0
    var clearCount = 0
    var clearError: Error?
    var referencedIDs: Set<Int>
    var pendingPushIDs: Set<Int>
    private(set) var orderQueue: Set<CatalogTransactionType> = []

    private var gateNextUpsert: Bool
    private var gateNextRemove: Bool
    private var gateNextApplyOrder: Bool
    private var upsertContinuation: CheckedContinuation<Void, Never>?
    private var removeContinuation: CheckedContinuation<Void, Never>?
    private var applyOrderContinuation: CheckedContinuation<Void, Never>?
    private var applyOrderReleased = false
    private(set) var upsertStarted = false
    private(set) var removeStarted = false
    private(set) var applyOrderStarted = false

    init(
        categories: [CachedCustomCategory] = [],
        referencedIDs: Set<Int> = [],
        pendingPushIDs: Set<Int> = [],
        gateNextUpsert: Bool = false,
        gateNextRemove: Bool = false,
        gateNextApplyOrder: Bool = false
    ) {
        self.categories = categories
        self.referencedIDs = referencedIDs
        self.pendingPushIDs = pendingPushIDs
        self.gateNextUpsert = gateNextUpsert
        self.gateNextRemove = gateNextRemove
        self.gateNextApplyOrder = gateNextApplyOrder
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
        // 큐에 있는 타입은 아직 못 올린 로컬 순서가 서버보다 우선한다(R4). 실 저장소와 같은
        // 계약이라야 Store 테스트가 프로덕션과 다른 순서를 정상으로 단언하지 않는다.
        let localSortOrders = self.categories.reduce(into: [Int: Int]()) { $0[$1.id] = $1.sortOrder }
        self.categories.removeAll { $0.syncState == .synced }
        self.categories.append(contentsOf: categories.map { category in
            guard orderQueue.contains(category.transactionType),
                  let local = localSortOrders[category.id]
            else {
                return category
            }
            var preserved = category
            preserved.sortOrder = local
            return preserved
        })
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
            syncState: current.syncState == .synced ? .pendingUpdate : current.syncState,
            sortOrder: current.sortOrder
        )
    }

    func removeLocally(id: Int) async throws {
        if gateNextRemove {
            gateNextRemove = false
            removeStarted = true
            await withCheckedContinuation { removeContinuation = $0 }
        }
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

    func nextLocalID(reserving reservedIDs: Set<Int>) throws -> Int {
        min(categories.map(\.id).min() ?? 0, reservedIDs.min() ?? 0, 0) - 1
    }

    func activeCount() throws -> Int {
        categories.count { [.synced, .pendingCreate, .pendingUpdate].contains($0.syncState) }
    }

    func applyOrder(_ orderedIDs: [Int], type: CatalogTransactionType) async throws {
        if gateNextApplyOrder {
            gateNextApplyOrder = false
            applyOrderStarted = true
            // 등록과 해제 여부 판정을 같은 동기 구간에 둔다. 나눠 두면 대기에 들어가기 전에 온
            // release를 흘려 아무도 깨우지 않는 continuation에 걸린다.
            await withCheckedContinuation { continuation in
                if applyOrderReleased {
                    continuation.resume()
                } else {
                    applyOrderContinuation = continuation
                }
            }
        }
        for (index, id) in orderedIDs.enumerated() {
            guard let position = categories.firstIndex(where: { $0.id == id }) else { continue }
            categories[position].sortOrder = 1001 + index
        }
        orderQueue.insert(type)
    }

    func applySortOrders(_ pairs: [(id: Int, sortOrder: Int)], type: CatalogTransactionType) async throws {
        for pair in pairs {
            guard let position = categories.firstIndex(where: { $0.id == pair.id }) else { continue }
            categories[position].sortOrder = pair.sortOrder
        }
        orderQueue.remove(type)
    }

    func pendingOrderTypes() throws -> Set<CatalogTransactionType> {
        orderQueue
    }

    func remap(from oldID: Int, to newID: Int) async throws {
        categories = categories.map {
            $0.id == oldID
                ? CachedCustomCategory(
                    id: newID,
                    transactionType: $0.transactionType,
                    name: $0.name,
                    syncState: $0.syncState,
                    sortOrder: $0.sortOrder
                )
                : $0
        }
        if referencedIDs.remove(oldID) != nil {
            referencedIDs.insert(newID)
        }
    }

    func referencedCategoryIDs() throws -> Set<Int> {
        referencedIDs
    }

    func pendingPushCategoryIDs() throws -> Set<Int> {
        pendingPushIDs
    }

    func resetForAccountSwitch(reserving _: Set<Int>) async throws -> [Int: Int] {
        [:]
    }

    func clearAll() async throws {
        clearCount += 1
        if let clearError {
            throw clearError
        }
        categories = []
        orderQueue = []
    }

    /// 대기가 걸리기 전에 release가 오면 신호를 버려선 안 된다. 버리면 뒤늦게 도착한
    /// 쓰기가 아무도 깨우지 않는 continuation에 걸려 테스트가 멈춘다.
    func releaseUpsert() {
        gateNextUpsert = false
        upsertContinuation?.resume()
        upsertContinuation = nil
    }

    func releaseRemove() {
        gateNextRemove = false
        removeContinuation?.resume()
        removeContinuation = nil
    }

    func releaseApplyOrder() {
        gateNextApplyOrder = false
        applyOrderReleased = true
        applyOrderContinuation?.resume()
        applyOrderContinuation = nil
    }
}

func categoryDTO(id: Int, name: String, sortOrder: Int = 1000) -> CategoryDTO {
    CategoryDTO(
        id: id,
        code: "CUSTOM",
        displayNameKo: name,
        displayNameEn: name,
        icon: nil,
        sortOrder: sortOrder
    )
}

func cachedCategory(
    id: Int,
    type: CatalogTransactionType,
    name: String,
    state: CustomCategorySyncState = .synced,
    sortOrder: Int = 1000
) -> CachedCustomCategory {
    CachedCustomCategory(
        id: id,
        transactionType: type,
        name: name,
        syncState: state,
        sortOrder: sortOrder
    )
}
