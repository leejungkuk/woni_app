//
//  WoniStringsAppTab.swift
//  woni_app
//

import Foundation

/// 하단 탭바 칸 이름. 화면 제목(`settingsTitle` 등)과 따로 바뀔 수 있어 탭 전용으로 둔다.
extension WoniStrings {
    static func appTabLedger(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "가계부"
        case .en: "Ledger"
        }
    }

    static func appTabReport(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "통계"
        case .en: "Stats"
        }
    }

    static func appTabSettings(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "설정"
        case .en: "Setting"
        }
    }
}
