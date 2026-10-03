//
//  NotificationPreferenceControllerTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// "알림을 받을까요?" 창과 설정 탭 "알림" 줄의 판정(UI_GUIDE 203-208 · 스펙 :379-388).
/// 따로 적지 않으면 앱 알림 꺼짐 · 안 물어봄 · iOS 권한 `.notDetermined` · iOS 권한 창의 답은 허용이다.
/// 설정은 실제 `NotificationSettingsStore`(테스트마다 새 suite)다.
@Suite(.serialized)
@MainActor
struct NotificationPreferenceControllerTests {
    // MARK: 보이는 값 · 다시 읽기

    @Test("B64N.S3-R1 보이는 값은 앱 알림 켜짐과 iOS 허용이 둘 다 있을 때만 켜짐이다", arguments: [
        EffectiveCase(enabled: true, ios: .allowed, isOn: true),
        EffectiveCase(enabled: true, ios: .denied, isOn: false),
        EffectiveCase(enabled: true, ios: .notDetermined, isOn: false),
        EffectiveCase(enabled: false, ios: .allowed, isOn: false)
    ])
    func effectiveValueNeedsAppAndIOS(_ effective: EffectiveCase) async throws {
        let fixture = try Fixture(enabled: effective.enabled, ios: effective.ios)

        await fixture.controller.refresh()

        #expect(fixture.controller.isEffectivelyOn == effective.isOn)
    }

    @Test("B64N.S3-R2 처음에는 iOS 권한을 모르고, 다시 읽으면 기기의 값이 된다")
    func authorizationStartsUnknownUntilRefresh() async throws {
        let fixture = try Fixture(enabled: true, ios: .denied)

        #expect(fixture.controller.authorization == .notDetermined)
        #expect(fixture.permission.readCount == 0)

        await fixture.controller.refresh()

        #expect(fixture.controller.authorization == .denied)
        #expect(fixture.permission.readCount == 1)
    }

    @Test("B64N.S3-R2 iOS 설정에서 바꾸고 돌아오면 다시 읽을 때 보이는 값이 따라간다", arguments: [
        RefreshCase(before: .denied, after: .allowed),
        RefreshCase(before: .allowed, after: .denied)
    ])
    func refreshFollowsIOSSettings(_ refresh: RefreshCase) async throws {
        let fixture = try Fixture(enabled: true, ios: refresh.before)
        await fixture.controller.refresh()
        let wasOn = fixture.controller.isEffectivelyOn
        #expect(wasOn == (refresh.before == .allowed))

        fixture.permission.status = refresh.after
        // 다시 읽기 전에는 옛 값 그대로다.
        #expect(fixture.controller.isEffectivelyOn == wasOn)

        await fixture.controller.refresh()

        #expect(fixture.controller.isEffectivelyOn == (refresh.after == .allowed))
    }

    @Test("B64N.S3-R2 다시 읽는 사이 iOS 권한 창의 답이 들어오면 늦게 끝난 다시 읽기가 답을 덮지 않는다", arguments: Entry.allCases)
    func lateRefreshDoesNotOverwriteRequestAnswer(_ entry: Entry) async throws {
        let fixture = try Fixture(ios: .notDetermined, requestResult: .allowed)
        fixture.permission.holdNextRequest()
        let answering = Task { await entry.run(fixture.controller) }
        await waitUntil { fixture.permission.isRequestHeld }

        // 권한 창이 떠 있는 사이 시작한 다시 읽기(foreground 갱신) — 그때 iOS 는 아직 `.notDetermined` 다.
        fixture.permission.holdNextRead()
        let refreshing = Task { await fixture.controller.refresh() }
        await waitUntil { fixture.permission.isReadHeld }
        fixture.permission.releaseRequest()
        await answering.value
        #expect(fixture.controller.authorization == .allowed)

        fixture.permission.releaseRead()
        await refreshing.value

        #expect(fixture.controller.authorization == .allowed)
        #expect(fixture.controller.isEffectivelyOn)
    }

