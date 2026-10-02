//
//  SettingsRowTypographyTests.swift
//  woni_appTests
//
//  설정 행 글자 크기. 행 높이(52)는 minHeight 로 정해 글자 크기를 바꿔도 UI 테스트가 통과하므로
//  글자 크기는 유닛으로 지킨다.
//

import Foundation
import Testing
@testable import woni_app

struct SettingsRowTypographyTests {
    @Test("설정 행 글자는 16pt 다 — 출시본 값, 설정·언어 설정 행이 같은 값을 쓴다")
    func settingsRowTextIsSixteenPoints() {
        #expect(SettingsRow.textStyle.fontSize == 16)
    }
}
