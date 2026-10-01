//
//  TabNavigationModel.swift
//  woni_app
//

import Observation

/// 탭 안에서 push 하는 화면. 가계부 탭에는 없다 — 입력 화면은 전체 화면 모달이라 경로 밖이다.
enum TabRoute: Hashable {
    case reportCategory(categoryID: Int)
    case settingsLanguage
}

/// 선택된 탭과 탭마다 따로 쓰는 이동 스택. 다른 탭에 갔다 와도 보던 화면이 남는다(2026-10-02 사용자 결정).
/// 상태만 든다 — 재집계·토스트 같은 부작용은 루트가 한다.
@MainActor
@Observable
final class TabNavigationModel {
    private(set) var selectedTab: AppTab = .ledger
    private var paths: [AppTab: [TabRoute]] = [:]

    func path(for tab: AppTab) -> [TabRoute] {
        paths[tab, default: []]
    }

    func setPath(_ path: [TabRoute], for tab: AppTab) {
        paths[tab] = path
    }

    /// 이미 선택된 탭을 다시 고르면 그 탭만 첫 화면으로 돌아간다.
    func select(_ tab: AppTab) {
        if tab == selectedTab {
            paths[tab] = []
        }
        selectedTab = tab
    }

    /// 연타 중복 push 방어는 경로 상태로만 판정한다 — 로드 완료 여부에 기대면 기기별로 갈린다.
    func pushIfAtRoot(_ route: TabRoute, on tab: AppTab) {
        guard path(for: tab).isEmpty else {
            return
        }

        paths[tab] = [route]
    }

    func resetAll() {
        paths = [:]
        selectedTab = .ledger
    }
}