    @Test("B64N.S3-R2 먼저 시작한 다시 읽기가 늦게 끝나면 뒤에 시작한 다시 읽기의 값이 남는다")
    func earlierRefreshDoesNotOverwriteLaterRefresh() async throws {
        let fixture = try Fixture(enabled: true, ios: .denied)
        fixture.permission.holdNextRead()
        let earlier = Task { await fixture.controller.refresh() }
        await waitUntil { fixture.permission.isReadHeld }

        fixture.permission.status = .allowed
        await fixture.controller.refresh()
        #expect(fixture.controller.authorization == .allowed)

        fixture.permission.releaseRead()
        await earlier.value

        #expect(fixture.controller.authorization == .allowed)
        #expect(fixture.controller.isEffectivelyOn)
    }

    @Test("B64N.S3-R2 짝: 그 사이 새 값이 없으면 붙잡혔던 다시 읽기의 값을 쓴다")
    func heldRefreshAppliesWhenNothingNewer() async throws {
        let fixture = try Fixture(enabled: true, ios: .allowed)
        await fixture.controller.refresh()
        fixture.permission.status = .denied
        fixture.permission.holdNextRead()
        let refreshing = Task { await fixture.controller.refresh() }
        await waitUntil { fixture.permission.isReadHeld }
        #expect(fixture.controller.authorization == .allowed)

        fixture.permission.releaseRead()
        await refreshing.value

        #expect(fixture.controller.authorization == .denied)
        #expect(!fixture.controller.isEffectivelyOn)
    }
}

// MARK: 판정 중에 겹친 다시 읽기

extension NotificationPreferenceControllerTests {
    @Test("B64N.S3-R2 설정 줄의 다시 읽기는 뒤에 다른 다시 읽기가 시작만 했으면 버려지지 않고 판정에 쓰인다")
    func toggleKeepsOwnRefreshWhenLaterOnlyStarted() async throws {
        let fixture = try Fixture(enabled: false, ios: .denied)
        await fixture.controller.refresh()
        // iOS 설정에서 허용하고 돌아왔다 — 마지막으로 읽은 값은 아직 거부다.
        fixture.permission.status = .allowed
        fixture.permission.holdNextRead()
        let toggling = Task { await fixture.controller.toggleFromSettings() }
        await waitUntil { fixture.permission.heldReadCount == 1 }

        // 판정용 다시 읽기가 도는 사이 foreground 갱신이 시작만 했다.
        fixture.permission.holdNextRead()
        let refreshing = Task { await fixture.controller.refresh() }
        await waitUntil { fixture.permission.heldReadCount == 2 }

        fixture.permission.releaseRead()
        let result = await toggling.value
        #expect(result == .turnedOn)
        #expect(fixture.openCount == 0)
        #expect(fixture.controller.authorization == .allowed)

        fixture.permission.releaseRead()
        await refreshing.value

        #expect(fixture.controller.authorization == .allowed)
        #expect(fixture.controller.isEffectivelyOn)
    }

    @Test("B64N.S3-R2 알림 받기의 다시 읽기는 뒤에 다른 다시 읽기가 시작만 했으면 버려지지 않고 권한 창 판정에 쓰인다")
    func turnOnKeepsOwnRefreshWhenLaterOnlyStarted() async throws {
        let fixture = try Fixture(ios: .allowed, requestResult: .allowed)
        await fixture.controller.refresh()
        // 마지막으로 읽은 값은 허용인데 기기는 아직 iOS 권한을 묻지 않았다.
        fixture.permission.status = .notDetermined
        fixture.permission.holdNextRead()
        let answering = Task { await fixture.controller.answerAsk(.turnOn) }
        await waitUntil { fixture.permission.heldReadCount == 1 }

        fixture.permission.holdNextRead()
        let refreshing = Task { await fixture.controller.refresh() }
        await waitUntil { fixture.permission.heldReadCount == 2 }

        fixture.permission.releaseRead()
        await answering.value
        #expect(fixture.permission.requestCount == 1)
        #expect(fixture.controller.authorization == .allowed)

        // 늦게 끝난 다시 읽기(.notDetermined)는 권한 창의 답보다 먼저 시작했으므로 버린다.
        fixture.permission.releaseRead()
        await refreshing.value

        #expect(fixture.controller.authorization == .allowed)
        #expect(fixture.controller.isEffectivelyOn)
    }

