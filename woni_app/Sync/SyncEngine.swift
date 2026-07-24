//
//  SyncEngine.swift
//  woni_app
//

import Foundation
import OSLog

/// 로컬 pending 거래를 서버에 FIFO로 push한다.
///
/// MainActor 직렬화와 단일 in-flight task로 명시 호출·온라인 전이가 겹쳐도 같은 작업에
/// 합류한다. 신원별 최초 성공 import(또는 conflict 확립) 뒤에는 건별 멱등 sync만 사용한다.
@MainActor
final class SyncEngine {
    nonisolated static let logger = Logger(subsystem: "woni_app", category: "Sync")
    /// openapi ImportLedgerEntriesRequest.entries @Size(max=1000) 계약.
    private static let maxImportEntries = 1000
    /// restore/changes OpenAPI size maximum.
    private static let pullPageSize = 500

    private let repository: TransactionRepository
    private let ledgerService: LedgerService
    private let authProvider: any AuthProviding
    private let connectivity: any ConnectivityObserving
    private let inFlightJoinObserver: (() -> Void)?
    private let applyServerConfirmedFailure: ((UUID) throws -> Void)?
    private let pushDebounce: Duration
    private let ledgerChangeBroadcaster = LedgerChangeBroadcaster()

    private var inFlightPush: Task<Void, Never>?
    private var inFlightPull: Task<Void, Error>?
    private var connectivityTask: Task<Void, Never>?
    private var debouncedPushTask: Task<Void, Never>?
    private(set) var isPushSuspended = false
    private var acceptsLocalWrites = true
    private var activeLocalWriteCount = 0
    private var localWriteWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldRerunPush = false

    private(set) var ledgerRevision = 0

    var ledgerDidChange: AsyncStream<Void> {
        ledgerChangeBroadcaster.changes
    }

    init(
        repository: TransactionRepository,
        ledgerService: LedgerService,
        authProvider: any AuthProviding,
        connectivity: any ConnectivityObserving,
        inFlightJoinObserver: (() -> Void)? = nil,
        applyServerConfirmedFailure: ((UUID) throws -> Void)? = nil,
        pushDebounce: Duration = .milliseconds(350)
    ) {
        self.repository = repository
        self.ledgerService = ledgerService
        self.authProvider = authProvider
        self.connectivity = connectivity
        self.inFlightJoinObserver = inFlightJoinObserver
        self.applyServerConfirmedFailure = applyServerConfirmedFailure
        self.pushDebounce = pushDebounce

        let changes = connectivity.changes
        connectivityTask = Task { [weak self] in
            for await isOnline in changes {
                guard !Task.isCancelled else {
                    return
                }
                if isOnline {
                    await self?.pushPending()
                }
            }
        }
    }

    deinit {
        connectivityTask?.cancel()
        inFlightPush?.cancel()
        debouncedPushTask?.cancel()
    }

