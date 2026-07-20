//
//  SyncEngine.swift
//  woni_app
//

import Foundation

/// 로컬 pending 거래를 서버에 FIFO로 push한다.
///
/// MainActor 직렬화와 단일 in-flight task로 명시 호출·온라인 전이가 겹쳐도 같은 작업에
/// 합류한다. 신원별 최초 성공 import(또는 conflict 확립) 뒤에는 건별 멱등 sync만 사용한다.
@MainActor
final class SyncEngine {
    /// openapi ImportLedgerEntriesRequest.entries @Size(max=1000) 계약.
    private static let maxImportEntries = 1000

    private let repository: TransactionRepository
    private let ledgerService: LedgerService
    private let authProvider: any AuthProviding
    private let connectivity: any ConnectivityObserving
    private let inFlightJoinObserver: (() -> Void)?

    private var inFlightPush: Task<Void, Never>?
    private var connectivityTask: Task<Void, Never>?

    init(
        repository: TransactionRepository,
        ledgerService: LedgerService,
        authProvider: any AuthProviding,
        connectivity: any ConnectivityObserving,
        inFlightJoinObserver: (() -> Void)? = nil
    ) {
        self.repository = repository
        self.ledgerService = ledgerService
        self.authProvider = authProvider
        self.connectivity = connectivity
        self.inFlightJoinObserver = inFlightJoinObserver

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
    }

    /// 온라인일 때만 push를 시작한다. 이미 실행 중이면 그 작업 완료에 합류한다.
    func pushPending() async {
        guard connectivity.isOnline else {
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
            await self.performPush()
        }
        inFlightPush = task
        await task.value
        inFlightPush = nil
    }
}

private extension SyncEngine {
    func performPush() async {
        do {
            try await authProvider.ensureIdentity()
            guard let memberID = authProvider.currentUserID else {
                return
            }

            if try await repository.isImportDone(memberID: memberID) {
                try await pushIncrementally()
            } else {
                try await pushInitialImport(memberID: memberID)
            }
        } catch {
            // 이벤트 기반 재트리거에서 pending 상태로 재개한다. 호출부 UI 오류 상태는 step8 경계다.
        }
    }

    func pushInitialImport(memberID: UUID) async throws {
        let entries = try await repository.pendingPushEntries()
        let importEntries = Array(entries.prefix(Self.maxImportEntries))
        let items = importEntries.map(ImportLedgerEntryItem.init(transaction:))

        do {
            _ = try await ledgerService.importAll(items)
        } catch let APIError.server(code, _) where code == "LEDGER_IMPORT_CONFLICT" {
            // 서버에 이미 import 기준선이 존재한다. 마커를 먼저 확정해 full-import 부활을 막고,
            // 다음 이벤트부터 건별 멱등 sync로 수렴한다.
            try await repository.setImportDone(true, memberID: memberID)
            return
        }

        // 마커를 먼저 기록한다. 이후 markSynced가 실패해도 다음 이벤트는 건별 sync만 수행하므로
        // 성공한 full-import가 다시 살아나는 것을 방지한다.
        try await repository.setImportDone(true, memberID: memberID)
        try await repository.markSynced(clientEntryIDs: importEntries.map(\.clientEntryID))

        if try await !repository.pendingPushEntries().isEmpty {
            try await pushIncrementally()
        }
    }

    func pushIncrementally() async throws {
        let entries = try await repository.pendingPushEntries()
        for entry in entries {
            _ = try await ledgerService.sync(SyncLedgerEntryRequest(transaction: entry))
            try await repository.markSynced(clientEntryIDs: [entry.clientEntryID])
        }
    }
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
