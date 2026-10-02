//
//  TabNavigationModelTests.swift
//  woni_appTests
//

import Testing
@testable import woni_app

/// 탭마다 따로 쓰는 이동 스택과 선택된 탭을 지킨다.
@MainActor
struct TabNavigationModelTests {
    @Test("처음에는 가계부 탭이고 모든 탭 경로가 비었다")
    func startsOnLedgerWithEmptyPaths() {
        let model = TabNavigationModel()

        #expect(model.selectedTab == .ledger)
        for tab in AppTab.allCases {
            #expect(model.path(for: tab).isEmpty, "\(tab) 경로가 비어 있지 않다")
        }
    }

    @Test("다른 탭에 갔다 와도 보던 화면이 남는다")
    func selectingAnotherTabKeepsItsPath() {
        let model = TabNavigationModel()
        model.select(.report)
        model.setPath([.reportCategory(categoryID: 7)], for: .report)

        model.select(.settings)
        #expect(model.selectedTab == .settings)
        model.select(.report)

        #expect(model.selectedTab == .report)
        #expect(model.path(for: .report) == [.reportCategory(categoryID: 7)])
    }

    @Test("선택된 탭을 다시 누르면 그 탭만 첫 화면으로 돌아간다")
    func reselectingTheSelectedTabPopsToRoot() {
        let model = TabNavigationModel()
        model.setPath([.settingsLanguage], for: .settings)
        model.select(.report)
        model.setPath([.reportCategory(categoryID: 7)], for: .report)

        model.select(.report)

        #expect(model.selectedTab == .report)
        #expect(model.path(for: .report).isEmpty)
        #expect(model.path(for: .settings) == [.settingsLanguage])
    }

    @Test("경로가 비었을 때만 쌓는다 — 연타해도 한 번만 들어간다")
    func pushIfAtRootIgnoresSecondPush() {
        let model = TabNavigationModel()

        model.pushIfAtRoot(.reportCategory(categoryID: 7), on: .report)
        model.pushIfAtRoot(.reportCategory(categoryID: 8), on: .report)

        #expect(model.path(for: .report) == [.reportCategory(categoryID: 7)])
    }

    @Test("뒤로 가서 경로가 줄면 그 탭만 줄고, 다시 들어갈 수 있다")
    func poppingThroughSetPathAllowsPushAgain() {
        let model = TabNavigationModel()
        model.setPath([.settingsLanguage], for: .settings)
        model.pushIfAtRoot(.reportCategory(categoryID: 7), on: .report)

        // NavigationStack(path:) 바인딩이 뒤로 버튼·스와이프 뒤에 줄어든 경로를 써 넣는다.
        model.setPath([], for: .report)

        #expect(model.path(for: .report).isEmpty)
        #expect(model.path(for: .settings) == [.settingsLanguage])
        model.pushIfAtRoot(.reportCategory(categoryID: 8), on: .report)
        #expect(model.path(for: .report) == [.reportCategory(categoryID: 8)])
    }

    @Test("모두 초기화하면 모든 경로가 비고 가계부 탭이다")
    func resetAllClearsEveryPathAndSelectsLedger() {
        let model = TabNavigationModel()
        model.setPath([.reportCategory(categoryID: 7)], for: .ledger)
        model.setPath([.reportCategory(categoryID: 7)], for: .report)
        model.setPath([.settingsLanguage], for: .settings)
        model.select(.report)

        model.resetAll()

        #expect(model.selectedTab == .ledger)
        for tab in AppTab.allCases {
            #expect(model.path(for: tab).isEmpty, "\(tab) 경로가 비어 있지 않다")
        }
    }

    @Test("경로만 비우면 모든 경로가 비고 선택된 탭은 그대로다 — 로그아웃은 설정 탭에 남는다")
    func clearPathsKeepsSelectedTab() {
        let model = TabNavigationModel()
        model.setPath([.reportCategory(categoryID: 7)], for: .ledger)
        model.setPath([.reportCategory(categoryID: 7)], for: .report)
        model.setPath([.settingsLanguage], for: .settings)
        model.select(.settings)

        model.clearPaths()

        #expect(model.selectedTab == .settings)
        for tab in AppTab.allCases {
            #expect(model.path(for: tab).isEmpty, "\(tab) 경로가 비어 있지 않다")
        }
    }
}