    /// 연속 로컬 쓰기를 한 번의 push 시도로 합친다. 오프라인이면 만료 시 no-op이고,
    /// 이후 온라인 전이가 별도 트리거가 되어 pending을 전송한다.
    private func schedulePushPending() {
        debouncedPushTask?.cancel()
        let delay = pushDebounce
        debouncedPushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.pushPending()
        }
    }

    func performLocalWrite(_ operation: @escaping () async throws -> Void) async throws {
        guard acceptsLocalWrites else {
            throw SyncEngineError.localWritesSuspended
        }
        activeLocalWriteCount += 1
        do {
            try await operation()
            if inFlightPush != nil {
                shouldRerunPush = true
            }
            finishLocalWrite()
            schedulePushPending()
        } catch {
            finishLocalWrite()
            throw error
        }
    }

    /// 온라인일 때만 push를 시작한다. 이미 실행 중이면 그 작업 완료에 합류한다.
    func pushPending() async {
        guard connectivity.isOnline, !isPushSuspended else {
            return
        }
        if let inFlightPush {
            inFlightJoinObserver?()
            await inFlightPush.value
            return
        }

        let task = Task { [weak self] in
            guard let self else {
                return
            }
            var capturedMemberID: UUID?
            // 재실행 pass의 performPush는 최초 진입과 동일하게 신원을 새로 캡처한다. 이 구조의
            // 안전 근거는 SyncEngine 밖의 호출 규약이다: 신원을 실제로 바꾸는 호출부
            // (LoginViewModel.confirmSignIn의 signIn, SessionTransitionCoordinator.
            // runLogoutCleanup의 signOut/ensureIdentity)는 suspend 게이트(beginAccountSwitch·
            // suspendPushForLogout)를 먼저 완료한 뒤에만 신원을 바꾸고, 그 게이트는 이 task의
            // 완전 종료를 기다린다. suspend 없이 신원을 바꾸는 호출부가 추가되면 이 루프가
            // 이전 계정의 큐를 새 신원으로 전송할 수 있다.
            repeat {
                capturedMemberID = await self.performPush()
            } while self.consumePushRerun(capturedMemberID: capturedMemberID)
            // in-flight 표식 정리를 task의 마지막 in-actor 문으로 둔다. 그래야 이 task의
            // `.value`를 기다린 다른 대기자(계정 전환 begin 등)가 재개될 때 이미 nil을 관측해,
            // 완료된 task를 여전히 in-flight로 오인해 후속 push를 건너뛰는 경쟁을 없앤다.
            self.inFlightPush = nil
        }
        inFlightPush = task
        await task.value
    }

    /// 로그아웃의 sign-out→local clear→새 익명 신원 순서와 push가 교차하지 않게 한다.
    func suspendPushForLogout() async {
        isPushSuspended = true
        acceptsLocalWrites = false
        debouncedPushTask?.cancel()
        debouncedPushTask = nil
        if let inFlightPush {
            await inFlightPush.value
        }
        if let inFlightPull {
            try? await inFlightPull.value
        }
        if activeLocalWriteCount > 0 {
            await withCheckedContinuation { continuation in
                localWriteWaiters.append(continuation)
            }
        }
    }

    func resumePushAfterLogout() {
        isPushSuspended = false
        acceptsLocalWrites = true
    }

    /// 계정 전환 중 다른 신원으로 sync가 교차하지 않도록 새 작업을 중단하고,
    /// 진행 중인 push와 pull이 정착하면 이전 신원의 pull 커서를 삭제한다.
    func beginAccountSwitch() async throws {
        isPushSuspended = true
        if let inFlightPush {
            await inFlightPush.value
        }
        if let inFlightPull {
            try? await inFlightPull.value
        }
        try await repository.setPullCursor(nil)
    }

    /// 인증 신원이 전환 대상과 일치할 때만 push를 재개해 대상 계정으로 pending 행을 병합한다.
    /// 신원이 달라졌다면 fail-closed로 suspend를 유지한다.
    func finishAccountSwitch(expectedMemberID: UUID) async -> Bool {
        guard authProvider.currentUserID == expectedMemberID else {
            return false
        }
        isPushSuspended = false
        await pushPending()
        return true
    }

    /// 계정 전환 실패·포기 경로에서 안전한 신원 상태일 때만 push suspension을 해제한다.
    /// 이 메서드는 push를 직접 시작하지 않는다.
    func resumeAccountSwitch(expectedMemberID: UUID?) -> Bool {
        let currentMemberID = authProvider.currentUserID
        guard currentMemberID == nil
            || authProvider.isAnonymous
            || currentMemberID == expectedMemberID
        else {
            return false
        }
        isPushSuspended = false
        return true
    }

    /// 로그인 전환·기기 복원 경계에서 서버의 모든 항목을 순회하며 매치되는 로컬 행은 필드 전체를 서버 값으로
    /// upsert한다. 서버 응답에 없는 로컬 전용 행은 삭제하지 않는다(tombstone 없음). pullChanges의 좁은
    /// 확정 갱신과 달리 전체 필드를 덮는 것은 이 경계에서 서버가 SSOT이고 보존할 미푸시 편집이 없다는 호출자
    /// 전제에 기댄다(코드가 강제하지는 않음).
    func restoreAll() async throws {
        var didApplyLedgerChange = false
        defer {
            if didApplyLedgerChange {
                publishLedgerChange()
            }
        }

        try await preparePull()
        var cursor: RestoreCursor?

        while true {
            let page = try await ledgerService.restore(
                cursorDate: cursor?.transactionDate,
                cursorId: cursor?.id,
                size: Self.pullPageSize
            )
            for entry in page.entries {
                guard let transaction = try entry.toDomain() else {
                    continue
                }
                if try await repository.applyServerEntry(transaction, fullReplace: true) {
                    didApplyLedgerChange = true
                }
            }

            guard page.hasNext else {
                return
            }
            guard let nextCursor = page.nextCursor, nextCursor != cursor else {
                throw SyncEngineError.invalidRestoreCursorProgress
            }
            cursor = nextCursor
        }
    }

    /// 저장한 `(updatedAt, id)`부터 서버 확정 변경을 멱등 적용하고 커서를 페이지마다 영속한다.
    func pullChanges() async throws {
        guard authProvider.currentUserID != nil else {
            Self.logger.debug("Skipping pull changes because no current identity is available.")
            return
        }
        guard connectivity.isOnline else {
            Self.logger.debug("Skipping pull changes while offline.")
            return
        }
        guard !isPushSuspended else {
            Self.logger.debug("Skipping pull changes while sync is suspended.")
            return
        }
        if let inFlightPull {
            inFlightJoinObserver?()
            try? await inFlightPull.value
            return
        }

        let task = Task { [self] in
            defer { inFlightPull = nil }
            guard let pullMemberID = authProvider.currentUserID, !isPushSuspended else {
                Self.logger.debug("Stopping pull changes before start because its context changed.")
                return
            }
            try await performPullChanges(memberID: pullMemberID)
        }
        inFlightPull = task
        try await task.value
    }
}

