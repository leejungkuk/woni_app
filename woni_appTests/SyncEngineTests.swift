//
//  SyncEngineTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

// swiftlint:disable file_length

@Suite(.serialized)
@MainActor
struct SyncEngineTests {}

extension SyncEngineTests {
    @Test("restoreAll은 restore 전 페이지를 keyset 커서로 순회해 서버 행을 synced로 upsert한다")
    func restoreAllTraversesEveryPageAndUpserts() async throws {
        let memberID = try #require(UUID(uuidString: "10101010-1010-1010-1010-101010101010"))
        let firstEntryID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000001"))
        let secondEntryID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            let query = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?
                .queryItemsDictionary ?? [:]
            if query["cursorDate"] == nil {
                return try response(
                    for: request,
                    data: successEnvelope(
                        dataJSON: restorePageJSON(
                            entries: [restoredLedgerEntryJSON(
                                id: 2,
                                clientEntryID: firstEntryID,
                                transactionDate: "2026-07-20",
                                memo: "first"
                            )],
                            nextCursor: ("2026-07-20", 2),
                            hasNext: true
                        )
                    )
                )
            }
            #expect(query["cursorDate"] == "2026-07-20")
            #expect(query["cursorId"] == "2")
            return try response(
                for: request,
                data: successEnvelope(
                    dataJSON: restorePageJSON(
                        entries: [restoredLedgerEntryJSON(
                            id: 1,
                            clientEntryID: secondEntryID,
                            transactionDate: "2026-07-19",
                            memo: "second"
                        )],
                        nextCursor: nil,
                        hasNext: false
                    )
                )
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        try await harness.engine.restoreAll()

        let stored = try await harness.repository.all(month: LedgerMonth(year: 2026, month: 7))
        #expect(stored.map(\.clientEntryID) == [firstEntryID, secondEntryID])
        #expect(stored.allSatisfy { !$0.pending && $0.syncState == .synced })
        let requests = harness.recorder.snapshot()
        #expect(requests.map(\.path) == ["/api/v1/ledgers/restore", "/api/v1/ledgers/restore"])
        #expect(requests.allSatisfy { $0.queryItems["size"] == "500" })
    }

    @Test("restoreAll은 clientEntryId가 null인 행만 건너뛰고 같은 페이지의 정상 행을 저장한다")
    func restoreAllSkipsNullClientEntryIDAndStoresValidEntry() async throws {
        let memberID = try #require(UUID(uuidString: "11101010-1010-1010-1010-101010101010"))
        let validEntryID = try #require(UUID(uuidString: "21000000-0000-0000-0000-000000000001"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try response(
                for: request,
                data: successEnvelope(
                    dataJSON: restorePageJSON(
                        entries: [
                            restoredLedgerEntryJSON(
                                id: 2,
                                clientEntryID: nil,
                                transactionDate: "2026-07-20",
                                memo: "legacy"
                            ),
                            restoredLedgerEntryJSON(
                                id: 1,
                                clientEntryID: validEntryID,
                                transactionDate: "2026-07-19",
                                memo: "valid"
                            )
                        ],
                        nextCursor: nil,
                        hasNext: false
                    )
                )
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        try await harness.engine.restoreAll()

        let stored = try await harness.repository.all(month: LedgerMonth(year: 2026, month: 7))
        #expect(stored.map(\.clientEntryID) == [validEntryID])
        #expect(stored.first?.memo == "valid")
    }

    @Test("restoreAll은 hasNext인데 nextCursor가 없으면 커서 진행 오류를 던진다")
    func restoreAllRejectsMissingNextCursorProgress() async throws {
        let memberID = try #require(UUID(uuidString: "12101010-1010-1010-1010-101010101010"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try response(
                for: request,
                data: successEnvelope(
                    dataJSON: restorePageJSON(entries: [], nextCursor: nil, hasNext: true)
                )
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        do {
            try await harness.engine.restoreAll()
            Issue.record("진행할 restore 커서가 없으면 실패해야 합니다.")
        } catch let error as SyncEngineError {
            #expect(error == .invalidRestoreCursorProgress)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("pullChanges는 저장 커서로 재개하고 hasMore와 overlap 재전달을 멱등 흡수한다")
    // swiftlint:disable:next function_body_length
    func pullChangesResumesCursorTraversesAndDeduplicatesOverlap() async throws {
        let memberID = try #require(UUID(uuidString: "20202020-2020-2020-2020-202020202020"))
        let overlapEntryID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000001"))
        let finalEntryID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000002"))
        let pendingEntryID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000003"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.repository.insert(makeTransaction(clientEntryID: pendingEntryID))
        try await harness.repository.setPullCursor(SyncPullCursor(updatedAt: "2026-07-20T09:00:00", id: 40))

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            let query = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?
                .queryItemsDictionary ?? [:]
            if query["cursorId"] == "40" {
                #expect(query["cursorUpdatedAt"] == "2026-07-20T09:00:00")
                return try response(
                    for: request,
                    data: successEnvelope(
                        dataJSON: changesPageJSON(
                            entries: [changedLedgerEntryJSON(
                                id: 41,
                                clientEntryID: overlapEntryID,
                                updatedAt: "2026-07-20T09:01:00",
                                memo: "overlap"
                            )],
                            nextCursor: ("2026-07-20T09:01:00", 41),
                            hasMore: true
                        )
                    )
                )
            }
            #expect(query["cursorUpdatedAt"] == "2026-07-20T09:01:00")
            #expect(query["cursorId"] == "41")
            return try response(
                for: request,
                data: successEnvelope(
                    dataJSON: changesPageJSON(
                        entries: [
                            changedLedgerEntryJSON(
                                id: 41,
                                clientEntryID: overlapEntryID,
                                updatedAt: "2026-07-20T09:01:00",
                                memo: "overlap"
                            ),
                            changedLedgerEntryJSON(
                                id: 42,
                                clientEntryID: finalEntryID,
                                updatedAt: "2026-07-20T09:02:00",
                                memo: "final"
                            )
                        ],
                        nextCursor: ("2026-07-20T09:02:00", 42),
                        hasMore: false
                    )
                )
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        try await harness.engine.pullChanges()

        #expect(try await harness.repository.count() == 3)
        #expect(try await harness.repository.pendingPushEntries().map(\.clientEntryID) == [pendingEntryID])
        #expect(try await harness.repository.pullCursor() == SyncPullCursor(
            updatedAt: "2026-07-20T09:02:00",
            id: 42
        ))
        let requests = harness.recorder.snapshot()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy {
            $0.queryItems["cursorUpdatedAt"] != nil && $0.queryItems["cursorId"] != nil
        })
    }

    @Test("pullChanges는 로컬 잠정 환산값을 서버 Decimal 확정값으로 교체하고 재계산하지 않는다")
    func pullChangesReplacesProvisionalValuesWithServerConfirmation() async throws {
        let memberID = try #require(UUID(uuidString: "30303030-3030-3030-3030-303030303030"))
        let entryID = try #require(UUID(uuidString: "40000000-0000-0000-0000-000000000001"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.repository.insert(makeTransaction(
            clientEntryID: entryID,
            amount: syncTestDecimal("12.34"),
            memo: "local"
        ))

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            let query = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?
                .queryItemsDictionary ?? [:]
            #expect(query["cursorUpdatedAt"] == nil)
            #expect(query["cursorId"] == nil)
            return try response(
                for: request,
                data: successEnvelope(
                    dataJSON: changesPageJSON(
                        entries: [changedLedgerEntryJSON(
                            id: 51,
                            clientEntryID: entryID,
                            updatedAt: "2026-07-20T10:00:00",
                            originalAmount: "12.34",
                            appliedRate: "1387.54321",
                            krwAmount: "17120.2872114",
                            memo: "server"
                        )],
                        nextCursor: ("2026-07-20T10:00:00", 51),
                        hasMore: false
                    )
                )
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        try await harness.engine.pullChanges()

        let stored = try #require(try await harness.repository.all(
            month: LedgerMonth(year: 2026, month: 7)
        ).first)
        let expectedAmount = try syncTestDecimal("12.34")
        let expectedKRWAmount = try syncTestDecimal("17120.2872114")
        let expectedRate = try syncTestDecimal("1387.54321")
        #expect(stored.amount == expectedAmount)
        #expect(stored.memo == "local")
        #expect(stored.krwAmount == expectedKRWAmount)
        #expect(stored.appliedRate == expectedRate)
        #expect(stored.rateBaseDate == "2026-07-19")
        #expect(!stored.pending)
        #expect(stored.syncState == .synced)
    }

    @Test("pullChanges는 clientEntryId가 null인 행만 건너뛰고 같은 페이지의 정상 행을 적용한다")
    func pullChangesSkipsNullClientEntryIDAndAppliesValidEntry() async throws {
        let memberID = try #require(UUID(uuidString: "31303030-3030-3030-3030-303030303030"))
        let validEntryID = try #require(UUID(uuidString: "41000000-0000-0000-0000-000000000001"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try response(
                for: request,
                data: successEnvelope(
                    dataJSON: changesPageJSON(
                        entries: [
                            changedLedgerEntryJSON(
                                id: 61,
                                clientEntryID: nil,
                                updatedAt: "2026-07-20T11:00:00",
                                memo: "legacy"
                            ),
                            changedLedgerEntryJSON(
                                id: 62,
                                clientEntryID: validEntryID,
                                updatedAt: "2026-07-20T11:01:00",
                                memo: "valid"
                            )
                        ],
                        nextCursor: ("2026-07-20T11:01:00", 62),
                        hasMore: false
                    )
                )
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        try await harness.engine.pullChanges()

        let stored = try await harness.repository.all(month: LedgerMonth(year: 2026, month: 7))
        #expect(stored.map(\.clientEntryID) == [validEntryID])
        #expect(stored.first?.memo == "valid")
    }

    @Test("pullChanges는 hasMore인데 nextCursor가 직전 커서와 같으면 진행 오류를 던진다")
    func pullChangesRejectsUnchangedCursorProgress() async throws {
        let memberID = try #require(UUID(uuidString: "32303030-3030-3030-3030-303030303030"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        let cursor = SyncPullCursor(updatedAt: "2026-07-20T12:00:00", id: 70)
        try await harness.repository.setPullCursor(cursor)

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try response(
                for: request,
                data: successEnvelope(
                    dataJSON: changesPageJSON(
                        entries: [],
                        nextCursor: (cursor.updatedAt, cursor.id),
                        hasMore: true
                    )
                )
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        do {
            try await harness.engine.pullChanges()
            Issue.record("changes 커서가 진행하지 않으면 실패해야 합니다.")
        } catch let error as SyncEngineError {
            #expect(error == .invalidChangesCursorProgress)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }

    @Test("pullChanges는 hasMore인데 nextCursor가 없으면 누락 오류를 던진다")
    func pullChangesRejectsMissingNextCursor() async throws {
        let memberID = try #require(UUID(uuidString: "33303030-3030-3030-3030-303030303030"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try response(
                for: request,
                data: successEnvelope(
                    dataJSON: changesPageJSON(entries: [], nextCursor: nil, hasMore: true)
                )
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        do {
            try await harness.engine.pullChanges()
            Issue.record("hasMore인 changes 응답에는 nextCursor가 필요합니다.")
        } catch let error as SyncEngineError {
            #expect(error == .missingChangesCursor)
        } catch {
            Issue.record("예상하지 않은 오류: \(error)")
        }
    }
}

extension SyncEngineTests {
    @Test("최초 push는 import 1회이고 이후 신규 항목은 sync로 전환한다")
    func firstPushImportsOnceThenUsesSync() async throws {
        let memberID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let firstEntryID = try #require(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let secondEntryID = try #require(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)

        try await harness.repository.insert(makeTransaction(
            clientEntryID: firstEntryID,
            amount: syncTestDecimal("12.34"),
            memo: nil
        ))
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.pushPending()

        #expect(try await harness.repository.isImportDone(memberID: memberID))
        #expect(try await harness.repository.pendingPushEntries().isEmpty)

        try await harness.repository.insert(makeTransaction(
            clientEntryID: secondEntryID,
            amount: syncTestDecimal("56.78"),
            memo: "후속"
        ))
        await harness.engine.pushPending()

        let requests = harness.recorder.snapshot()
        #expect(requests.map(\.path) == [
            "/api/v1/ledgers/import",
            "/api/v1/ledgers/sync"
        ])
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
        #expect(harness.auth.anonymousSignInCount == 1)

        let importBody = try bodyObject(from: #require(requests.first?.body))
        let entries = try #require(importBody["entries"] as? [[String: Any]])
        let importedEntry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(importedEntry["clientEntryId"] as? String == firstEntryID.uuidString)
        #expect(importedEntry["memo"] == nil)
        #expect(importedEntry["krwAmount"] == nil)
        #expect(importedEntry["appliedRate"] == nil)

        let syncBody = try bodyObject(from: #require(requests.last?.body))
        #expect(syncBody["clientEntryId"] as? String == secondEntryID.uuidString)
        #expect(syncBody["memo"] as? String == "후속")
        #expect(syncBody["krwAmount"] == nil)
        #expect(syncBody["appliedRate"] == nil)
    }

    @Test("최초 import는 1000건으로 제한하고 초과분을 같은 push에서 sync한다")
    func initialImportCapsAtOneThousandAndDrainsOverflow() async throws {
        let memberID = try #require(UUID(uuidString: "12121212-1212-1212-1212-121212121212"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        let entryIDs = (0 ..< 1001).map { _ in UUID() }

        for entryID in entryIDs {
            try await harness.repository.insert(makeTransaction(clientEntryID: entryID))
        }

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.pushPending()

        let requests = harness.recorder.snapshot()
        #expect(requests.map(\.path) == [
            "/api/v1/ledgers/import",
            "/api/v1/ledgers/sync"
        ])

        let importBody = try bodyObject(from: #require(requests.first?.body))
        let importedEntries = try #require(importBody["entries"] as? [[String: Any]])
        let importedEntryIDs = try importedEntries.map { entry in
            try #require(entry["clientEntryId"] as? String)
        }
        let expectedImportedEntryIDs = entryIDs.prefix(1000).map(\.uuidString)
        #expect(importedEntries.count == 1000)
        #expect(importedEntryIDs == expectedImportedEntryIDs)
        #expect(importedEntryIDs.contains(entryIDs[1000].uuidString) == false)

        let syncBody = try bodyObject(from: #require(requests.last?.body))
        #expect(syncBody["clientEntryId"] as? String == entryIDs[1000].uuidString)
        #expect(syncBody["krwAmount"] == nil)
        #expect(syncBody["appliedRate"] == nil)
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
        #expect(try await harness.repository.isImportDone(memberID: memberID))
    }

    @Test("LEDGER_IMPORT_CONFLICT는 import_done을 확정하고 다음 push를 sync로 수렴시킨다")
    func importConflictTransitionsToIncrementalSync() async throws {
        let memberID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let entryID = try #require(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.repository.insert(makeTransaction(clientEntryID: entryID))

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            if request.url?.path == "/api/v1/ledgers/import" {
                return try response(
                    for: request,
                    statusCode: 409,
                    data: Data(
                        #"{"success":false,"code":"LEDGER_IMPORT_CONFLICT","message":"conflict","data":null}"#.utf8
                    )
                )
            }
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.pushPending()

        #expect(try await harness.repository.isImportDone(memberID: memberID))
        #expect(try await harness.repository.pendingPushEntries().map(\.clientEntryID) == [entryID])
        #expect(harness.recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])

        await harness.engine.pushPending()

        #expect(harness.recorder.snapshot().map(\.path) == [
            "/api/v1/ledgers/import",
            "/api/v1/ledgers/sync"
        ])
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
    }

    @Test("중첩 pushPending 호출은 같은 in-flight 작업에 합류해 import를 중복하지 않는다")
    func overlappingPushesJoinOneInFlightImport() async throws {
        let memberID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let importGate = SyncPushImportGate()
        let harness = try makeHarness(
            memberID: memberID,
            isOnline: true,
            inFlightJoinObserver: {
                Task { await importGate.signalJoined() }
            }
        )
        try await harness.repository.insert(makeTransaction())

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            await importGate.signalStartedAndWaitForRelease()
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        let first = Task { await harness.engine.pushPending() }
        await importGate.waitUntilStarted()

        let second = Task { await harness.engine.pushPending() }
        await importGate.waitUntilJoined()
        await importGate.release()
        await first.value
        await second.value

        #expect(harness.recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])
        #expect(try await harness.repository.isImportDone(memberID: memberID))
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
    }

    @Test("계정 전환 preserve는 push를 중단하고 rollback은 격리 행과 push를 복원한다")
    func accountSwitchPreservationSuspendsPushAndRollbackRestoresIt() async throws {
        let memberID = try #require(UUID(uuidString: "36363636-3636-3636-3636-363636363636"))
        let entryID = try #require(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let zeroBatchID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.repository.insert(makeTransaction(clientEntryID: entryID))

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        let batchID = try await harness.engine.preserveLocalDataForAccountSwitch()

        #expect(batchID != zeroBatchID)
        #expect(try await harness.repository.pendingPushEntries().isEmpty)

        await harness.engine.pushPending()

        #expect(harness.recorder.snapshot().isEmpty)

        try await harness.engine.rollbackLocalDataPreservation(batchID: batchID)

        #expect(try await harness.repository.pendingPushEntries().map(\.clientEntryID) == [entryID])

        await harness.engine.pushPending()

        #expect(harness.recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
    }

    @Test("계정 전환 finish는 기존 행 exclusion을 유지하고 이후 신규 행 push를 재개한다")
    func accountSwitchFinishKeepsExclusionAndPushesNewEntries() async throws {
        let memberID = try #require(UUID(uuidString: "37373737-3737-3737-3737-373737373737"))
        let preservedEntryID = try #require(UUID(uuidString: "38383838-3838-3838-3838-383838383838"))
        let newEntryID = try #require(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.repository.insert(makeTransaction(clientEntryID: preservedEntryID))

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        _ = try await harness.engine.preserveLocalDataForAccountSwitch()
        try await harness.repository.insert(makeTransaction(clientEntryID: newEntryID))

        #expect(try await harness.repository.pendingPushEntries().map(\.clientEntryID) == [newEntryID])

        harness.engine.finishAccountSwitch()
        await harness.engine.pushPending()

        let requests = harness.recorder.snapshot()
        #expect(requests.map(\.path) == ["/api/v1/ledgers/import"])
        let importBody = try bodyObject(from: #require(requests.first?.body))
        let entries = try #require(importBody["entries"] as? [[String: Any]])
        #expect(entries.compactMap { $0["clientEntryId"] as? String } == [newEntryID.uuidString])
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
        #expect(try await harness.repository.count() == 2)
    }

    @Test("증분 sync는 FIFO로 처리하고 중간 실패 지점부터 다음 push에서 재개한다")
    func incrementalSyncResumesInFIFOOrderAfterMiddleFailure() async throws {
        let memberID = try #require(UUID(uuidString: "34343434-3434-3434-3434-343434343434"))
        let firstEntryID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let secondEntryID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000002"))
        let thirdEntryID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000003"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        let failure = SyncPushFailOnce(attempt: 2)

        try await harness.repository.setImportDone(true, memberID: memberID)
        for entryID in [firstEntryID, secondEntryID, thirdEntryID] {
            try await harness.repository.insert(makeTransaction(clientEntryID: entryID))
        }

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            if request.url?.path == "/api/v1/ledgers/sync", failure.shouldFail() {
                return try response(
                    for: request,
                    statusCode: 500,
                    data: Data(
                        #"{"success":false,"code":"SYNC_TEST_FAILURE","message":"failure","data":null}"#.utf8
                    )
                )
            }
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.pushPending()

        #expect(try await harness.repository.pendingPushEntries().map(\.clientEntryID) == [
            secondEntryID,
            thirdEntryID
        ])

        await harness.engine.pushPending()

        let syncedEntryIDs = try harness.recorder.snapshot().map { request in
            let body = try bodyObject(from: #require(request.body))
            let identifier = try #require(body["clientEntryId"] as? String)
            return try #require(UUID(uuidString: identifier))
        }
        #expect(syncedEntryIDs == [
            firstEntryID,
            secondEntryID,
            secondEntryID,
            thirdEntryID
        ])
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
    }

    @Test("오프라인 pushPending은 신원 발급과 네트워크 요청을 하지 않는다")
    func offlinePushIsNoOp() async throws {
        let memberID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let harness = try makeHarness(memberID: memberID, isOnline: false)
        try await harness.repository.insert(makeTransaction())
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.pushPending()

        #expect(harness.auth.anonymousSignInCount == 0)
        #expect(harness.auth.currentUserID == nil)
        #expect(harness.recorder.snapshot().isEmpty)
        #expect(try await harness.repository.pendingPushEntries().count == 1)
        #expect(try await harness.repository.isImportDone(memberID: memberID) == false)
    }

    @Test("오프라인에서 온라인으로 전이하면 이벤트가 push를 트리거한다")
    func onlineTransitionTriggersPush() async throws {
        let memberID = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let harness = try makeHarness(memberID: memberID, isOnline: false)
        try await harness.repository.insert(makeTransaction())
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await Task.yield()
        harness.connectivity.setOnline(true)

        for _ in 0 ..< 10000 {
            if try await harness.repository.pendingPushEntries().isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(harness.recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])
        #expect(try await harness.repository.isImportDone(memberID: memberID))
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
    }
}

