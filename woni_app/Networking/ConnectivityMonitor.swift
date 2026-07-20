//
//  ConnectivityMonitor.swift
//  woni_app
//

import Foundation
import Network
import Observation

@MainActor
protocol ConnectivityObserving: AnyObject {
    var isOnline: Bool { get }
    var changes: AsyncStream<Bool> { get }
}

/// 연결성 전이를 다중 구독자에게 팬아웃하는 공용 브로드캐스터.
/// `changes` 구독 등록·종료 정리와 전이 브로드캐스트를 production(`ConnectivityMonitor`)과
/// 테스트용(`FakeConnectivityMonitor`)이 공유해, continuation 관리 로직의 중복·드리프트를
/// 없애고 실제 팬아웃 동작을 직접 단위 테스트할 수 있게 한다.
@MainActor
final class ConnectivityBroadcaster {
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    /// 새 구독 스트림. 접근할 때마다 새 구독이 등록되므로 구독자는 한 번만 읽어 보관한다.
    var changes: AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// 현재 구독자 수. 종료된 구독의 정리 검증용(테스트 지원).
    var subscriberCount: Int {
        continuations.count
    }

    func broadcast(_ isOnline: Bool) {
        continuations.values.forEach { $0.yield(isOnline) }
    }

    func finishAll() {
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }

    deinit {
        continuations.values.forEach { $0.finish() }
    }
}

/// `NWPathMonitor`의 백그라운드 업데이트를 메인 액터 상태와 전이 스트림으로 노출한다.
/// path 갱신은 단일 `AsyncStream`으로 모아 **하나의 MainActor 소비 Task**가 순차 처리하므로,
/// 이벤트마다 별도 `Task`를 띄울 때 생기는 도착 순서 역전(빠른 flapping 시 잘못된 최종 상태
/// 고착)을 원천 차단한다. 소비처(step5 SyncEngine)가 전이 순서를 그대로 신뢰할 수 있다.
@Observable
@MainActor
final class ConnectivityMonitor: ConnectivityObserving {
    private(set) var isOnline: Bool

    @ObservationIgnored private let pathMonitor: NWPathMonitor
    @ObservationIgnored private let monitorQueue: DispatchQueue
    @ObservationIgnored private let broadcaster = ConnectivityBroadcaster()
    @ObservationIgnored private let pathStatusContinuation: AsyncStream<Bool>.Continuation
    @ObservationIgnored private var consumeTask: Task<Void, Never>?

    var changes: AsyncStream<Bool> {
        broadcaster.changes
    }

    init() {
        isOnline = false
        pathMonitor = NWPathMonitor()
        monitorQueue = DispatchQueue(label: "woni.connectivity-monitor")

        let (pathStatuses, continuation) = AsyncStream.makeStream(of: Bool.self)
        pathStatusContinuation = continuation

        // NWPathMonitor는 직렬 monitorQueue에서 순서대로 콜백하고, AsyncStream은 그 순서를
        // 보존한다. 단일 소비 Task가 for-await로 순차 적용하므로 전이 순서가 유지된다.
        pathMonitor.pathUpdateHandler = { path in
            continuation.yield(path.status == .satisfied)
        }
        consumeTask = Task { @MainActor [weak self] in
            for await isOnline in pathStatuses {
                self?.update(isOnline: isOnline)
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    deinit {
        pathMonitor.cancel()
        pathStatusContinuation.finish()
        consumeTask?.cancel()
    }

    /// 상태가 실제로 바뀔 때만 저장값을 갱신하고 구독자에게 전이를 전달한다.
    private func update(isOnline: Bool) {
        guard self.isOnline != isOnline else {
            return
        }

        self.isOnline = isOnline
        broadcaster.broadcast(isOnline)
    }
}

/// 실제 네트워크 경로에 의존하지 않고 연결성 전이를 주입하는 테스트 지원 구현.
/// production과 동일한 `ConnectivityBroadcaster`로 팬아웃해 전이 시맨틱을 공유한다.
@MainActor
final class FakeConnectivityMonitor: ConnectivityObserving {
    private(set) var isOnline: Bool
    private let broadcaster = ConnectivityBroadcaster()

    var changes: AsyncStream<Bool> {
        broadcaster.changes
    }

    init(isOnline: Bool = false) {
        self.isOnline = isOnline
    }

    func setOnline(_ isOnline: Bool) {
        guard self.isOnline != isOnline else {
            return
        }

        self.isOnline = isOnline
        broadcaster.broadcast(isOnline)
    }
}
