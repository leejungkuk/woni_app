//
//  NotificationRowGuardTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 설정 탭 "알림" 줄의 다시 누름 무시(UI_GUIDE 설정 탭 "알림" 줄, 2026-10-04 사용자 결정). 누른 뒤 처리(다시 읽기·iOS 권한 창·
/// iOS 설정 열기)가 끝날 때까지 다시 누름은 아무것도 바꾸지 않는다. 처리 중에 머물게 하려고 가짜 iOS 권한의 다시 읽기·권한 창을
/// 붙잡는다. 따로 적지 않으면 iOS 권한 창의 답은 허용이다.
@Suite(.serialized)
@MainActor
struct NotificationRowGuardTests {
    // MARK: R1 — 처리 중 다시 누름은 무시

    @Test("BDF.S6-R1 다시 읽기를 기다리는 동안 다시 누르면 아무것도 바꾸지 않고 첫 누름만 켠다")
    func secondPressWhileReadingIsIgnored() async throws {
        let fixture = try RowGuardFixture(enabled: false, ios: .allowed)
        await fixture.controller.refresh()
        fixture.permission.holdNextRead()

        let first = Task { await fixture.controller.toggleFromSettings() }
        await waitUntil { fixture.permission.isReadHeld }
        let second = await fixture.controller.toggleFromSettings()

        #expect(second == .unchanged)
        // 처음 1 + 첫 누름 1 — 무시한 누름은 다시 읽지도 않는다.
        #expect(fixture.permission.readCount == 2)
        #expect(fixture.permission.requestCount == 0)
        #expect(fixture.openCount == 0)
        #expect(!fixture.settings.isEnabled)

        fixture.permission.releaseRead()
        let firstResult = await first.value

        #expect(firstResult == .turnedOn)
        #expect(fixture.settings.isEnabled)
        #expect(fixture.controller.isEffectivelyOn)
        #expect(fixture.permission.readCount == 2)
    }

    @Test("BDF.S6-R1 iOS 권한 창을 기다리는 동안 다시 누르면 권한 창을 또 띄우지 않고 첫 누름만 켠다")
    func secondPressWhileRequestingIsIgnored() async throws {
        let fixture = try RowGuardFixture(enabled: false, ios: .notDetermined, requestResult: .allowed)
        await fixture.controller.refresh()
        fixture.permission.holdNextRequest()

        let first = Task { await fixture.controller.toggleFromSettings() }
        await waitUntil { fixture.permission.isRequestHeld }
        let second = await fixture.controller.toggleFromSettings()

        #expect(second == .unchanged)
        #expect(fixture.permission.readCount == 2)
        #expect(fixture.permission.requestCount == 1)
        #expect(fixture.openCount == 0)
        // 첫 누름이 권한 창 전에 켠 값 그대로다.
        #expect(fixture.settings.isEnabled)

        fixture.permission.releaseRequest()
        let firstResult = await first.value

        #expect(firstResult == .turnedOn)
        #expect(fixture.permission.requestCount == 1)
        #expect(fixture.settings.isEnabled)
        #expect(fixture.controller.authorization == .allowed)
    }

    @Test("BDF.S6-R1 실패 짝: 첫 누름이 끝난 뒤의 두 번째 누름은 무시하지 않고 켠 것을 끈다")
    func secondPressAfterFinishTurnsBackOff() async throws {
        let fixture = try RowGuardFixture(enabled: false, ios: .allowed)
        await fixture.controller.refresh()

        let first = await fixture.controller.toggleFromSettings()
        let second = await fixture.controller.toggleFromSettings()

        #expect(first == .turnedOn)
        #expect(second == .turnedOff)
        #expect(fixture.permission.readCount == 3)
        #expect(!fixture.settings.isEnabled)
    }

    // MARK: R2 — 처리가 끝나면 평소대로

