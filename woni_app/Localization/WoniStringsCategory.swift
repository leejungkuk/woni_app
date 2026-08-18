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
}