    @Test("B64N.S3-R2 짝: 설정 줄의 다시 읽기가 낡은 값을 들고 늦게 끝나면 뒤에 시작해 먼저 반영된 값으로 판정한다")
    func toggleDropsOwnRefreshWhenLaterAlreadyApplied() async throws {
        let fixture = try Fixture(enabled: false, ios: .denied)
        await fixture.controller.refresh()
        fixture.permission.holdNextRead()
        let toggling = Task { await fixture.controller.toggleFromSettings() }
        await waitUntil { fixture.permission.isReadHeld }

        // 판정용 다시 읽기가 거부를 읽은 뒤 허용으로 바뀌었고, 뒤에 시작한 다시 읽기가 먼저 끝났다.
        fixture.permission.status = .allowed
        await fixture.controller.refresh()
        #expect(fixture.controller.authorization == .allowed)

        fixture.permission.releaseRead()
        let result = await toggling.value

        #expect(fixture.controller.authorization == .allowed)
        #expect(result == .turnedOn)
        #expect(fixture.openCount == 0)
    }
}

// MARK: 물을 때 · 창 모양

extension NotificationPreferenceControllerTests {
    @Test(
        "B64N.S3-R3 예산을 정한 달이고 이 기기에서 아직 안 물었으면 묻는다",
        arguments: [BudgetStatus.none, .inProgress, .nearLimit, .reached, .exceeded]
    )
    func asksForBudgetedMonth(_ status: BudgetStatus) async throws {
        let fixture = try Fixture()
        await fixture.controller.refresh()

        #expect(fixture.controller.askVariant(for: makeBudget(status)) != nil)

        // 짝: 같은 상태라도 이 기기에서 이미 물었으면 묻지 않는다.
        let asked = try Fixture(asked: true)
        await asked.controller.refresh()
        #expect(asked.controller.askVariant(for: makeBudget(status)) == nil)
    }

    @Test("B64N.S3-R3 예산이 없는 달과 아직 못 읽은 달에서는 묻지 않는다")
    func doesNotAskWithoutBudget() async throws {
        let fixture = try Fixture()
        await fixture.controller.refresh()

        #expect(fixture.controller.askVariant(for: makeBudget(.notSet)) == nil)
        #expect(fixture.controller.askVariant(for: nil) == nil)
        // 짝: 같은 기기·같은 상태에서 예산을 정한 달이면 묻는다.
        #expect(fixture.controller.askVariant(for: makeBudget(.inProgress)) != nil)
    }

    @Test("B64N.S3-R3 창의 어느 답이든 같은 기기에서 다시 묻지 않는다", arguments: [
        NotificationAskAnswer.turnOn, .openSettings, .later
    ])
    func doesNotAskAgainAfterAnswer(_ answer: NotificationAskAnswer) async throws {
        let fixture = try Fixture(ios: .allowed)
        await fixture.controller.refresh()
        #expect(fixture.controller.askVariant(for: makeBudget(.inProgress)) != nil)

        await fixture.controller.answerAsk(answer)

        #expect(fixture.controller.askVariant(for: makeBudget(.inProgress)) == nil)
    }

    @Test("B64N.S3-R3 설정 줄을 누른 뒤에는 예산 탭에서 묻지 않는다")
    func doesNotAskAfterSettingsToggle() async throws {
        let fixture = try Fixture(ios: .allowed)
        await fixture.controller.refresh()
        #expect(fixture.controller.askVariant(for: makeBudget(.inProgress)) != nil)

        _ = await fixture.controller.toggleFromSettings()

        #expect(fixture.controller.askVariant(for: makeBudget(.inProgress)) == nil)
    }