    @Test("BDF.S6-R2 끄기가 끝나면 표시가 꺼지고 다시 누르면 켜는 경로로 처리한다")
    func pressAfterTurningOffTurnsOn() async throws {
        let fixture = try RowGuardFixture(enabled: true, ios: .allowed)
        await fixture.controller.refresh()

        let off = await fixture.controller.toggleFromSettings()

        #expect(off == .turnedOff)
        #expect(!fixture.controller.isTogglingFromSettings)

        let on = await fixture.controller.toggleFromSettings()

        #expect(on == .turnedOn)
        #expect(fixture.settings.isEnabled)
        #expect(fixture.controller.authorization == .allowed)
        #expect(fixture.controller.isEffectivelyOn)
    }

    @Test("BDF.S6-R2 권한 창·설정 열기·그대로 경로도 끝나면 표시가 꺼지고 다음 누름을 처리한다", arguments: [
        PathCase(name: "권한 창", ios: .notDetermined, requestResult: .allowed, result: .turnedOn, requests: 1, opens: 0),
        PathCase(name: "설정 열기", ios: .denied, requestResult: .allowed, result: .unchanged, requests: 0, opens: 1),
        PathCase(name: "그대로", ios: .notDetermined, requestResult: .denied, result: .unchanged, requests: 1, opens: 0)
    ])
    func everyPathClearsWhenFinished(_ path: PathCase) async throws {
        let fixture = try RowGuardFixture(enabled: false, ios: path.ios, requestResult: path.requestResult)
        await fixture.controller.refresh()

        let result = await fixture.controller.toggleFromSettings()

        #expect(result == path.result)
        #expect(fixture.permission.requestCount == path.requests)
        #expect(fixture.openCount == path.opens)
        #expect(!fixture.controller.isTogglingFromSettings)

        let readsBefore = fixture.permission.readCount
        _ = await fixture.controller.toggleFromSettings()

        #expect(fixture.permission.readCount == readsBefore + 1)
    }

    @Test("BDF.S6-R2 실패 짝: 다시 읽기가 끝나도 iOS 권한 창이 남은 동안은 아직 처리 중이다")
    func stillTogglingUntilRequestFinishes() async throws {
        let fixture = try RowGuardFixture(enabled: false, ios: .notDetermined, requestResult: .denied)
        await fixture.controller.refresh()
        fixture.permission.holdNextRead()
        fixture.permission.holdNextRequest()

        let toggling = Task { await fixture.controller.toggleFromSettings() }
        await waitUntil { fixture.permission.isReadHeld }
        fixture.permission.releaseRead()
        await waitUntil { fixture.permission.isRequestHeld }

        #expect(fixture.controller.isTogglingFromSettings)

        fixture.permission.releaseRequest()
        let result = await toggling.value

        #expect(result == .unchanged)
        #expect(!fixture.controller.isTogglingFromSettings)
    }

    // MARK: R3 — 첫 await 앞에서 켠다

    @Test("BDF.S6-R3 누르기 전에는 꺼져 있고 다시 읽기를 기다리는 동안 켜져 있다")
    func togglingIsOnWhileReading() async throws {
        let fixture = try RowGuardFixture(enabled: true, ios: .denied)

        #expect(!fixture.controller.isTogglingFromSettings)

        await fixture.controller.refresh()
        fixture.permission.holdNextRead()

        let toggling = Task { await fixture.controller.toggleFromSettings() }
        await waitUntil { fixture.permission.isReadHeld }

        #expect(fixture.controller.isTogglingFromSettings)

        fixture.permission.releaseRead()
        _ = await toggling.value

        #expect(!fixture.controller.isTogglingFromSettings)
    }

