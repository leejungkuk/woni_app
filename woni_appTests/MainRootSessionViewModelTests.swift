import Foundation
import Testing
@testable import woni_app

@MainActor
struct MainRootSessionViewModelTests {
    @Test("원격 무효화 안내는 홈 reload와 navigation root reset을 한 번만 요청하고 확인 뒤 해제된다")
    func remoteLogoutReloadsAndResetsOnceUntilAcknowledged() async {
        let auth = FakeAuthService()
        let coordinator = makeTestSessionCoordinator(authProvider: auth)
        var reloadCount = 0
        let viewModel = MainRootSessionViewModel(
            coordinator: coordinator,
            reloadMain: { reloadCount += 1 }
        )

        await coordinator.handleRemoteSessionInvalidation()
        #expect(viewModel.isRemoteLogoutAlertPresented)

        await viewModel.handleRemoteLogoutNoticeChange(true)
        await viewModel.handleRemoteLogoutNoticeChange(true)

        #expect(reloadCount == 1)
        #expect(viewModel.navigationResetGeneration == 1)
        #expect(viewModel.isRemoteLogoutAlertPresented)

        viewModel.acknowledgeRemoteLogoutNotice()
        await viewModel.handleRemoteLogoutNoticeChange(false)

        #expect(!viewModel.isRemoteLogoutAlertPresented)
        #expect(!coordinator.remoteLogoutNotice)
    }

    @Test("cleanupRequired는 이전 계정 데이터 대신 전역 차단 상태를 노출한다")
    func cleanupRequiredBlocksMainContent() {
        let auth = FakeAuthService()
        let marker = InMemoryLogoutCleanupMarker()
        marker.markPending()
        let coordinator = makeTestSessionCoordinator(
            authProvider: auth,
            cleanupMarker: marker
        )
        let viewModel = MainRootSessionViewModel(
            coordinator: coordinator,
            reloadMain: {}
        )

        #expect(coordinator.logoutState == .cleanupRequired)
        #expect(viewModel.isCleanupBlocking)
    }

    @Test("foreground 활성화는 pending push, 코디네이터 프로브, 환율 프리페치 순서로 호출한다")
    func foregroundActivationPushesThenProbesThenPrefetches() async {
        let recorder = ForegroundActivationOrderRecorder()
        let sync = ForegroundLoginSyncSpy(onPush: { recorder.record("push") })
        let auth = FakeAuthService(
            probeSessionValidityHandler: {
                recorder.record("probe")
                return false
            }
        )
        let coordinator = makeTestSessionCoordinator(authProvider: auth)

        await AppDependencies.handleForegroundActivation(
            sync: sync,
            coordinator: coordinator,
            prefetchRates: { recorder.record("prefetch") }
        )

        #expect(sync.pushCount == 1)
        #expect(auth.probeSessionValidityCount == 1)
        #expect(recorder.snapshot() == ["push", "probe", "prefetch"])
    }
}

@MainActor
private final class ForegroundLoginSyncSpy: LoginSyncing {
    private let onPush: () -> Void
    private(set) var pushCount = 0

    init(onPush: @escaping () -> Void = {}) {
        self.onPush = onPush
    }

    func beginAccountSwitch() async throws {}
    func finishAccountSwitch(expectedMemberID _: UUID) async -> Bool {
        true
    }

    func resumeAccountSwitch(expectedMemberID _: UUID?) -> Bool {
        true
    }

    func pushPending() async {
        pushCount += 1
        onPush()
    }

    func restoreAll() async throws {}
}

private final class ForegroundActivationOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func record(_ event: String) {
        lock.withLock {
            events.append(event)
        }
    }

    func snapshot() -> [String] {
        lock.withLock { events }
    }
}