    @Test("B64N.S3-R4 iOS 가 거부면 iOS 꺼짐 창(③), 아니면 기본 창(②)이다", arguments: [
        VariantCase(ios: .denied, variant: .iosOff),
        VariantCase(ios: .notDetermined, variant: .standard),
        VariantCase(ios: .allowed, variant: .standard)
    ])
    func variantFollowsIOS(_ variant: VariantCase) async throws {
        let fixture = try Fixture(ios: variant.ios)

        await fixture.controller.refresh()

        #expect(fixture.controller.askVariant(for: makeBudget(.inProgress)) == variant.variant)
    }
}

// MARK: 창의 답

extension NotificationPreferenceControllerTests {
    @Test("B64N.S3-R5 알림 받기는 iOS 가 안 물었으면 권한 창을 띄우고 답과 상관없이 켜짐으로 둔다", arguments: [
        NotificationAuthorization.allowed, .denied
    ])
    func turnOnRequestsWhenNotDetermined(_ answer: NotificationAuthorization) async throws {
        let fixture = try Fixture(ios: .notDetermined, requestResult: answer)
        await fixture.controller.refresh()

        await fixture.controller.answerAsk(.turnOn)

        #expect(fixture.permission.requestCount == 1)
        #expect(fixture.settings.isEnabled)
        #expect(fixture.settings.hasAsked)
        #expect(fixture.controller.authorization == answer)
        #expect(fixture.controller.isEffectivelyOn == (answer == .allowed))
        #expect(fixture.openCount == 0)
    }

    @Test("B64N.S3-R5 알림 받기는 iOS 가 이미 허용이면 권한 창 없이 켜짐이다")
    func turnOnWhenAllowedSkipsRequest() async throws {
        let fixture = try Fixture(ios: .allowed)
        await fixture.controller.refresh()

        await fixture.controller.answerAsk(.turnOn)

        #expect(fixture.permission.requestCount == 0)
        #expect(fixture.settings.isEnabled)
        #expect(fixture.settings.hasAsked)
        #expect(fixture.controller.isEffectivelyOn)
        #expect(fixture.openCount == 0)
    }

    @Test("B64N.S3-R5 알림 받기는 다시 읽어 iOS 거부로 바뀐 것을 보면 권한 창도 iOS 설정도 열지 않고 켜짐으로 둔다")
    func turnOnRereadsAndLeavesDenied() async throws {
        let fixture = try Fixture(ios: .notDetermined)
        await fixture.controller.refresh()
        #expect(fixture.controller.askVariant(for: makeBudget(.inProgress)) == .standard)
        fixture.permission.status = .denied

        await fixture.controller.answerAsk(.turnOn)

        #expect(fixture.permission.requestCount == 0)
        #expect(fixture.openCount == 0)
        #expect(fixture.settings.isEnabled)
        #expect(fixture.settings.hasAsked)
        #expect(fixture.controller.authorization == .denied)
        #expect(!fixture.controller.isEffectivelyOn)
    }

    @Test("B64N.S3-R5 설정 열기는 앱 알림을 켜짐으로 두고 iOS 설정을 연다", arguments: [
        NotificationAuthorization.denied, .allowed
    ])
    func openSettingsTurnsOnAndOpens(_ ios: NotificationAuthorization) async throws {
        let fixture = try Fixture(ios: ios)
        await fixture.controller.refresh()

        await fixture.controller.answerAsk(.openSettings)

        #expect(fixture.settings.isEnabled)
        #expect(fixture.settings.hasAsked)
        #expect(fixture.openCount == 1)
        #expect(fixture.permission.requestCount == 0)
        #expect(fixture.controller.isEffectivelyOn == (ios == .allowed))
    }

    @Test("B64N.S3-R5 나중에는 물어봤음만 남기고 꺼진 채 닫힌다")
    func laterKeepsOff() async throws {
        let fixture = try Fixture(ios: .notDetermined)
        await fixture.controller.refresh()

        await fixture.controller.answerAsk(.later)

        #expect(fixture.settings.hasAsked)
        #expect(!fixture.settings.isEnabled)
        #expect(fixture.permission.requestCount == 0)
        #expect(fixture.openCount == 0)
    }
}

