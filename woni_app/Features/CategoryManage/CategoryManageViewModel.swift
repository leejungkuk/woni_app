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

    /// 순서 커밋의 결과. 로컬 저장 자체가 거부된 경우만 View가 안내로 옮긴다 —
    /// 전송 실패는 큐가 조용히 재시도하므로 화면에 알리지 않는다(R8).
    enum ReorderOutcome: Equatable {
        case committed
        case localWriteRejected
    }

    /// 행 높이. 드래그 인덱스 계산이 이 값에 의존하므로 View의 `.frame(height:)`도 이 상수를 쓴다.
    static let rowHeight: CGFloat = 56

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
        dragSnapshot ?? customCategories.map(Row.init)
    }

    func selectTab(_ tab: EntryType) {
        guard !isDeleting, !isReordering else {
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
        guard !isDeleting, !isReordering else {
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

    // MARK: - 순서 재배치

    /// 드래그 시작 시점의 행 스냅샷. 내용까지 담아 드래그 중 refresh가 이름·구성을 흔들지 못하게 한다.
    private(set) var dragSnapshot: [Row]?
    /// 스냅샷 기준 시작 인덱스(드래그 내내 불변).
    private(set) var startIndex: Int?
    /// 재배열 후 현재 인덱스.
    private(set) var currentIndex: Int?
    private(set) var draggingOffset: CGFloat = 0
    /// 커밋을 기다리는 동안 참. 이 창에서 들어오는 조작은 전부 무시한다.
    private var isCommitting = false

    var draggingID: Int? {
        currentIndex.flatMap { dragSnapshot?[$0].id }
    }

    /// 드래그를 시작하면 커밋이 끝날 때까지 목록이 흔들리면 안 된다 — `isDeleting`과 같은 잠금이다.
    var isReordering: Bool {
        dragSnapshot != nil
    }

    /// 이 행이 드래그를 몰아도 되는지 답한다. 아무도 끌고 있지 않으면 시작하고, 이미 다른
    /// 행이 끌리는 중이거나 커밋을 기다리는 중이면 false를 돌려 그 행의 이벤트를 통째로 버린다.
    /// 핸들은 행마다 독립된 제스처라, 두 손가락으로 두 핸들을 동시에 누르면 나중 손가락의
    /// 이동량이 먼저 시작한 행에 적용되고 먼저 뗀 손가락이 남의 드래그를 커밋해 버린다.
    @discardableResult
    func beginDrag(id: Int) -> Bool {
        guard dragSnapshot == nil else {
            return !isCommitting && draggingID == id
        }
        guard !isDeleting else {
            return false
        }
        let snapshot = customCategories.map(Row.init)
        guard let index = snapshot.firstIndex(where: { $0.id == id }) else {
            return false
        }
        dragSnapshot = snapshot
        startIndex = index
        currentIndex = index
        draggingOffset = 0
        return true
    }

    /// `beginDrag(id:)`가 true를 준 뒤에만 부른다 — 이 함수는 호출자를 식별하지 않고 지금
    /// 살아 있는 드래그를 조작하므로, 소유권을 확인하지 않고 부르면 남의 드래그를 움직인다.
    /// 이동량을 먼저 목록 범위로 자르고 목표 인덱스와 시각 오프셋을 **둘 다 그 값에서** 낸다.
    /// 인덱스만 자르면 첫 행을 위로·마지막 행을 아래로 끌 때 행이 목록 밖으로 빠져나갔다가 되튄다.
    /// 자동 스크롤은 만들지 않는다(R10) — 목록 끝에서는 행이 손가락과 분리돼 제자리에 멈춘다.
    func updateDrag(translation: CGFloat) {
        guard !isCommitting, let snapshot = dragSnapshot, let start = startIndex, let current = currentIndex else {
            return
        }
        let height = Self.rowHeight
        let clamped = min(
            max(translation, -CGFloat(start) * height),
            CGFloat(snapshot.count - 1 - start) * height
        )
        let target = start + Int((clamped / height).rounded())
        if target != current {
            var reordered = snapshot
            let moved = reordered.remove(at: current)
            reordered.insert(moved, at: target)
            dragSnapshot = reordered
            currentIndex = target
        }
        // 재배열로 그 행의 기준 위치가 이미 (target - start)칸 이동했으므로 그만큼 뺀다.
        // 보정하지 않으면 행이 손가락보다 한 칸 더 내려간다.
        draggingOffset = clamped - CGFloat(target - start) * height
    }

    /// 놓는 즉시 로컬에 커밋한다(R5). 어떤 오류로 끝나든 `defer`가 드래그 상태를 모두 풀어
    /// 화면을 Store 순서로 되돌린다 — 로컬은 안 바뀌었는데 화면만 재배열된 채 남는 갈라짐을 막는다.
    /// 커밋을 기다리는 동안에도 스냅샷은 살아 있어야 화면이 튀지 않는다. 그래서 그 창을
    /// `isCommitting`으로 닫는다 — 열어 두면 다른 핸들이 남의 스냅샷을 자기 것으로 알고
    /// 움직이거나 그대로 한 번 더 커밋해, 사용자가 만들지 않은 순서가 저장된다.
    func endDrag(id: Int) async -> ReorderOutcome? {
        guard !isCommitting, draggingID == id, let snapshot = dragSnapshot else {
            return nil
        }
        isCommitting = true
        defer {
            isCommitting = false
            dragSnapshot = nil
            startIndex = nil
            currentIndex = nil
            draggingOffset = 0
        }
        let orderedIDs = snapshot.map(\.id)
        guard orderedIDs != customCategories.map(\.id) else {
            // 제자리로 돌아왔다(핸들을 눌렀다 놓기만 한 경우 포함) — 저장도 전송도 할 것이 없다.
            return nil
        }
        do {
            try await store.reorder(orderedIDs: orderedIDs, type: Self.catalogType(for: tab))
            return .committed
        } catch SyncEngineError.localWritesSuspended {
            // 로컬 커밋 자체가 거부됐다 — 순서가 저장되지 않았으므로 화면까지 알린다.
            return .localWriteRejected
        } catch {
            // `staleOperation` 등 나머지는 조용히 Store 순서로 복원한다(defer).
            return nil
        }
    }

    /// VoiceOver 이동 액션(R11). 목록 경계를 넘어가면 아무 일도 하지 않고,
    /// 그 외에는 드래그와 같은 계산·같은 커밋 경로를 그대로 탄다.
    func move(id: Int, by delta: Int) async -> ReorderOutcome? {
        guard
            let index = rows.firstIndex(where: { $0.id == id }),
            rows.indices.contains(index + delta),
            beginDrag(id: id)
        else {
            return nil
        }
        updateDrag(translation: CGFloat(delta) * Self.rowHeight)
        return await endDrag(id: id)
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