private extension SyncEngine {
    func performPullChanges(memberID: UUID) async throws {
        var didApplyLedgerChange = false
        defer {
            if didApplyLedgerChange {
                publishLedgerChange()
            }
        }

        var cursor = try await repository.pullCursor()
        while true {
            let page = try await ledgerService.changes(
                cursorUpdatedAt: cursor?.updatedAt,
                cursorId: cursor?.id,
                size: Self.pullPageSize
            )
            guard authProvider.currentUserID == memberID, !isPushSuspended else {
                Self.logger.debug("Stopping pull changes before applying a page because its context changed.")
                return
            }

            for entry in page.entries {
                guard let transaction = try entry.toDomain() else {
                    continue
                }
                if try await repository.applyServerEntry(transaction, fullReplace: false) {
                    didApplyLedgerChange = true
                }
            }

            if let nextCursor = page.nextCursor {
                let next = SyncPullCursor(updatedAt: nextCursor.updatedAt, id: nextCursor.id)
                guard next != cursor || !page.hasMore else {
                    throw SyncEngineError.invalidChangesCursorProgress
                }
                guard authProvider.currentUserID == memberID, !isPushSuspended else {
                    Self.logger.debug("Stopping pull changes before saving its cursor because its context changed.")
                    return
                }
                try await repository.setPullCursor(next)
                cursor = next
            } else if page.hasMore {
                throw SyncEngineError.missingChangesCursor
            }

            guard page.hasMore else {
                return
            }
        }
    }

    func preparePull() async throws {
        guard connectivity.isOnline else {
            throw SyncEngineError.offline
        }
        try await authProvider.ensureIdentity()
        guard authProvider.currentUserID != nil else {
            throw SyncEngineError.missingIdentity
        }
    }

    func performPush() async -> UUID? {
        var didApplyLedgerChange = false
        var capturedMemberID: UUID?
        defer {
            if didApplyLedgerChange {
                publishLedgerChange()
            }
        }

        do {
            let pendingEntries = try await repository.pendingPushEntries()
            let pendingDeleteIDs = try await repository.pendingDeleteClientEntryIDs()
            guard !pendingEntries.isEmpty || !pendingDeleteIDs.isEmpty else {
                return nil
            }
            try await authProvider.ensureIdentity()
            guard let memberID = authProvider.currentUserID else {
                return nil
            }
            capturedMemberID = memberID

            for clientEntryID in try await repository.pendingDeleteClientEntryIDs() {
                guard isPushContextValid(memberID: memberID) else {
                    return capturedMemberID
                }
                try await ledgerService.deleteSynced(clientEntryID: clientEntryID)
                guard isPushContextValid(memberID: memberID) else {
                    return capturedMemberID
                }
                try await repository.removeFromDeleteQueue(clientEntryIDs: [clientEntryID])
            }

            guard isPushContextValid(memberID: memberID) else {
                return capturedMemberID
            }
            guard try await !repository.pendingPushEntries().isEmpty else {
                return capturedMemberID
            }

            if try await repository.isImportDone(memberID: memberID) {
                _ = try await pushIncrementally(memberID: memberID) {
                    didApplyLedgerChange = true
                }
            } else {
                _ = try await pushInitialImport(memberID: memberID) {
                    didApplyLedgerChange = true
                }
            }
        } catch {
            // 이벤트 기반 재트리거에서 pending 상태로 재개한다. 호출부 UI 오류 상태는 step8 경계다.
        }
        return capturedMemberID
    }

