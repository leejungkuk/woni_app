//
//  woni_appUITestsLaunchTests.swift
//  woni_appUITests
//
//  Created by J on 6/2/26.
//

import XCTest

/// 실행 스모크. 인자 없이 돌면 실기기 DB에 붙으므로 `-uiTest`로 인메모리 의존성을 강제한다.
/// `runsForEachTargetApplicationUIConfiguration`은 켜두면 회차마다 4번 반복해 스위트 시간만 늘려 껐다.
final class WoniAppUITestsLaunchTests: WoniAppUITestCase {
    @MainActor
    func testLaunch() {
        app.launchArguments = ["-uiTest"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
