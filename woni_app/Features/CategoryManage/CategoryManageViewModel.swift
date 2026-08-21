//
//  CategoryManageViewModel.swift
//  woni_app
//

import Foundation
import Observation

@Observable
final class CategoryManageViewModel {
    /// 삭제 확인의 결과. View가 안내 토스트로 옮긴다.
    enum DeleteOutcome: Equatable {
        case success
        case failed
    }

    struct Row: Identifiable {
        let category: Category

        var id: Int {
            category.id
        }
    }

    /// 관리 대상 타입. 진입 시점의 탭으로 시작하고 화면 안에서 전환할 수 있다.
    private(set) var tab: EntryType

    private let store: CustomCategoryStore

    /// X를 탭해 삭제 확인 다이얼로그가 겨눈 카테고리. nil이면 다이얼로그가 닫혀 있다.
    private(set) var pendingDeletion: Category?
    private(set) var isDeleting = false

    init(
        tab: EntryType,
        customCategoryStore: CustomCategoryStore
    ) {
        self.tab = tab
        store = customCategoryStore
    }

    /// 관리 목록은 커스텀만 노출한다 — 기본은 삭제 대상이 아니라서 행으로 보여주지 않고
    /// 하단 안내 문구로 설명한다(2026-08-19 사용자 결정, 시안 ②⑨ 변경).
    var rows: [Row] {
        customCategories.map(Row.init)
    }

    func selectTab(_ tab: EntryType) {
        guard !isDeleting else {
            return
        }
        self.tab = tab
    }

    /// 서버 오류가 빈 목록으로 위장되지 않게 빈 상태와 구분해 표시한다.
    var showsLoadError: Bool {
        customCategories.isEmpty && store.lastRefreshError != nil
    }

    var showsEmptyState: Bool {
        customCategories.isEmpty && store.lastRefreshError == nil
    }

    var syncNotice: CustomCategorySyncNotice? {
        store.lastSyncNotice
    }

    func consumeSyncNotice() -> CustomCategorySyncNotice? {
        store.consumeSyncNotice()
    }

    func retryRefresh() async {
        await store.refresh()
    }

    func requestDelete(_ category: Category) {
        guard !isDeleting else {
            return
        }
        pendingDeletion = category
    }

    func cancelDelete() {
        guard !isDeleting else {
            return
        }
        pendingDeletion = nil
    }

    /// 로컬 삭제는 연결 상태와 미동기 내역에 막히지 않는다. 서버 반영 순서는 동기화 큐가 책임진다.
    /// 진행 중 재진입은 nil을 돌려 무시된다(isBusy 중복 탭 차단).
    func confirmDelete() async -> DeleteOutcome? {
        guard let category = pendingDeletion, !isDeleting else {
            return nil
        }
        isDeleting = true
        defer {
            isDeleting = false
            pendingDeletion = nil
        }

        do {
            try await store.remove(id: category.id)
            return .success
        } catch {
            return .failed
        }
    }
}

private extension CategoryManageViewModel {
    var customCategories: [Category] {
        store.categories(for: Self.catalogType(for: tab))
    }

    static func catalogType(for tab: EntryType) -> CatalogTransactionType {
        switch tab {
        case .expense:
            .expense
        case .income:
            .income
        }
    }
}
