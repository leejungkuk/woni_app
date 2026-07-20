//
//  ConnectivityMonitorTests.swift
//  woni_appTests
//

import Testing
@testable import woni_app

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ConnectivityMonitorTests {
    @Test("Fake 연결성 모니터는 오프라인에서 온라인으로의 전이를 스트림과 현재 상태에 반영한다")
    func fakePublishesOfflineToOnlineTransition() async {
        let monitor = FakeConnectivityMonitor(isOnline: false)
        var changes = monitor.changes.makeAsyncIterator()

        #expect(monitor.isOnline == false)

        monitor.setOnline(true)

        let transition = await changes.next()

        #expect(transition == true)
        #expect(monitor.isOnline)
    }

    @Test("Fake는 동일 상태 반복 설정을 전이로 방출하지 않는다(dedup)")
    func fakeDedupsRepeatedSameState() async {
        let monitor = FakeConnectivityMonitor(isOnline: false)
        var changes = monitor.changes.makeAsyncIterator()

        monitor.setOnline(true) // 전이 1
        monitor.setOnline(true) // no-op (dedup)
        monitor.setOnline(false) // 전이 2

        // 중복 방출됐다면 두 번째 값이 true여야 하지만, dedup되어 false가 이어진다.
        #expect(await changes.next() == true)
        #expect(await changes.next() == false)
        #expect(monitor.isOnline == false)
    }

    @Test("ConnectivityBroadcaster는 모든 구독자에게 전이를 팬아웃한다")
    func broadcasterFansOutToAllSubscribers() async {
        let broadcaster = ConnectivityBroadcaster()
        var first = broadcaster.changes.makeAsyncIterator()
        var second = broadcaster.changes.makeAsyncIterator()

        #expect(broadcaster.subscriberCount == 2)

        broadcaster.broadcast(true)

        #expect(await first.next() == true)
        #expect(await second.next() == true)
    }

    @Test("ConnectivityBroadcaster.finishAll은 스트림을 종료하고 구독자를 비운다")
    func broadcasterFinishAllEndsStreamsAndClearsSubscribers() async {
        let broadcaster = ConnectivityBroadcaster()
        var iterator = broadcaster.changes.makeAsyncIterator()

        #expect(broadcaster.subscriberCount == 1)

        broadcaster.finishAll()

        #expect(await iterator.next() == nil)
        #expect(broadcaster.subscriberCount == 0)
    }
}
