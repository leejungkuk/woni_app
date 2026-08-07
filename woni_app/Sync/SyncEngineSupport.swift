//
//  SyncEngineSupport.swift
//  woni_app
//
//  SyncEngine이 쓰는 자기 완결적 지원 타입 — 변경 팬아웃 브로드캐스터, 오류, 도메인→요청 DTO 매핑.
//  SyncEngine.swift가 file_length 상한에 닿아 분리했다. 경계를 여기로 잡은 이유는 SyncEngine의
//  멤버를 다른 파일로 옮기면 저장 프로퍼티(repository·inFlight*·isPushSuspended의 private(set)
//  쓰기 장벽)를 전부 internal로 넓혀야 하기 때문이다 — 이 타입들의 대가는 훨씬 작다.
//  다만 공짜는 아니다: Swift는 파일 간 `private` 공유가 안 되므로 top-level 3개(브로드캐스터와
//  DTO init 확장 2개)가 file-private에서 internal로 넓어졌다. 분할에 불가피한 비용이며,
//  이 타입들을 SyncEngine 밖에서 쓰지 마라.
//

import Foundation

@MainActor
final class LedgerChangeBroadcaster {
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

enum SyncEngineError: Error, Equatable {
    case offline
    case missingIdentity
    case invalidRestoreCursorProgress
    case missingChangesCursor
    case invalidChangesCursorProgress
    case localWritesSuspended
}

extension ImportLedgerEntryItem {
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

extension SyncLedgerEntryRequest {
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