// MARK: 기다리는 동안의 순서

extension NotificationPreferenceControllerTests {
    @Test("B64N.S3-R6 알림 받기는 iOS 권한을 기다리기 전에 물어봤음과 켜짐을 남긴다")
    func turnOnRecordsBeforeAwaiting() async throws {
        let fixture = try Fixture(ios: .notDetermined, requestResult: .allowed)
        await fixture.controller.refresh()
        #expect(fixture.controller.askVariant(for: makeBudget(.inProgress)) != nil)
        fixture.permission.holdNextRead()
        fixture.permission.holdNextRequest()

        let answering = Task { await fixture.controller.answerAsk(.turnOn) }
        await waitUntil { fixture.permission.isReadHeld }
        #expect(fixture.settings.hasAsked)
        #expect(fixture.settings.isEnabled)
        #expect(fixture.controller.askVariant(for: makeBudget(.inProgress)) == nil)

        fixture.permission.releaseRead()
        await waitUntil { fixture.permission.isRequestHeld }
        #expect(fixture.settings.hasAsked)
        #expect(fixture.settings.isEnabled)
        #expect(fixture.controller.askVariant(for: makeBudget(.inProgress)) == nil)

        fixture.permission.releaseRequest()
        await answering.value

        #expect(fixture.controller.authorization == .allowed)
        #expect(fixture.controller.isEffectivelyOn)
    }

    @Test("B64N.S3-R6 설정 줄은 다시 읽기 전에 물어봤음을, 권한 창 전에 켜짐을 남긴다")
    func toggleRecordsBeforeAwaiting() async throws {
        let fixture = try Fixture(ios: .notDetermined, requestResult: .allowed)
        await fixture.controller.refresh()
        fixture.permission.holdNextRead()
        fixture.permission.holdNextRequest()

        let toggling = Task { await fixture.controller.toggleFromSettings() }
        await waitUntil { fixture.permission.isReadHeld }
        #expect(fixture.settings.hasAsked)

        fixture.permission.releaseRead()
        await waitUntil { fixture.permission.isRequestHeld }
        #expect(fixture.settings.hasAsked)
        #expect(fixture.settings.isEnabled)

        fixture.permission.releaseRequest()
        let result = await toggling.value

        #expect(result == .turnedOn)
        #expect(fixture.openCount == 0)
    }
}

// MARK: 설정 줄

extension NotificationPreferenceControllerTests {
    @Test("B64N.S3-R7 설정 줄은 보이는 값이 켜짐이면 끄고, 꺼짐이면 켜되 iOS 가 막으면 권한 창이나 iOS 설정으로 간다",
          arguments: ToggleCase.all)
    func toggleChangesSettings(_ toggle: ToggleCase) async throws {
        let fixture = try Fixture(enabled: toggle.enabled, ios: toggle.ios, requestResult: toggle.requestResult)
        await fixture.controller.refresh()

        _ = await fixture.controller.toggleFromSettings()

        #expect(fixture.settings.isEnabled == toggle.enabledAfter)
        #expect(fixture.permission.requestCount == toggle.requests)
        #expect(fixture.openCount == toggle.opens)
        #expect(fixture.settings.hasAsked)
        if toggle.requests > 0 {
            #expect(fixture.controller.authorization == toggle.requestResult)
        }
        #expect(fixture.controller.isEffectivelyOn == toggle.isOnAfter)
    }

    @Test("B64N.S3-R8 설정 줄의 토스트는 보이는 값이 실제로 바뀔 때만 뜬다", arguments: ToggleCase.all)
    func toggleResultFollowsVisibleChange(_ toggle: ToggleCase) async throws {
        let fixture = try Fixture(enabled: toggle.enabled, ios: toggle.ios, requestResult: toggle.requestResult)
        await fixture.controller.refresh()

        let result = await fixture.controller.toggleFromSettings()

        #expect(result == toggle.result)
    }

