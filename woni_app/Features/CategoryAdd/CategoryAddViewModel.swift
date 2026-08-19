//
//  CategoryAddViewModel.swift
//  woni_app
//

import Foundation
import Observation

@Observable
final class CategoryAddViewModel {
    /// 저장 시도의 결과. View가 pop·자동 선택 또는 안내 토스트로 옮긴다.
    enum SaveOutcome: Equatable {
        /// type은 실제 생성에 쓰인 타입 — await 후 tab 재조회에 기대지 않도록 값으로 고정한다.
        case saved(id: Int, type: EntryType)
        case offline
        case limitExceeded
        case failed
    }

    /// 서버 `@Size(max=50)`과 같은 UTF-16 code unit 단위 상한.
    static let maxNameLength = 50

    /// 생성 대상 타입. 진입 시점의 탭으로 시작하고 화면 안에서 전환할 수 있다.
    private(set) var tab: EntryType

    var name = ""
    private(set) var isSaving = false

    private let store: CustomCategoryStore
    private let connectivity: any ConnectivityObserving

    init(
        tab: EntryType,
        customCategoryStore: CustomCategoryStore,
        connectivity: any ConnectivityObserving
    ) {
        self.tab = tab
        store = customCategoryStore
        self.connectivity = connectivity
    }

    /// 카운터·검증은 grapheme 수가 아니라 UTF-16 유닛 수를 쓴다 — grapheme으로 세면
    /// 이모지·ZWJ 이름이 클라이언트를 통과한 뒤 서버에서 거부된다.
    var nameLength: Int {
        trimmedName.utf16.count
    }

    var canSave: Bool {
        !trimmedName.isEmpty && nameLength <= Self.maxNameLength
    }

    func selectTab(_ tab: EntryType) {
        guard !isSaving else {
            return
        }
        self.tab = tab
    }

    /// 오류 3분기 전부 입력을 유지한 채 안내로 끝난다(오프라인은 온라인 전용 결정 3의 명시적 실패).
    /// store의 stale-operation(revision 경합)은 일반 오류로 수렴한다 — 폐기된 id로 pop·선택하지
    /// 않는다. 진행 중 재진입은 nil을 돌려 무시된다(중복 탭 차단).
    func save() async -> SaveOutcome? {
        guard canSave, !isSaving else {
            return nil
        }
        isSaving = true
        defer {
            isSaving = false
        }

        guard connectivity.isOnline else {
            return .offline
        }
        let type = tab
        do {
            let id = try await store.create(name: trimmedName, type: Self.catalogType(for: type))
            return .saved(id: id, type: type)
        } catch {
            return Self.isLimitExceeded(error) ? .limitExceeded : .failed
        }
    }
}

private extension CategoryAddViewModel {
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func catalogType(for tab: EntryType) -> CatalogTransactionType {
        switch tab {
        case .expense:
            .expense
        case .income:
            .income
        }
    }

    static func isLimitExceeded(_ error: Error) -> Bool {
        guard case let APIError.server(code, _) = error else {
            return false
        }
        return code == "CUSTOM_CATEGORY_LIMIT_EXCEEDED"
    }
}
