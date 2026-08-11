//
//  LogoutAndBootstrapIntegrationTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct LogoutAndBootstrapIntegrationTests {
    @Test("삭제 큐는 비강행 로그아웃을 막고 강행 로그아웃에서 파기된다")
    func pendingDeleteQueueRequiresForcedLogoutAndIsCleared() async throws {
        let memberID = try #require(UUID(uuidString: "30303030-3030-3030-3030-303030303030"))
        let deletedID = try #require(UUID(uuidString: "31313131-3131-3131-3131-313131313131"))
        let auth = FakeAuthService(makeUserID: { memberID })
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(clientEntryID: deletedID))
        try await repository.delete(clientEntryID: deletedID)
        let syncEngine = SyncEngine(
            repository: repository,
            ledgerService: LedgerService(),
            authProvider: auth,
            connectivity: connectivity
        )
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: syncEngine,
            cleanupMarker: InMemoryLogoutCleanupMarker()
        )
        let settingsViewModel = SettingsViewModel(
            loginViewModel: LoginViewModel(
                authProvider: auth,
                sync: syncEngine,
                coordinator: coordinator,
                connectivity: connectivity,
                anonymousAccountDeleter: FakeAnonymousAccountDeleter()
            ),
            coordinator: coordinator,
            withdrawalCoordinator: Self.makeWithdrawalCoordinator(
                session: coordinator,
                auth: auth,
                connectivity: connectivity
            )
        )

        await settingsViewModel.requestLogout()

        #expect(settingsViewModel.logoutState == .awaitingUnsyncedConfirmation)
        #expect(auth.signOutCount == 0)
        #expect(try await repository.pendingDeleteClientEntryIDs() == [deletedID])

        await settingsViewModel.confirmForcedLogout()

        #expect(settingsViewModel.logoutState == .completed)
        #expect(auth.signOutCount == 1)
        #expect(try await repository.pendingDeleteClientEntryIDs().isEmpty)
    }

    @Test("오프라인 생성부터 import·sync·로그인·로그아웃 clear까지 수렴한다")
    // swiftlint:disable:next function_body_length
    func offlineCreateThroughLogoutClearConvergesEndToEnd() async throws {
        let firstUserID = try #require(UUID(uuidString: "10101010-1010-1010-1010-101010101010"))
        let logoutUserID = try #require(UUID(uuidString: "20202020-2020-2020-2020-202020202020"))
        let memberUserID = try #require(UUID(uuidString: "40404040-4040-4040-4040-404040404040"))
        var userIDs = [firstUserID, logoutUserID]
        let auth = FakeAuthService(
            makeUserID: { userIDs.removeFirst() },
            makeSignedInUserID: { memberUserID }
        )
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        let recorder = SyncPushRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BootstrapURLProtocol.self]
        let syncEngine = SyncEngine(
            repository: repository,
            ledgerService: LedgerService(client: APIClient(
                session: URLSession(configuration: configuration),
                authProvider: auth
            )),
            authProvider: auth,
            connectivity: connectivity,
            pushDebounce: .zero
        )
        let addViewModel = AddExpenseViewModel(
            transactionRepository: repository,
            catalogProvider: CatalogProvider(seedData: addExpenseSeedData()),
            addExpenseRateProvider: SeedRateProviderAdapter(seedData: addExpenseSeedData()),
            baseCurrency: .krw,
            syncTrigger: syncEngine
        )
        BootstrapURLProtocol.handler = { request in
            recorder.record(request)
            guard request.url?.path == "/api/v1/ledgers/restore" else {
                return try successResponse(for: request)
            }
            // 새 계정에는 서버 데이터가 없다 — restore는 0건으로 정상 종료한다.
            return try response(
                for: request,
                data: successEnvelope(
                    dataJSON: restorePageJSON(entries: [], nextCursor: nil, hasNext: false)
                )
            )
        }
        defer { BootstrapURLProtocol.handler = nil }

        await addViewModel.load()
        addViewModel.amount = 1000
        addViewModel.selectedCategoryId = 10
        addViewModel.selectedAssetId = 20
        await addViewModel.save()
        try await Self.waitUntil { try await repository.count() == 1 }
        await Task.yield()

        #expect(auth.currentUserID == nil)
        #expect(auth.anonymousSignInCount == 0)
        #expect(recorder.snapshot().isEmpty)
        #expect(try await repository.pendingPushEntries().count == 1)

        connectivity.setOnline(true)
        try await Self.waitUntil {
            let didImport = recorder.snapshot().count == 1
            let isPendingEmpty = try await repository.pendingPushEntries().isEmpty
            return didImport && isPendingEmpty
        }

        #expect(recorder.snapshot().map(\.path) == ["/api/v1/ledgers/import"])
        #expect(auth.currentUserID == firstUserID)
        #expect(auth.anonymousSignInCount == 1)

        addViewModel.amount = 2000
        await addViewModel.save()
        try await Self.waitUntil {
            let didSync = recorder.snapshot().count == 2
            let isPendingEmpty = try await repository.pendingPushEntries().isEmpty
            return didSync && isPendingEmpty
        }

        #expect(recorder.snapshot().map(\.path) == [
            "/api/v1/ledgers/import",
            "/api/v1/ledgers/sync"
        ])

        let cleanupMarker = InMemoryLogoutCleanupMarker()
        let sessionCoordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: syncEngine,
            cleanupMarker: cleanupMarker
        )
        let anonymousAccountDeleter = FakeAnonymousAccountDeleter()
        let loginViewModel = LoginViewModel(
            authProvider: auth,
            sync: syncEngine,
            coordinator: sessionCoordinator,
            connectivity: connectivity,
            anonymousAccountDeleter: anonymousAccountDeleter
        )
        await loginViewModel.signIn(.google)

        // 단일 경로는 익명 UUID를 승계하지 않고 새 회원 신원을 받은 뒤 그 계정을 restore한다.
        #expect(auth.currentUserID == memberUserID)
        #expect(auth.isAnonymous == false)
        #expect(loginViewModel.flowState == .completed)
        #expect(loginViewModel.identityState == .signedIn)
        #expect(recorder.snapshot().map(\.path) == [
            "/api/v1/ledgers/import",
            "/api/v1/ledgers/sync",
            "/api/v1/ledgers/restore",
            "/api/v1/ledgers/import"
        ])

        // S5 — 익명 시절 이미 synced가 된 두 행이 모두 새 회원 계정으로 다시 올라간다.
        // 재업로드가 빠지면 비회원 데이터가 새 계정에서 사라진다(피드백 #7).
        let migrationBody = try bodyObject(from: #require(recorder.snapshot().last?.body))
        let migratedEntries = try #require(migrationBody["entries"] as? [[String: Any]])
        let migratedAmounts = try migratedEntries.map {
            try #require($0["amount"] as? NSNumber).decimalValue
        }
        #expect(migratedAmounts.sorted() == [1000, 2000])

        // 잔량 게이트를 실 SyncEngine·실 repository로 통과시켜야 삭제가 일어난다. 대역만으로
        // 검증하면 SyncEngine.hasPendingPush의 판정이 뒤집혀도 아무 테스트가 깨지지 않는다.
        #expect(anonymousAccountDeleter.deletedAccessTokens.count == 1)

        try await repository.setPullCursor(SyncPullCursor(
            updatedAt: "2026-07-20T12:00:00Z",
            id: 77
        ))
        try await repository.insert(LocalTransaction(
            clientEntryID: UUID(),
            amount: Decimal(3000),
            currencyCode: "KRW",
            categoryID: 10,
            assetID: 20,
            transactionType: .expense,
            transactionDate: "2026-07-20",
            memo: "logout push",
            pending: true,
            appliedRate: nil,
            rateBaseDate: nil,
            krwAmount: Decimal(3000)
        ))
        let settingsViewModel = SettingsViewModel(
            loginViewModel: loginViewModel,
            coordinator: sessionCoordinator,
            withdrawalCoordinator: Self.makeWithdrawalCoordinator(
                session: sessionCoordinator,
                auth: auth,
                connectivity: connectivity
            )
        )

        await settingsViewModel.requestLogout()

        #expect(settingsViewModel.logoutState == .completed)
        #expect(auth.signOutCount == 1)
        #expect(auth.currentUserID == logoutUserID)
        #expect(auth.isAnonymous)
        #expect(auth.anonymousSignInCount == 2)
        // 뷰가 없어 `.task`가 돌지 않으므로 신원 구독을 직접 시작한다.
        let identityObservation = Task { await loginViewModel.observeIdentity() }
        await Self.waitUntil { loginViewModel.identityState == .anonymous }
        #expect(loginViewModel.identityState == .anonymous)
        identityObservation.cancel()
        #expect(try await repository.count() == 0)
        #expect(try await repository.pullCursor() == nil)
        #expect(try await repository.isImportDone(memberID: firstUserID) == false)
        // 계정 전환 재업로드가 이미 회원 신원의 import 기준선을 세웠으므로 마지막 push는 건별 sync다.
        #expect(recorder.snapshot().map(\.path) == [
            "/api/v1/ledgers/import",
            "/api/v1/ledgers/sync",
            "/api/v1/ledgers/restore",
            "/api/v1/ledgers/import",
            "/api/v1/ledgers/sync"
        ])
    }
}