    @Test("B64N.S3-R9 설정 줄을 누르면 판정 전에 iOS 권한을 다시 읽는다", arguments: [
        StaleCase(enabled: false, stale: .denied, actual: .allowed, result: .turnedOn, opens: 0, enabledAfter: true),
        StaleCase(enabled: false, stale: .allowed, actual: .denied, result: .unchanged, opens: 1, enabledAfter: true),
        StaleCase(enabled: true, stale: .allowed, actual: .denied, result: .unchanged, opens: 1, enabledAfter: true),
        StaleCase(enabled: true, stale: .denied, actual: .allowed, result: .turnedOff, opens: 0, enabledAfter: false)
    ])
    func toggleRereadsBeforeDeciding(_ stale: StaleCase) async throws {
        let fixture = try Fixture(enabled: stale.enabled, ios: stale.stale)
        await fixture.controller.refresh()
        fixture.permission.status = stale.actual

        let result = await fixture.controller.toggleFromSettings()

        #expect(result == stale.result)
        #expect(fixture.openCount == stale.opens)
        #expect(fixture.settings.isEnabled == stale.enabledAfter)
        #expect(fixture.permission.requestCount == 0)
    }
}

// MARK: 입력

extension NotificationPreferenceControllerTests {
    struct EffectiveCase: CustomTestStringConvertible {
        let enabled: Bool
        let ios: NotificationAuthorization
        let isOn: Bool

        var testDescription: String {
            "앱 \(enabled ? "켜짐" : "꺼짐") · iOS \(ios)"
        }
    }

    struct RefreshCase: CustomTestStringConvertible {
        let before: NotificationAuthorization
        let after: NotificationAuthorization

        var testDescription: String {
            "\(before) → \(after)"
        }
    }

    struct VariantCase: CustomTestStringConvertible {
        let ios: NotificationAuthorization
        let variant: NotificationAskVariant

        var testDescription: String {
            "iOS \(ios)"
        }
    }

    /// 권한 창을 띄우는 두 입구.
    enum Entry: CaseIterable {
        case askTurnOn, settingsToggle

        func run(_ controller: NotificationPreferenceController) async {
            switch self {
            case .askTurnOn:
                await controller.answerAsk(.turnOn)
            case .settingsToggle:
                _ = await controller.toggleFromSettings()
            }
        }
    }

    /// 설정 줄 경로 — R7 은 남은 상태를, R8 은 토스트를 본다. `requests` 가 0 이면 `requestResult` 는 쓰이지 않는다.
    struct ToggleCase: CustomTestStringConvertible {
        let enabled: Bool
        let ios: NotificationAuthorization
        var requestResult = NotificationAuthorization.allowed
        let enabledAfter: Bool
        let requests: Int
        let opens: Int
        let isOnAfter: Bool
        let result: NotificationToggleResult

        var testDescription: String {
            "앱 \(enabled ? "켜짐" : "꺼짐") · iOS \(ios)" + (requests > 0 ? " · 권한 창 \(requestResult)" : "")
        }

