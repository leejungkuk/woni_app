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
}
