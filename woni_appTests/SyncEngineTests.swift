//
//  SyncEngineTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct SyncEngineTests {
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