        static let all: [ToggleCase] = [
            // 보이는 값 켜짐 → 끈다
            ToggleCase(
                enabled: true,
                ios: .allowed,
                enabledAfter: false,
                requests: 0,
                opens: 0,
                isOnAfter: false,
                result: .turnedOff
            ),
            // 앱 설정만 꺼짐 → 켠다
            ToggleCase(
                enabled: false,
                ios: .allowed,
                enabledAfter: true,
                requests: 0,
                opens: 0,
                isOnAfter: true,
                result: .turnedOn
            ),
            // iOS 가 안 물음 → 권한 창 먼저(허용 · 거부)
            ToggleCase(
                enabled: false,
                ios: .notDetermined,
                requestResult: .allowed,
                enabledAfter: true,
                requests: 1,
                opens: 0,
                isOnAfter: true,
                result: .turnedOn
            ),
            ToggleCase(
                enabled: false,
                ios: .notDetermined,
                requestResult: .denied,
                enabledAfter: true,
                requests: 1,
                opens: 0,
                isOnAfter: false,
                result: .unchanged
            ),
            // iOS 거부 → 켜짐으로 두고 iOS 설정
            ToggleCase(
                enabled: false,
                ios: .denied,
                enabledAfter: true,
                requests: 0,
                opens: 1,
                isOnAfter: false,
                result: .unchanged
            ),
            // 앱은 켜짐인데 iOS 가 막아 보이는 값 꺼짐 → 켜는 경로(끄지 않는다)
            ToggleCase(
                enabled: true,
                ios: .denied,
                enabledAfter: true,
                requests: 0,
                opens: 1,
                isOnAfter: false,
                result: .unchanged
            ),
            ToggleCase(
                enabled: true,
                ios: .notDetermined,
                requestResult: .allowed,
                enabledAfter: true,
                requests: 1,
                opens: 0,
                isOnAfter: true,
                result: .turnedOn
            ),
            ToggleCase(
                enabled: true,
                ios: .notDetermined,
                requestResult: .denied,
                enabledAfter: true,
                requests: 1,
                opens: 0,
                isOnAfter: false,
                result: .unchanged
            )
        ]
    }

    /// 마지막 다시 읽기 뒤 iOS 설정에서 바꾸고, foreground 갱신보다 먼저 누른 경우.
    struct StaleCase: CustomTestStringConvertible {
        let enabled: Bool
        let stale: NotificationAuthorization
        let actual: NotificationAuthorization
        let result: NotificationToggleResult
        let opens: Int
        let enabledAfter: Bool

        var testDescription: String {
            "앱 \(enabled ? "켜짐" : "꺼짐") · 읽은 값 \(stale) · 실제 \(actual)"
        }
    }
}

// MARK: 예산 탭이 창을 띄우기 전 다시 읽기

extension NotificationPreferenceControllerTests {
    @Test("B64N.S4-R4 iOS 권한을 다시 읽는 사이 작업이 취소되면 정한 달·안 물음이어도 창을 띄우지 않는다")
    func askIfNeededDropsWhenCancelledWhileReading() async throws {
        let fixture = try Fixture(ios: .allowed)
        fixture.permission.holdNextRead()
        let asking = Task { await fixture.controller.askIfNeeded(for: makeBudget(.inProgress)) }
        await waitUntil { fixture.permission.isReadHeld }

        // 기다리는 사이 가림이 생기거나 탭이 바뀌어 화면이 작업을 거뒀다.
        asking.cancel()
        fixture.permission.releaseRead()

        #expect(await asking.value == nil)
        #expect(!fixture.settings.hasAsked)
    }

    @Test("B64N.S4-R4 짝: 취소하지 않으면 다시 읽은 iOS 권한으로 창 모양을 정한다", arguments: [
        VariantCase(ios: .allowed, variant: .standard),
        VariantCase(ios: .denied, variant: .iosOff)
    ])
    func askIfNeededUsesRereadAuthorization(_ variant: VariantCase) async throws {
        let fixture = try Fixture(ios: variant.ios)
        fixture.permission.holdNextRead()
        let asking = Task { await fixture.controller.askIfNeeded(for: makeBudget(.inProgress)) }
        await waitUntil { fixture.permission.isReadHeld }
        // 다시 읽기 전에는 iOS 권한을 모른다 — 이 값으로 정하면 거부여도 기본 창(②)이다.
        #expect(fixture.controller.authorization == .notDetermined)

        fixture.permission.releaseRead()

        #expect(await asking.value == variant.variant)
        #expect(fixture.permission.readCount == 1)
    }

    @Test("B64N.S4-R4 예산이 없는 달과 아직 못 읽은 달에서는 다시 읽은 뒤에도 창을 띄우지 않는다")
    func askIfNeededSkipsWithoutBudget() async throws {
        let fixture = try Fixture(ios: .allowed)

        #expect(await fixture.controller.askIfNeeded(for: makeBudget(.notSet)) == nil)
        #expect(await fixture.controller.askIfNeeded(for: nil) == nil)
        // 짝: 같은 기기에서 예산을 정한 달이면 띄운다.
        #expect(await fixture.controller.askIfNeeded(for: makeBudget(.inProgress)) == .standard)
    }
}