    func pushInitialImport(memberID: UUID, onLedgerChange: () -> Void) async throws -> Bool {
        let entries = try await repository.pendingPushEntries()
        let importEntries = Array(entries.prefix(Self.maxImportEntries))
        let items = importEntries.map(ImportLedgerEntryItem.init(transaction:))
        let pushedPayloads = Dictionary(
            uniqueKeysWithValues: importEntries.map {
                ($0.clientEntryID, TransactionRepository.PushedPayload(transaction: $0))
            }
        )
        let response: ImportLedgerEntriesResponse

        guard isPushContextValid(memberID: memberID) else {
            return false
        }
        do {
            response = try await ledgerService.importAll(items)
        } catch let APIError.server(code, _) where code == "LEDGER_IMPORT_CONFLICT" {
            guard isPushContextValid(memberID: memberID) else {
                return false
            }
            // 서버에 이미 import 기준선이 존재한다. 마커를 먼저 확정해 full-import 부활을 막고,
            // 다음 이벤트부터 건별 멱등 sync로 수렴한다.
            try await repository.setImportDone(true, memberID: memberID)
            return true
        }
        guard isPushContextValid(memberID: memberID) else {
            return false
        }

        // 마커를 먼저 기록한다. 이후 확정값 반영이 실패해도 다음 이벤트는 건별 sync만 수행하므로
        // 성공한 full-import가 다시 살아나는 것을 방지한다.
        try await repository.setImportDone(true, memberID: memberID)
        for importedEntry in response.entries {
            guard let pushed = pushedPayloads[importedEntry.clientEntryId] else {
                continue
            }
            let didApply = try await confirmPush(
                clientEntryID: importedEntry.clientEntryId,
                pushed: pushed,
                ledgerEntry: importedEntry.ledgerEntry
            )
            guard didApply else {
                continue
            }
            onLedgerChange()
        }

        if try await !repository.pendingPushEntries().isEmpty {
            return try await pushIncrementally(memberID: memberID, onLedgerChange: onLedgerChange)
        }
        return true
    }

    func pushIncrementally(memberID: UUID, onLedgerChange: () -> Void) async throws -> Bool {
        let entries = try await repository.pendingPushEntries()
        for entry in entries {
            guard isPushContextValid(memberID: memberID) else {
                return false
            }
            let pushed = TransactionRepository.PushedPayload(transaction: entry)
            let response = try await ledgerService.sync(SyncLedgerEntryRequest(transaction: entry))
            guard isPushContextValid(memberID: memberID) else {
                return false
            }
            if try await confirmPush(
                clientEntryID: response.clientEntryId,
                pushed: pushed,
                ledgerEntry: response.ledgerEntry
            ) {
                onLedgerChange()
            }
        }
        return true
    }

    func confirmPush(
        clientEntryID: UUID,
        pushed: TransactionRepository.PushedPayload,
        ledgerEntry: LedgerEntryResponse
    ) async throws -> Bool {
        try applyServerConfirmedFailure?(clientEntryID)
        return try await repository.confirmPush(
            clientEntryID: clientEntryID,
            pushed: pushed,
            krwAmount: ledgerEntry.krwAmount,
            appliedRate: ledgerEntry.appliedRate,
            rateBaseDate: ledgerEntry.rateBaseDate
        )
    }

    func isPushContextValid(memberID: UUID) -> Bool {
        !isPushSuspended && authProvider.currentUserID == memberID
    }

    /// 플래그 소비와 재실행 경계 판정을 하나의 MainActor 구간에서 끝낸다.
    /// capturedMemberID가 nil인 경우는 서버 작업 전 빈 큐 판정 중 로컬 쓰기가 완료된 경우다.
    func consumePushRerun(capturedMemberID: UUID?) -> Bool {
        guard shouldRerunPush else {
            return false
        }
        shouldRerunPush = false
        guard !isPushSuspended else {
            return false
        }
        guard let capturedMemberID else {
            return true
        }
        return authProvider.currentUserID == capturedMemberID
    }

    func publishLedgerChange() {
        ledgerRevision += 1
        ledgerChangeBroadcaster.broadcast()
    }

    func finishLocalWrite() {
        activeLocalWriteCount -= 1
        guard activeLocalWriteCount == 0 else {
            return
        }
        let waiters = localWriteWaiters
        localWriteWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

@MainActor
private final class LedgerChangeBroadcaster {
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    var changes: AsyncStream<Void> {
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

    func broadcast() {
        continuations.values.forEach { $0.yield(()) }
    }

    deinit {
        continuations.values.forEach { $0.finish() }
    }
}

extension SyncEngine: LocalWriteSyncTriggering {}

enum SyncEngineError: Error, Equatable {
    case offline
    case missingIdentity
    case invalidRestoreCursorProgress
    case missingChangesCursor
    case invalidChangesCursorProgress
    case localWritesSuspended
}

private extension ImportLedgerEntryItem {
    init(transaction: LocalTransaction) {
        self.init(
            clientEntryId: transaction.clientEntryID,
            amount: transaction.amount,
            currencyCode: transaction.currencyCode,
            categoryId: transaction.categoryID,
            assetId: transaction.assetID,
            transactionDate: transaction.transactionDate,
            memo: transaction.memo
        )
    }
}

private extension SyncLedgerEntryRequest {
    init(transaction: LocalTransaction) {
        self.init(
            clientEntryId: transaction.clientEntryID,
            amount: transaction.amount,
            currencyCode: transaction.currencyCode,
            categoryId: transaction.categoryID,
            assetId: transaction.assetID,
            transactionDate: transaction.transactionDate,
            memo: transaction.memo
        )
    }
}
