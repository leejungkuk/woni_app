//
//  AppTab.swift
//  woni_app
//

/// 하단 탭바의 칸. 탭바는 `allCases` 순서 그대로 그린다 — 예산 칸은 예산 탭 화면과 함께 넣었다(2026-10-02 사용자 결정).
enum AppTab: CaseIterable, Hashable {
    case ledger, report, budget, settings

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .ledger: WoniStrings.appTabLedger(language)
        case .report: WoniStrings.appTabReport(language)
        case .budget: WoniStrings.appTabBudget(language)
        case .settings: WoniStrings.appTabSettings(language)
        }
    }

    var accessibilityIdentifier: String {
        "tab.\(key)"
    }

    /// 시안 `ai_tabIcon`(`1946:11595`) 에셋. 켬은 채움·안쪽 선 바탕색이라 모양까지 끔과 다르다.
    func iconName(selected: Bool) -> String {
        "tab_\(key)_\(selected ? "on" : "off")"
    }

    private var key: String {
        switch self {
        case .ledger: "ledger"
        case .report: "report"
        case .budget: "budget"
        case .settings: "settings"
        }
    }
}
