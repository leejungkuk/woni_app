//
//  CategoryAddViewModel.swift
//  woni_app
//

import Foundation
import Observation

typealias CategoryAddViewModelFactory = (EntryType, CategoryAddViewModel.Mode, String) -> CategoryAddViewModel

@Observable
final class CategoryAddViewModel {
    enum Mode: Equatable {
        case create
        case edit(id: Int)
    }

    /// 저장 시도의 결과. View가 pop·자동 선택 또는 안내 토스트로 옮긴다.
    enum SaveOutcome: Equatable {
        /// type은 실제 생성에 쓰인 타입 — await 후 tab 재조회에 기대지 않도록 값으로 고정한다.
        case saved(id: Int, type: EntryType)
        case updated
        case limitExceeded
        case failed
    }

    /// 서버 `@Size(max=50)`과 같은 UTF-16 code unit 단위 상한.
    static let maxNameLength = 50

    /// 생성 대상 타입. 진입 시점의 탭으로 시작하고 화면 안에서 전환할 수 있다.
    private(set) var tab: EntryType
    private(set) var mode: Mode

    var name: String
    private(set) var isSaving = false

    private let store: CustomCategoryStore

    init(
        tab: EntryType,
        customCategoryStore: CustomCategoryStore,
        mode: Mode = .create,
        name: String = ""
    ) {
        self.tab = tab
        store = customCategoryStore
        self.mode = mode
        self.name = name
    }

    var showsTypeTab: Bool {
        mode == .create
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
        guard showsTypeTab, !isSaving else {
            return
        }
        self.tab = tab
    }

    /// store의 stale-operation(revision 경합)은 일반 오류로 수렴한다 — 폐기된 결과로 pop·선택하지
    /// 않는다. 진행 중 재진입은 nil을 돌려 무시된다(중복 탭 차단).
    func save() async -> SaveOutcome? {
        guard canSave, !isSaving else {
            return nil
        }
        isSaving = true
        defer {
            isSaving = false
        }

        do {
            switch mode {
            case .create:
                // await 뒤 tab을 다시 읽지 않도록 실제 생성 타입을 값으로 먼저 고정한다.
                let type = tab
                let id = try await store.create(name: trimmedName, type: Self.catalogType(for: type))
                return .saved(id: id, type: type)
            case let .edit(id):
                try await store.rename(id: id, name: trimmedName)
                return .updated
            }
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