private extension URLComponents {
    var queryItemsDictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: (queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}

private struct SyncEngineTestHarness {
    let engine: SyncEngine
    let repository: TransactionRepository
    let auth: FakeAuthService
    let connectivity: FakeConnectivityMonitor
    let recorder: SyncPushRequestRecorder
}

@MainActor
private func makeHarness(
    memberID: UUID,
    isOnline: Bool,
    inFlightJoinObserver: (() -> Void)? = nil
) throws -> SyncEngineTestHarness {
    let repository = try TransactionRepository(database: AppDatabase.inMemory())
    let auth = FakeAuthService(makeUserID: { memberID })
    let connectivity = FakeConnectivityMonitor(isOnline: isOnline)
    let recorder = SyncPushRequestRecorder()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyncPushURLProtocol.self]
    let service = LedgerService(client: APIClient(
        session: URLSession(configuration: configuration),
        authProvider: auth
    ))
    let engine = SyncEngine(
        repository: repository,
        ledgerService: service,
        authProvider: auth,
        connectivity: connectivity,
        inFlightJoinObserver: inFlightJoinObserver
    )
    return SyncEngineTestHarness(
        engine: engine,
        repository: repository,
        auth: auth,
        connectivity: connectivity,
        recorder: recorder
    )
}

private func makeTransaction(
    clientEntryID: UUID = UUID(),
    amount: Decimal = Decimal(100),
    memo: String? = "메모"
) -> LocalTransaction {
    LocalTransaction(
        clientEntryID: clientEntryID,
        amount: amount,
        currencyCode: "USD",
        categoryID: 10,
        assetID: 20,
        transactionType: .expense,
        transactionDate: "2026-07-20",
        memo: memo,
        pending: true,
        appliedRate: Decimal(1400),
        rateBaseDate: "2026-07-19",
        krwAmount: Decimal(140_000)
    )
}

private func syncTestDecimal(_ text: String) throws -> Decimal {
    try #require(Decimal(string: text))
}
