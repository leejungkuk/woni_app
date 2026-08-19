//
//  WoniStringsCategory.swift
//  woni_app
//

/// 카테고리(커스텀 포함) 문구. `WoniStrings.swift`가 file_length 한계에 닿아 이 묶음만 분리했다.
extension WoniStrings {
    static func categoryDeletedReselectToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "쓰던 카테고리가 삭제됐어요. 다시 선택해 주세요."
        case .en: "The category you were using was deleted. Please select another one."
        }
    }

    static func categoryManageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "카테고리 관리"
        case .en: "Manage Categories"
        }
    }

    static func categoryManageEntry(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "수정"
        case .en: "Edit"
        }
    }

    static func categoryManageDefaultNotice(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "기본 카테고리는 지우거나 바꿀 수 없어요."
        case .en: "Default categories can't be deleted or changed."
        }
    }

    static func categoryManageEmptyTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "아직 만든 카테고리가 없어요"
        case .en: "You haven't made any categories yet"
        }
    }

    static func categoryManageEmptySubtitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "자주 쓰는 분류를 직접 만들어 보세요."
        case .en: "Create the ones you use often."
        }
    }

    static func categoryManageLoadFailed(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "불러오지 못했어요"
        case .en: "Couldn't load your categories"
        }
    }

    static func categoryAddButton(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "+ 카테고리 추가"
        case .en: "+ Add Category"
        }
    }

    static func categoryLoginRequiredToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그인하면 카테고리를 만들 수 있어요."
        case .en: "Sign in to create your own categories."
        }
    }

    static func categoryOfflineDeleteToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "오프라인에서는 카테고리를 지울 수 없어요."
        case .en: "You can't delete categories while offline."
        }
    }

    static func categoryDeletePendingEntriesToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "아직 저장 중인 내역이 있어요. 잠시 뒤 다시 시도해 주세요."
        case .en: "Some entries are still saving. Try again in a moment."
        }
    }

    static func categoryDeleteFailedToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "카테고리를 지우지 못했어요. 다시 시도해 주세요."
        case .en: "Couldn't delete the category. Please try again."
        }
    }
}
