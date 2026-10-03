//
//  SharedOverlayFixesTests.swift
//  woni_appTests
//

import Foundation
import Testing
import UIKit
@testable import woni_app

/// 년·월 피커 버튼 문구(UI_GUIDE "통계·예산 탭의 날짜를 누르면 년·월 피커")와 공용 확인 창의 누름 막기
/// (UI_GUIDE "공용 확인 창 … 0.5초"). 시계와 예약은 가짜이고 시간은 테스트가 직접 흘린다.
@MainActor
struct SharedOverlayFixesTests {
    // MARK: 피커 버튼 문구

    @Test("BDF.S0-R1 년·월 피커의 확인 버튼 문구는 ko 확인 · en OK 이다")
    func pickerConfirmTitleIsOK() {
        #expect(WoniStrings.pickerSave(.ko) == "확인")
        #expect(WoniStrings.pickerSave(.en) == "OK")
    }

    @Test("BDF.S0-R1 년·월 피커의 취소 버튼 문구는 그대로 ko 취소 · en Cancel 이다")
    func pickerCancelTitleIsUnchanged() {
        #expect(WoniStrings.pickerCancel(.ko) == "취소")
        #expect(WoniStrings.pickerCancel(.en) == "Cancel")
    }

    // MARK: 확인 창 누름 막기

    @Test("BDF.S0-R2 막는 중이 아니면 누름은 막기를 먼저 켜고 액션을 한 번 부른다")
    func firstTapBlocksThenRunsAction() {
        let fakes = TapGuardFakes()
        #expect(!fakes.tapGuard.isBlocking)
        #expect(fakes.calls.isEmpty)

        let handled = fakes.tapGuard.handleTap { fakes.calls.append(.action) }

        #expect(handled)
        #expect(fakes.calls == [.block, .action])
        #expect(fakes.tapGuard.isBlocking)
    }

    @Test("BDF.S0-R3 막는 동안의 누름은 액션을 부르지 않고, 0.5초 뒤 풀기가 돌면 다시 받는다")
    func tapsWhileBlockingAreDroppedUntilRelease() throws {
        let fakes = TapGuardFakes()
        var actions = 0
        fakes.tapGuard.handleTap { actions += 1 }

        // QA 에서 본 간격 — 창이 닫힌 뒤의 두 번째 누름.
        fakes.advance(to: 0.32)
        #expect(!fakes.tapGuard.handleTap { actions += 1 })
        #expect(actions == 1)
        #expect(fakes.blockCount == 1)

        fakes.advance(to: 0.49)
        #expect(!fakes.tapGuard.handleTap { actions += 1 })
        #expect(actions == 1)
        #expect(fakes.releaseCount == 0)

        #expect(ConfirmDialogTapGuard.blockDuration == 0.5)
        #expect(fakes.scheduled.count == 1)
        let release = try #require(fakes.scheduled.first)
        #expect(release.delay == 0.5)
        fakes.advance(to: 0.5)
        release.work()

        #expect(fakes.releaseCount == 1)
        #expect(!fakes.tapGuard.isBlocking)
        #expect(fakes.tapGuard.handleTap { actions += 1 })
        #expect(actions == 2)
        #expect(fakes.blockCount == 2)
    }

    @Test("BDF.S0-R5 풀기는 막을 때의 window 를 다시 켜고, 그 사이 key window 가 바뀌어도 다른 window 를 건드리지 않는다")
    func releaseRestoresBlockedWindowAfterKeyWindowChanges() {
        let windowA = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let windowB = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        var keyWindow: UIWindow? = windowA
        let block = ConfirmDialogTapGuard.windowBlocker { keyWindow }

        let release = block()
        #expect(!windowA.isUserInteractionEnabled)
        #expect(windowB.isUserInteractionEnabled)

        keyWindow = windowB
        release()

        #expect(windowA.isUserInteractionEnabled)
        #expect(windowB.isUserInteractionEnabled)
    }

    @Test("BDF.S0-R5 막은 뒤 key window 가 없어져도(iOS 설정을 열고 돌아옴) 풀기는 막았던 window 를 켠다")
    func releaseRestoresBlockedWindowAfterKeyWindowIsGone() {
        let windowA = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        var keyWindow: UIWindow? = windowA
        let block = ConfirmDialogTapGuard.windowBlocker { keyWindow }
        let release = block()

        keyWindow = nil
        #expect(!windowA.isUserInteractionEnabled)
        release()

        #expect(windowA.isUserInteractionEnabled)
    }

    // MARK: 막기 시간

    @Test("BDF.S0-R7 막기 시간은 -uiTest 와 늘림 인자가 함께 있지 않으면 0.5초다")
    func blockDurationStaysProductValueWithoutBothUITestArguments() {
        let executable = "/private/var/containers/Bundle/Application/woni_app.app/woni_app"

        #expect(ConfirmDialogTapGuard.blockDuration(arguments: [executable]) == 0.5)
        #expect(ConfirmDialogTapGuard.blockDuration(arguments: [executable, UITestSupport.enableFlag]) == 0.5)
        #expect(ConfirmDialogTapGuard.blockDuration(arguments: [executable, UITestSupport.longTapGuardFlag]) == 0.5)
    }

    @Test("BDF.S0-R7 막기 시간은 -uiTest 와 늘림 인자가 함께 있을 때만 3초로 늘어난다")
    func blockDurationGrowsWithBothUITestArguments() {
        let executable = "/private/var/containers/Bundle/Application/woni_app.app/woni_app"
        let arguments = [executable, UITestSupport.enableFlag, UITestSupport.longTapGuardFlag]

        #expect(ConfirmDialogTapGuard.blockDuration(arguments: arguments) == 3)
    }
}

/// 가짜 시계·가짜 예약과 부른 횟수를 세는 막기. 예약된 일은 테스트가 직접 부른다.
@MainActor
private final class TapGuardFakes {
    enum Call: Equatable {
        case block
        case action
    }

    /// 막기와 (테스트가 넣은) 액션을 부른 차례.
    var calls: [Call] = []
    private(set) var blockCount = 0
    private(set) var releaseCount = 0
    private(set) var scheduled: [(delay: TimeInterval, work: () -> Void)] = []
    private var clock = Date(timeIntervalSinceReferenceDate: 0)

    lazy var tapGuard = ConfirmDialogTapGuard(
        now: { [unowned self] in clock },
        block: { [unowned self] in
            blockCount += 1
            calls.append(.block)
            return { [unowned self] in releaseCount += 1 }
        },
        schedule: { [unowned self] delay, work in scheduled.append((delay, work)) }
    )

    /// 첫 누름(0초)부터 흐른 시간.
    func advance(to seconds: TimeInterval) {
        clock = Date(timeIntervalSinceReferenceDate: seconds)
    }
}
