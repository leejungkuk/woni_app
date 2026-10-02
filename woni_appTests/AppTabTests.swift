import Testing
import UIKit
@testable import woni_app

/// 하단 탭바의 칸 목록·이름·식별자·아이콘 에셋을 지킨다.
struct AppTabTests {
    @Test("탭은 가계부·통계·설정 순서다")
    func tabsAreLedgerReportSettingsInOrder() {
        #expect(AppTab.allCases == [.ledger, .report, .settings])
    }

    @Test("탭 이름은 표시 언어를 따른다")
    func tabTitlesFollowLanguage() {
        #expect(AppTab.ledger.title(.ko) == "가계부")
        #expect(AppTab.report.title(.ko) == "통계")
        #expect(AppTab.settings.title(.ko) == "설정")
        #expect(AppTab.ledger.title(.en) == "Ledger")
        #expect(AppTab.report.title(.en) == "Stats")
        #expect(AppTab.settings.title(.en) == "Setting")
    }

    @Test("탭 식별자는 고정이다")
    func tabIdentifiersAreStable() {
        #expect(AppTab.ledger.accessibilityIdentifier == "tab.ledger")
        #expect(AppTab.report.accessibilityIdentifier == "tab.report")
        #expect(AppTab.settings.accessibilityIdentifier == "tab.settings")
    }

    @Test("선택된 칸은 켬 아이콘, 나머지는 끔 아이콘이다 — 색과 모양을 함께 바꾼다")
    func selectedTabUsesOnIcon() {
        #expect(AppTab.ledger.iconName(selected: true) == "tab_ledger_on")
        #expect(AppTab.ledger.iconName(selected: false) == "tab_ledger_off")
        #expect(AppTab.report.iconName(selected: true) == "tab_report_on")
        #expect(AppTab.report.iconName(selected: false) == "tab_report_off")
        #expect(AppTab.settings.iconName(selected: true) == "tab_settings_on")
        #expect(AppTab.settings.iconName(selected: false) == "tab_settings_off")
    }

    @Test("탭 아이콘은 칸마다 켬·끔 에셋이 따로 있다")
    func tabIconAssetsExist() {
        let names = AppTab.allCases.flatMap { [$0.iconName(selected: true), $0.iconName(selected: false)] }
        #expect(Set(names).count == 6, "켬과 끔, 또는 다른 칸이 같은 에셋을 가리킨다: \(names)")
        for name in names {
            #expect(UIImage(named: name) != nil, "에셋 \(name) 이 번들에 없다")
        }
    }
}