    @Test("BDF.S6-R3 실패 짝: 예산 탭 창의 알림 받기는 iOS 권한을 기다리는 동안에도 이 표시를 켜지 않는다")
    func answerAskDoesNotSetToggling() async throws {
        let fixture = try RowGuardFixture(enabled: false, ios: .notDetermined, requestResult: .allowed)
        fixture.permission.holdNextRead()
        fixture.permission.holdNextRequest()

        let answering = Task { await fixture.controller.answerAsk(.turnOn) }
        await waitUntil { fixture.permission.isReadHeld }

        #expect(!fixture.controller.isTogglingFromSettings)

        fixture.permission.releaseRead()
        await waitUntil { fixture.permission.isRequestHeld }

        #expect(!fixture.controller.isTogglingFromSettings)

        fixture.permission.releaseRequest()
        await answering.value

        #expect(fixture.controller.isEffectivelyOn)
    }
}

// MARK: 입력

extension NotificationRowGuardTests {
    /// 앱 알림 꺼짐에서 누른 한 번의 경로.
    struct PathCase: CustomTestStringConvertible {
        let name: String
        let ios: NotificationAuthorization
        let requestResult: NotificationAuthorization
        let result: NotificationToggleResult
        let requests: Int
        let opens: Int

        var testDescription: String {
            name
        }
    }
}

// MARK: 가짜

/// 테스트 하나가 쓰는 설정·가짜 iOS 권한·컨트롤러.
@MainActor
private final class RowGuardFixture {
    let settings: NotificationSettingsStore
    let permission: HoldablePermission
    let controller: NotificationPreferenceController
    private let opener = RowGuardOpenCounter()
    private let suiteName: String

    var openCount: Int {
        opener.count
    }

    init(
        enabled: Bool,
        ios: NotificationAuthorization,
        requestResult: NotificationAuthorization = .allowed
    ) throws {
        let suiteName = "woni_appTests.NotificationRowGuardTests.\(UUID().uuidString)"
        self.suiteName = suiteName
        settings = try NotificationSettingsStore(userDefaults: #require(UserDefaults(suiteName: suiteName)))
        settings.isEnabled = enabled
        permission = HoldablePermission(status: ios, requestResult: requestResult)
        let opener = opener
        controller = NotificationPreferenceController(
            settings: settings,
            permission: permission,
            openSystemSettings: { opener.count += 1 }
        )
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class RowGuardOpenCounter {
    var count = 0
}

/// 기기의 iOS 권한. 다음 다시 읽기 하나와 권한 창을 붙잡았다 풀 수 있다.
@MainActor
private final class HoldablePermission: NotificationPermissionProviding {
    /// 지금 기기의 값. 권한 창의 답으로 바뀐다.
    private var status: NotificationAuthorization
    /// iOS 권한 창의 답.
    private let requestResult: NotificationAuthorization
    private(set) var readCount = 0
    private(set) var requestCount = 0
    private var holdsRead = false
    private var holdsRequest = false
    private var heldRead: CheckedContinuation<Void, Never>?
    private var heldRequest: CheckedContinuation<Void, Never>?

    init(status: NotificationAuthorization, requestResult: NotificationAuthorization) {
        self.status = status
        self.requestResult = requestResult
    }

    var isReadHeld: Bool {
        heldRead != nil
    }

    var isRequestHeld: Bool {
        heldRequest != nil
    }

    func holdNextRead() {
        holdsRead = true
    }

    func holdNextRequest() {
        holdsRequest = true
    }

    func releaseRead() {
        heldRead?.resume()
        heldRead = nil
    }

    func releaseRequest() {
        heldRequest?.resume()
        heldRequest = nil
    }

    func authorization() async -> NotificationAuthorization {
        readCount += 1
        let value = status
        if holdsRead {
            holdsRead = false
            await withCheckedContinuation { heldRead = $0 }
        }
        return value
    }

    func requestAuthorization() async -> NotificationAuthorization {
        requestCount += 1
        if holdsRequest {
            holdsRequest = false
            await withCheckedContinuation { heldRequest = $0 }
        }
        status = requestResult
        return requestResult
    }
}
