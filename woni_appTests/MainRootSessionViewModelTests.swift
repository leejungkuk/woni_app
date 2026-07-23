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

    @Test("foreground 활성화는 pending push, 코디네이터 프로브, pull, 환율 프리페치 순서로 호출한다")
    func foregroundActivationPushesThenProbesThenPullsThenPrefetches() async {
        let recorder = ForegroundActivationOrderRecorder()
        let sync = ForegroundSyncSpy(
            onPush: { recorder.record("push") },
            onPull: { recorder.record("pull") }
        )
        let auth = FakeAuthService(
            probeSessionValidityHandler: {
                recorder.record("probe")
                return true
            }
        )
        let coordinator = makeTestSessionCoordinator(authProvider: auth)

        await AppDependencies.handleForegroundActivation(
            sync: sync,
            coordinator: coordinator,
            prefetchRates: { recorder.record("prefetch") }
        )

        #expect(sync.pushCount == 1)
        #expect(sync.pullCount == 1)
        #expect(auth.probeSessionValidityCount == 1)
        #expect(recorder.snapshot() == ["push", "probe", "pull", "prefetch"])
    }

    @Test("foreground pull 실패 뒤에도 환율 프리페치를 계속한다")
    func foregroundActivationContinuesAfterPullFailure() async {
        let recorder = ForegroundActivationOrderRecorder()
        let sync = ForegroundSyncSpy(
            pullError: ForegroundSyncSpyError.pullFailed,
            onPull: { recorder.record("pull") }
        )
        let auth = FakeAuthService(probeSessionValidityHandler: { true })
        let coordinator = makeTestSessionCoordinator(authProvider: auth)

        await AppDependencies.handleForegroundActivation(
            sync: sync,
            coordinator: coordinator,
            prefetchRates: { recorder.record("prefetch") }
        )

        #expect(sync.pullCount == 1)
        #expect(recorder.snapshot() == ["pull", "prefetch"])
    }

    @Test("foreground 프로브가 세션 무효화를 감지하면 pull을 건너뛴다")
    func foregroundActivationSkipsPullAfterInvalidation() async {
        let recorder = ForegroundActivationOrderRecorder()
        let sync = ForegroundSyncSpy(onPull: { recorder.record("pull") })
        let auth = FakeAuthService(probeSessionValidityHandler: { false })
        let coordinator = makeTestSessionCoordinator(authProvider: auth)

        await AppDependencies.handleForegroundActivation(
            sync: sync,
            coordinator: coordinator,
            prefetchRates: { recorder.record("prefetch") }
        )

        #expect(sync.pullCount == 0)
        #expect(recorder.snapshot() == ["prefetch"])
    }

    @Test("첫 foreground 체인이 probe 중이면 다음 활성화는 전체 체인에 합류한다")
    func overlappingForegroundActivationsJoinEntireChain() async {
        let probeGate = ForegroundActivationGate()
        let secondStarted = ForegroundActivationGate()
        let sync = ForegroundSyncSpy()
        let auth = FakeAuthService(probeSessionValidityHandler: {
            await probeGate.hold()
            return true
        })
        let coordinator = makeTestSessionCoordinator(authProvider: auth)
        let runner = ForegroundActivationRunner()
        var prefetchCount = 0

        let first = Task {
            await runner.run {
                await AppDependencies.handleForegroundActivation(
                    sync: sync,
                    coordinator: coordinator,
                    prefetchRates: { prefetchCount += 1 }
                )
            }
        }
        await probeGate.waitUntilHeld()

        let second = Task {
            secondStarted.signal()
            await runner.run {
                await AppDependencies.handleForegroundActivation(
                    sync: sync,
                    coordinator: coordinator,
                    prefetchRates: { prefetchCount += 1 }
                )
            }
        }
        await secondStarted.waitUntilHeld()
        await Task.yield()

        #expect(sync.pushCount == 1)
        #expect(auth.probeSessionValidityCount == 1)
        #expect(sync.pullCount == 0)

        probeGate.release()
        await first.value
        await second.value

        #expect(sync.pushCount == 1)
        #expect(auth.probeSessionValidityCount == 1)
        #expect(sync.pullCount == 1)
        #expect(prefetchCount == 1)
    }

    @Test("첫 foreground 체인이 끝난 뒤 다음 활성화는 새 체인을 시작한다")
    func sequentialForegroundActivationsStartNewChains() async {
        let sync = ForegroundSyncSpy()
        let auth = FakeAuthService(probeSessionValidityHandler: { true })
        let coordinator = makeTestSessionCoordinator(authProvider: auth)
        let runner = ForegroundActivationRunner()
        var prefetchCount = 0

        for _ in 0 ..< 2 {
            await runner.run {
                await AppDependencies.handleForegroundActivation(
                    sync: sync,
                    coordinator: coordinator,
                    prefetchRates: { prefetchCount += 1 }
                )
            }
        }

        #expect(sync.pushCount == 2)
        #expect(auth.probeSessionValidityCount == 2)
        #expect(sync.pullCount == 2)
        #expect(prefetchCount == 2)
    }
}

@MainActor
private final class ForegroundSyncSpy: ForegroundSyncing {
    private let onPush: () -> Void
    private let onPull: () -> Void
    private let pullError: Error?
    private(set) var pushCount = 0
    private(set) var pullCount = 0

    init(
        pullError: Error? = nil,
        onPush: @escaping () -> Void = {},
        onPull: @escaping () -> Void = {}
    ) {
        self.pullError = pullError
        self.onPush = onPush
        self.onPull = onPull
    }

    func pushPending() async {
        pushCount += 1
        onPush()
    }

    func pullChanges() async throws {
        pullCount += 1
        onPull()
        if let pullError {
            throw pullError
        }
    }
}

@MainActor
private final class ForegroundActivationGate {
    private var heldContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isHeld = false

    func hold() async {
        signal()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func signal() {
        isHeld = true
        heldContinuation?.resume()
        heldContinuation = nil
    }

    func waitUntilHeld() async {
        guard !isHeld else {
            return
        }
        await withCheckedContinuation { heldContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
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

private enum ForegroundSyncSpyError: Error {
    case pullFailed
}