private final class BootstrapURLProtocol: URLProtocol {
    static var handler: ((URLRequest) async throws -> (HTTPURLResponse, Data))?
    private var loadingTask: Task<Void, Never>?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        loadingTask = Task { [weak self, request] in
            guard let self else {
                return
            }
            do {
                let (response, data) = try await handler(request)
                guard !Task.isCancelled else {
                    return
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
}

/// 이 스위트는 로그아웃만 다루므로 탈퇴 경로는 호출되지 않는다. 주입만 채운다.
@MainActor
private struct UnusedWithdrawalService: WithdrawalRequesting {
    func withdraw(appleAuthorizationCode _: String?) async throws {
        Issue.record("이 시나리오에서 탈퇴 요청이 나가면 안 된다.")
    }
}

private extension LogoutAndBootstrapIntegrationTests {
    static func makeWithdrawalCoordinator(
        session: SessionTransitionCoordinator,
        auth: FakeAuthService,
        connectivity: FakeConnectivityMonitor
    ) -> WithdrawalCoordinator {
        WithdrawalCoordinator(
            session: session,
            authProvider: auth,
            connectivity: connectivity,
            withdrawalService: UnusedWithdrawalService()
        )
    }

    static func makeTransaction(clientEntryID: UUID) -> LocalTransaction {
        LocalTransaction(
            clientEntryID: clientEntryID,
            amount: Decimal(100),
            currencyCode: "KRW",
            categoryID: 10,
            assetID: 20,
            transactionType: .expense,
            transactionDate: "2026-07-24",
            memo: nil,
            pending: false,
            appliedRate: nil,
            rateBaseDate: nil,
            krwAmount: Decimal(100)
        )
    }

    static func waitUntil(
        _ condition: @escaping () async throws -> Bool
    ) async rethrows {
        for _ in 0 ..< 10000 {
            if try await condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("비동기 통합 시나리오가 제한 시간 안에 수렴하지 않았습니다.")
    }
}
