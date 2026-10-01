//
//  SettingsRowTypographyTests.swift
//  woni_appTests
//
//  설정 행 글자 크기. 행 높이(52)는 minHeight 로 정해 글자를 16 으로 되돌려도 UI 테스트가 통과하므로
//  글자 크기는 유닛으로 지킨다.
//

import Foundation
import Testing
@testable import woni_app

struct SettingsRowTypographyTests {
    @Test("설정 행 글자는 KR 20pt 다 — 설정·언어 설정 행이 같은 값을 쓴다")
    func settingsRowTextIsTwentyPoints() {
        #expect(SettingsRow.textStyle.fontSize == 20)
    }
}