// MARK: 가짜

/// 테스트 하나가 쓰는 설정·가짜 iOS 권한·컨트롤러.
@MainActor
private final class Fixture {
    let settings: NotificationSettingsStore
    let permission: FakePermission
    let controller: NotificationPreferenceController
    private let opener = OpenCounter()
    private let suiteName: String

    var openCount: Int {
        opener.count
    }

    init(
        enabled: Bool = false,
        asked: Bool = false,
        ios: NotificationAuthorization = .notDetermined,
        requestResult: NotificationAuthorization = .allowed
    ) throws {
        let suiteName = "woni_appTests.NotificationPreferenceControllerTests.\(UUID().uuidString)"
        self.suiteName = suiteName
        settings = try NotificationSettingsStore(userDefaults: #require(UserDefaults(suiteName: suiteName)))
        settings.isEnabled = enabled
        settings.hasAsked = asked
        permission = FakePermission(status: ios, requestResult: requestResult)
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
private final class OpenCounter {
    var count = 0
}

/// 기기의 iOS 권한. 다시 읽기(여럿)와 권한 창을 붙잡았다 풀 수 있다.
@MainActor
private final class FakePermission: NotificationPermissionProviding {
    /// 지금 기기의 값. 권한 창의 답으로 바뀐다.
    var status: NotificationAuthorization
    /// iOS 권한 창의 답.
    let requestResult: NotificationAuthorization
    private(set) var readCount = 0
    private(set) var requestCount = 0
    private var holdsRead = false
    private var holdsRequest = false
    /// 붙잡힌 다시 읽기, 먼저 붙잡힌 것이 앞이다.
    private var heldReads: [CheckedContinuation<Void, Never>] = []
    private var heldRequest: CheckedContinuation<Void, Never>?

    init(status: NotificationAuthorization, requestResult: NotificationAuthorization) {
        self.status = status
        self.requestResult = requestResult
    }

    var isReadHeld: Bool {
        !heldReads.isEmpty
    }

    var heldReadCount: Int {
        heldReads.count
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

    /// 붙잡힌 다시 읽기 중 가장 먼저 붙잡힌 것을 푼다.
    func releaseRead() {
        guard !heldReads.isEmpty else {
            return
        }
        heldReads.removeFirst().resume()
    }

    func releaseRequest() {
        heldRequest?.resume()
        heldRequest = nil
    }

    /// 읽은 때의 값을 돌려준다 — 붙잡힌 동안 바뀐 값은 모른다.
    func authorization() async -> NotificationAuthorization {
        readCount += 1
        let value = status
        if holdsRead {
            holdsRead = false
            await withCheckedContinuation { heldReads.append($0) }
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

/// 붙잡은 자리까지 작업이 오도록 main actor 를 돌린다.
@MainActor
private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    var tries = 0
    while !condition(), tries < 1000 {
        await Task.yield()
        tries += 1
    }
    #expect(condition(), "붙잡은 자리에 닿지 않았다", sourceLocation: sourceLocation)
}

/// 보이는 달의 응답. 묻는 판정은 상태만 본다 — `.notSet` 은 예산이 없는 달이다.
@MainActor
private func makeBudget(_ status: BudgetStatus) -> MonthlyBudget {
    let isSet = status != .notSet
    return MonthlyBudget(
        year: 2026,
        month: 10,
        currentYear: 2026,
        currentMonth: 10,
        remainingDaysIncludingToday: 7,
        hasAnyBudget: isSet,
        status: status,
        currency: isSet ? .krw : nil,
        total: nil,
        paymentGroups: [],
        categories: [],
        otherCategories: nil,
        missingRateCount: 0,
        dailyAllowance: nil
    )
}
