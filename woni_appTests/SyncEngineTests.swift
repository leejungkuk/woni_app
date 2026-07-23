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
        // 두 페이지에 걸쳐 2건을 반영해도 패스 단위 defer로 정확히 1회만 발화한다.
        #expect(harness.engine.ledgerRevision == 1)
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
        #expect(harness.engine.ledgerRevision == 1)
    }

    @Test("restoreAll은 첫 페이지 반영 뒤 다음 페이지가 실패해도 변경 신호를 한 번 발행한다")
    func restoreAllPublishesOnceAfterPartialApplicationFailure() async throws {
        let memberID = try #require(UUID(uuidString: "11201010-1010-1010-1010-101010101010"))
        let entryID = try #require(UUID(uuidString: "22000000-0000-0000-0000-000000000001"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        var changes = harness.engine.ledgerDidChange.makeAsyncIterator()

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
                                clientEntryID: entryID,
                                transactionDate: "2026-07-20"
                            )],
                            nextCursor: ("2026-07-20", 2),
                            hasNext: true
                        )
                    )
                )
            }
            return try response(
                for: request,
                statusCode: 500,
                data: Data(#"{"success":false,"code":"RESTORE_FAILURE","message":"failure","data":null}"#.utf8)
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        do {
            try await harness.engine.restoreAll()
            Issue.record("두 번째 restore 페이지 실패가 전달되어야 합니다.")
        } catch {
            #expect(try await harness.repository.count() == 1)
        }

        #expect(await changes.next() != nil)
        #expect(harness.engine.ledgerRevision == 1)
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
    // swiftlint:disable:next function_body_length
    func firstPushImportsOnceThenUsesSync() async throws {
        let memberID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let firstEntryID = try #require(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let secondEntryID = try #require(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        var firstChanges = harness.engine.ledgerDidChange.makeAsyncIterator()
        var secondChanges = harness.engine.ledgerDidChange.makeAsyncIterator()

        try await harness.repository.insert(makeTransaction(
            clientEntryID: firstEntryID,
            amount: syncTestDecimal("12.34"),
            memo: nil
        ))
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(
                for: request,
                krwAmount: "17120.2872114",
                appliedRate: "1387.54321"
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.pushPending()

        #expect(try await harness.repository.isImportDone(memberID: memberID))
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
        let imported = try #require(try await harness.repository.all(
            month: LedgerMonth(year: 2026, month: 7)
        ).first)
        let importedKRWAmount = try syncTestDecimal("17120.2872114")
        let importedRate = try syncTestDecimal("1387.54321")
        #expect(imported.krwAmount == importedKRWAmount)
        #expect(imported.appliedRate == importedRate)
        #expect(!imported.pending)
        #expect(imported.syncState == .synced)
        #expect(await firstChanges.next() != nil)
        #expect(await secondChanges.next() != nil)
        #expect(harness.engine.ledgerRevision == 1)

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
        #expect(harness.engine.ledgerRevision == 2)

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
        #expect(harness.engine.ledgerRevision == 1)
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

    @Test("계정 전환 finish는 대상 계정 확인 뒤 최초 import로 익명 행을 병합한다")
    func accountSwitchFinishImportsPendingEntriesForExpectedMember() async throws {
        let memberID = try #require(UUID(uuidString: "47474747-4747-4747-4747-474747474747"))
        let entryID = try #require(UUID(uuidString: "48000000-0000-0000-0000-000000000001"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.auth.signIn(.google)
        try await harness.repository.insert(makeTransaction(clientEntryID: entryID))
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.beginAccountSwitch()
        let didFinish = await harness.engine.finishAccountSwitch(expectedMemberID: memberID)

        #expect(didFinish)
        #expect(!harness.engine.isPushSuspended)
        let requests = harness.recorder.snapshot()
        #expect(requests.map(\.path) == ["/api/v1/ledgers/import"])
        let importBody = try bodyObject(from: #require(requests.first?.body))
        let entries = try #require(importBody["entries"] as? [[String: Any]])
        #expect(entries.compactMap { $0["clientEntryId"] as? String } == [entryID.uuidString])
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
    }

    @Test("계정 전환 finish는 import 완료 계정에 증분 sync로 익명 행을 병합한다")
    func accountSwitchFinishSyncsPendingEntriesForImportedMember() async throws {
        let memberID = try #require(UUID(uuidString: "48484848-4848-4848-4848-484848484848"))
        let entryID = try #require(UUID(uuidString: "48000000-0000-0000-0000-000000000002"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.auth.signIn(.google)
        try await harness.repository.setImportDone(true, memberID: memberID)
        try await harness.repository.insert(makeTransaction(clientEntryID: entryID))
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.beginAccountSwitch()
        let didFinish = await harness.engine.finishAccountSwitch(expectedMemberID: memberID)

        #expect(didFinish)
        #expect(!harness.engine.isPushSuspended)
        let requests = harness.recorder.snapshot()
        #expect(requests.map(\.path) == ["/api/v1/ledgers/sync"])
        let syncBody = try bodyObject(from: #require(requests.first?.body))
        #expect(syncBody["clientEntryId"] as? String == entryID.uuidString)
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
    }

    @Test("계정 전환 finish는 대상 member가 다르면 suspend를 유지하고 push하지 않는다")
    func accountSwitchFinishFailsClosedForUnexpectedMember() async throws {
        let currentMemberID = try #require(UUID(uuidString: "49494949-4949-4949-4949-494949494949"))
        let expectedMemberID = try #require(UUID(uuidString: "50505050-5050-5050-5050-505050505050"))
        let entryID = try #require(UUID(uuidString: "48000000-0000-0000-0000-000000000003"))
        let harness = try makeHarness(memberID: currentMemberID, isOnline: true)
        try await harness.auth.signIn(.google)
        try await harness.repository.insert(makeTransaction(clientEntryID: entryID))
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.beginAccountSwitch()
        let didFinish = await harness.engine.finishAccountSwitch(expectedMemberID: expectedMemberID)
        let didResume = harness.engine.resumeAccountSwitch(expectedMemberID: expectedMemberID)
        await harness.engine.pushPending()

        #expect(!didFinish)
        #expect(!didResume)
        #expect(harness.engine.isPushSuspended)
        #expect(harness.recorder.snapshot().isEmpty)
        #expect(try await harness.repository.pendingPushEntries().map(\.clientEntryID) == [entryID])
    }

    @Test("계정 전환 resume은 nil 익명 동일 member에서만 push 없이 suspend를 해제한다")
    func accountSwitchResumeAllowsOnlySafeIdentityStates() async throws {
        let memberID = try #require(UUID(uuidString: "51515151-5151-5151-5151-515151515151"))
        let unexpectedMemberID = try #require(UUID(uuidString: "52525252-5252-5252-5252-525252525252"))
        let recorder = SyncPushRequestRecorder()
        SyncPushURLProtocol.handler = { request in
            recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        let missingSessionHarness = try makeHarness(memberID: memberID, isOnline: true)
        try await missingSessionHarness.repository.insert(makeTransaction())
        await missingSessionHarness.engine.beginAccountSwitch()
        #expect(missingSessionHarness.engine.resumeAccountSwitch(expectedMemberID: nil))
        #expect(!missingSessionHarness.engine.isPushSuspended)
        #expect(try await missingSessionHarness.repository.pendingPushEntries().count == 1)

        let anonymousHarness = try makeHarness(memberID: memberID, isOnline: true)
        try await anonymousHarness.auth.ensureIdentity()
        try await anonymousHarness.repository.insert(makeTransaction())
        await anonymousHarness.engine.beginAccountSwitch()
        #expect(anonymousHarness.engine.resumeAccountSwitch(expectedMemberID: unexpectedMemberID))
        #expect(!anonymousHarness.engine.isPushSuspended)
        #expect(try await anonymousHarness.repository.pendingPushEntries().count == 1)

        let expectedMemberHarness = try makeHarness(memberID: memberID, isOnline: true)
        try await expectedMemberHarness.auth.signIn(.google)
        try await expectedMemberHarness.repository.insert(makeTransaction())
        await expectedMemberHarness.engine.beginAccountSwitch()
        #expect(expectedMemberHarness.engine.resumeAccountSwitch(expectedMemberID: memberID))
        #expect(!expectedMemberHarness.engine.isPushSuspended)
        #expect(try await expectedMemberHarness.repository.pendingPushEntries().count == 1)

        #expect(recorder.snapshot().isEmpty)
    }

    @Test("계정 전환 resume은 예상 밖 인증 member에서 fail-closed로 suspend를 유지한다")
    func accountSwitchResumeFailsClosedForUnexpectedAuthenticatedMember() async throws {
        let currentMemberID = try #require(UUID(uuidString: "53535353-5353-5353-5353-535353535353"))
        let expectedMemberID = try #require(UUID(uuidString: "54545454-5454-5454-5454-545454545454"))
        let entryID = try #require(UUID(uuidString: "48000000-0000-0000-0000-000000000004"))
        let harness = try makeHarness(memberID: currentMemberID, isOnline: true)
        try await harness.auth.signIn(.google)
        try await harness.repository.insert(makeTransaction(clientEntryID: entryID))
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.beginAccountSwitch()
        let didResume = harness.engine.resumeAccountSwitch(expectedMemberID: expectedMemberID)
        await harness.engine.pushPending()

        #expect(!didResume)
        #expect(harness.engine.isPushSuspended)
        #expect(harness.recorder.snapshot().isEmpty)
        #expect(try await harness.repository.pendingPushEntries().map(\.clientEntryID) == [entryID])
    }

    @Test("계정 전환 begin은 DB를 변경하지 않고 진행 중 push 정착까지 기다린다")
    func accountSwitchBeginPreservesDatabaseAndWaitsForInFlightPush() async throws {
        let memberID = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555556"))
        let entryID = try #require(UUID(uuidString: "48000000-0000-0000-0000-000000000005"))
        let importGate = SyncPushImportGate()
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.auth.signIn(.google)
        try await harness.repository.insert(makeTransaction(clientEntryID: entryID))
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            await importGate.signalStartedAndWaitForRelease()
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        let push = Task { await harness.engine.pushPending() }
        await importGate.waitUntilStarted()
        var beginDidReturn = false
        let begin = Task {
            await harness.engine.beginAccountSwitch()
            beginDidReturn = true
        }
        while !harness.engine.isPushSuspended {
            await Task.yield()
        }

        #expect(!beginDidReturn)
        #expect(try await harness.repository.pendingPushEntries().map(\.clientEntryID) == [entryID])

        await importGate.release()
        await push.value
        await begin.value

        #expect(beginDidReturn)
        #expect(harness.engine.isPushSuspended)
        #expect(harness.recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
    }

    @Test("진행 중 push에 begin이 합류한 뒤 finish는 남은 pending을 빠짐없이 병합한다")
    func accountSwitchFinishAfterBeginJoinsInFlightPushMergesRemainingPending() async throws {
        let memberID = try #require(UUID(uuidString: "57575757-5757-5757-5757-575757575757"))
        let inFlightID = try #require(UUID(uuidString: "48000000-0000-0000-0000-000000000006"))
        let mergedID = try #require(UUID(uuidString: "48000000-0000-0000-0000-000000000007"))
        let importGate = SyncPushImportGate()
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.auth.signIn(.google)
        try await harness.repository.setImportDone(true, memberID: memberID)
        try await harness.repository.insert(makeTransaction(clientEntryID: inFlightID))
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            await importGate.signalStartedAndWaitForRelease()
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        // 진행 중 push가 inFlightID를 sync하는 도중 gate에서 정지시킨다.
        let push = Task { await harness.engine.pushPending() }
        await importGate.waitUntilStarted()
        // 진행 중 push가 이미 대상 배치를 캡처한 뒤 mergedID를 추가해, 이 행은 finish가 담당하게 한다.
        try await harness.repository.insert(makeTransaction(clientEntryID: mergedID))

        let begin = Task { await harness.engine.beginAccountSwitch() }
        while !harness.engine.isPushSuspended {
            await Task.yield()
        }

        await importGate.release()
        // begin 합류 완료만 기다리고 진행 중 push 정리를 먼저 await하지 않는다(경쟁을 가리지 않기 위함).
        await begin.value

        let didFinish = await harness.engine.finishAccountSwitch(expectedMemberID: memberID)
        await push.value

        #expect(didFinish)
        #expect(!harness.engine.isPushSuspended)
        let paths = harness.recorder.snapshot().map(\.path)
        #expect(paths == ["/api/v1/ledgers/sync", "/api/v1/ledgers/sync"])
        let sentEntryIDs = try harness.recorder.snapshot().map { recorded in
            try bodyObject(from: #require(recorded.body))["clientEntryId"] as? String
        }
        #expect(sentEntryIDs == [inFlightID.uuidString, mergedID.uuidString])
        #expect(try await harness.repository.pendingPushEntries().isEmpty)
    }

    @Test("계정 전환 finish는 pending이 없으면 push 없이 성공한다")
    func accountSwitchFinishWithNoPendingEntriesIsNoOp() async throws {
        let memberID = try #require(UUID(uuidString: "56565656-5656-5656-5656-565656565656"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.auth.signIn(.google)
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.beginAccountSwitch()
        let didFinish = await harness.engine.finishAccountSwitch(expectedMemberID: memberID)

        #expect(didFinish)
        #expect(!harness.engine.isPushSuspended)
        #expect(harness.recorder.snapshot().isEmpty)
        #expect(harness.auth.anonymousSignInCount == 0)
    }

    @Test("증분 sync는 FIFO로 처리하고 중간 실패 지점부터 다음 push에서 재개한다")
    func incrementalSyncResumesInFIFOOrderAfterMiddleFailure() async throws {
        let memberID = try #require(UUID(uuidString: "34343434-3434-3434-3434-343434343434"))
        let firstEntryID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let secondEntryID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000002"))
        let thirdEntryID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000003"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        let failure = SyncPushFailOnce(attempt: 2)
        var changes = harness.engine.ledgerDidChange.makeAsyncIterator()

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
        #expect(await changes.next() != nil)
        #expect(harness.engine.ledgerRevision == 1)

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
        #expect(await changes.next() != nil)
        #expect(harness.engine.ledgerRevision == 2)
    }

    @Test("서버 ack 뒤 로컬 확정 실패는 pending을 유지하고 다음 sync의 최신 값으로 수렴한다")
    // swiftlint:disable:next function_body_length
    func confirmationFailureRetriesAndConvergesToLatestServerValues() async throws {
        let memberID = try #require(UUID(uuidString: "35353535-3535-3535-3535-353535353535"))
        let entryID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000004"))
        let confirmationFailure = SyncPushFailOnce(attempt: 1)
        let responseAttempt = SyncPushFailOnce(attempt: 1)
        let harness = try makeHarness(
            memberID: memberID,
            isOnline: true,
            applyServerConfirmedFailure: { identifier in
                #expect(identifier == entryID)
                if confirmationFailure.shouldFail() {
                    throw SyncEngineTestError.confirmationFailure
                }
            }
        )
        try await harness.repository.insert(makeTransaction(clientEntryID: entryID))

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            if responseAttempt.shouldFail() {
                return try successResponse(
                    for: request,
                    krwAmount: "150000.01",
                    appliedRate: "1500.0001"
                )
            }
            return try successResponse(
                for: request,
                krwAmount: "160000.02",
                appliedRate: "1600.0002",
                rateBaseDate: "2026-07-20"
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.pushPending()

        let stillPending = try #require(try await harness.repository.pendingPushEntries().first)
        #expect(stillPending.clientEntryID == entryID)
        #expect(stillPending.krwAmount == Decimal(140_000))
        #expect(try await harness.repository.isImportDone(memberID: memberID))
        #expect(harness.engine.ledgerRevision == 0)

        await harness.engine.pushPending()

        let confirmed = try #require(try await harness.repository.all(
            month: LedgerMonth(year: 2026, month: 7)
        ).first)
        let confirmedKRWAmount = try syncTestDecimal("160000.02")
        let confirmedRate = try syncTestDecimal("1600.0002")
        #expect(confirmed.krwAmount == confirmedKRWAmount)
        #expect(confirmed.appliedRate == confirmedRate)
        #expect(confirmed.rateBaseDate == "2026-07-20")
        #expect(!confirmed.pending)
        #expect(confirmed.syncState == .synced)
        #expect(harness.engine.ledgerRevision == 1)

        let requests = harness.recorder.snapshot()
        #expect(requests.map(\.path) == [
            "/api/v1/ledgers/import",
            "/api/v1/ledgers/sync"
        ])
        let requestIDs = try requests.map { request in
            let body = try bodyObject(from: #require(request.body))
            if let entries = body["entries"] as? [[String: Any]] {
                return entries.first?["clientEntryId"] as? String
            }
            return body["clientEntryId"] as? String
        }
        #expect(requestIDs == [entryID.uuidString, entryID.uuidString])
    }

    @Test("응답 clientEntryId가 로컬 행과 매칭되지 않으면 변경 신호를 발행하지 않는다")
    func unmatchedConfirmationDoesNotPublishLedgerChange() async throws {
        let memberID = try #require(UUID(uuidString: "36353535-3535-3535-3535-353535353535"))
        let entryID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000005"))
        let unmatchedID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000006"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        try await harness.repository.setImportDone(true, memberID: memberID)
        try await harness.repository.insert(makeTransaction(clientEntryID: entryID))

        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try response(
                for: request,
                data: successEnvelope(
                    dataJSON: #"{"clientEntryId":"\#(unmatchedID.uuidString)","ledgerEntry":\#(ledgerEntryJSON())}"#
                )
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.pushPending()

        #expect(try await harness.repository.pendingPushEntries().map(\.clientEntryID) == [entryID])
        #expect(harness.engine.ledgerRevision == 0)
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
        #expect(harness.engine.ledgerRevision == 0)
    }

    @Test("온라인 포그라운드 트리거도 pending이 없으면 익명 신원을 발급하지 않는다")
    func onlinePushWithoutPendingEntryKeepsIdentityDeferred() async throws {
        let memberID = try #require(UUID(uuidString: "45454545-4545-4545-4545-454545454545"))
        let harness = try makeHarness(memberID: memberID, isOnline: true)
        SyncPushURLProtocol.handler = { request in
            harness.recorder.record(request)
            return try successResponse(for: request)
        }
        defer { SyncPushURLProtocol.handler = nil }

        await harness.engine.pushPending()

        #expect(harness.auth.currentUserID == nil)
        #expect(harness.auth.anonymousSignInCount == 0)
        #expect(harness.recorder.snapshot().isEmpty)
        #expect(harness.engine.ledgerRevision == 0)
    }

    @Test("로그아웃 suspension은 clear 경계 동안 새 로컬 쓰기를 거부한다")
    func logoutSuspensionRejectsNewLocalWritesUntilResume() async throws {
        let memberID = try #require(UUID(uuidString: "46464646-4646-4646-4646-464646464646"))
        let harness = try makeHarness(memberID: memberID, isOnline: false)
        var didRunSuspendedWrite = false

        await harness.engine.suspendPushForLogout()
        do {
            try await harness.engine.performLocalWrite {
                didRunSuspendedWrite = true
            }
            Issue.record("로그아웃 중에는 새 로컬 쓰기를 시작하지 않아야 합니다.")
        } catch let error as SyncEngineError {
            #expect(error == .localWritesSuspended)
        }

        #expect(!didRunSuspendedWrite)
        harness.engine.resumePushAfterLogout()
        try await harness.engine.performLocalWrite {
            try await harness.repository.insert(makeTransaction())
        }
        #expect(try await harness.repository.count() == 1)
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
    inFlightJoinObserver: (() -> Void)? = nil,
    applyServerConfirmedFailure: ((UUID) throws -> Void)? = nil
) throws -> SyncEngineTestHarness {
    let repository = try TransactionRepository(database: AppDatabase.inMemory())
    let auth = FakeAuthService(
        makeUserID: { memberID },
        makeSignedInUserID: { memberID }
    )
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
        inFlightJoinObserver: inFlightJoinObserver,
        applyServerConfirmedFailure: applyServerConfirmedFailure
    )
    return SyncEngineTestHarness(
        engine: engine,
        repository: repository,
        auth: auth,
        connectivity: connectivity,
        recorder: recorder
    )
}

private enum SyncEngineTestError: Error {
    case confirmationFailure
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
