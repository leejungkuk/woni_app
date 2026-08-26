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
    // swiftlint:disable:next function_body_length
    func pendingDeleteQueueRequiresForcedLogoutAndIsCleared() async throws {
        let memberID = try #require(UUID(uuidString: "30303030-3030-3030-3030-303030303030"))
        let deletedID = try #require(UUID(uuidString: "31313131-3131-3131-3131-313131313131"))
        let auth = FakeAuthService(makeUserID: { memberID })
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let database = try AppDatabase.inMemory()
        let repository = TransactionRepository(database: database)
        let customCategoryCache = CustomCategoryCacheRepository(database: database)
        try await customCategoryCache.replaceSynced([
            CachedCustomCategory(id: 81, transactionType: .expense, name: "야식")
        ])
        let customCategoryStore = try CustomCategoryStore(
            service: CustomCategoryService(),
            cache: customCategoryCache,
            authProvider: auth
        )
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
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: { try await customCategoryStore.clear() }
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
            ),
            dataPurgeCoordinator: Self.makeDataPurgeCoordinator(
                session: coordinator,
                sync: syncEngine,
                store: repository,
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
        #expect(customCategoryStore.expenseCategories.isEmpty)
        #expect(try customCategoryCache.load(for: .expense).isEmpty)
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
        let cleanupMarker = InMemoryLogoutCleanupMarker()
        let sessionCoordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: syncEngine,
            cleanupMarker: cleanupMarker,
            onLogoutCleanup: {}
        )
        syncEngine.configureSessionEntry { [weak sessionCoordinator] in
            await sessionCoordinator?.ensureAnonymousIdentityIfNeeded()
        }
        let anonymousAccountDeleter = FakeAnonymousAccountDeleter()
        let loginViewModel = LoginViewModel(
            authProvider: auth,
            sync: syncEngine,
            coordinator: sessionCoordinator,
            connectivity: connectivity,
            anonymousAccountDeleter: anonymousAccountDeleter
        )
        let addViewModel = try AddExpenseViewModel(
            transactionRepository: repository,
            catalogProvider: CatalogProvider(seedData: addExpenseSeedData()),
            customCategoryStore: makeCustomCategoryStore(),
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
            ),
            dataPurgeCoordinator: Self.makeDataPurgeCoordinator(
                session: sessionCoordinator,
                sync: syncEngine,
                store: repository,
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

extension LogoutAndBootstrapIntegrationTests {
    @Test("릴리스 복구 팩토리는 anonymous 재발급 sync를 실제 SyncEngine에 배선한다")
    func recoveringFactoryWiresAnonymousReissueSync() async throws {
        let oldUserID = UUID()
        let newUserID = UUID()
        var userIDs = [oldUserID, newUserID]
        let auth = FakeAuthService(makeUserID: { userIDs.removeFirst() })
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        let clientEntryID = UUID()
        try await repository.insert(Self.makeTransaction(clientEntryID: clientEntryID))
        try await repository.markSynced(clientEntryIDs: [clientEntryID])
        let session = try await AppDependencyFactory.makeRecoveringSessionDependencies(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            services: AppLedgerServices(
                sync: LedgerService(),
                purge: BootstrapPurgeService(connectivity: connectivity)
            ),
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {},
            onDataCleared: {},
            hasPendingCategoryWork: { false },
            onBeforeLedgerPush: {},
            onAfterLedgerPush: {}
        )

        #expect(try await repository.pendingPushEntries().isEmpty)
        auth.simulateRemoteInvalidation(kind: .anonymous)
        try await Self.waitUntil {
            let pendingCount = try await repository.pendingPushEntries().count
            return auth.currentUserID == newUserID && pendingCount == 1
        }

        #expect(auth.currentUserID == newUserID)
        #expect(auth.anonymousSignInCount == 2)
        #expect(try await repository.pendingPushEntries().count == 1)
        #expect(!session.sessionCoordinator.remoteLogoutNotice)
    }

    @Test("로그인 중 발생한 익명 무효화는 회원 세션에서 원장을 다시 reset하지 않는다")
    func anonymousInvalidationDuringLoginDoesNotResetMemberLedger() async throws {
        let memberID = UUID()
        let auth = FakeAuthService(makeSignedInUserID: { memberID })
        try await auth.ensureIdentity()
        let recorder = SessionTransitionEventRecorder()
        let sync = GatedAccountSwitchSync(recorder: recorder, authProvider: auth)
        let coordinator = SessionTransitionCoordinator(
            repository: RecordingLogoutRepository(recorder: recorder),
            authProvider: auth,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            sync: sync,
            anonymousSync: sync,
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {}
        )
        let loginViewModel = LoginViewModel(
            authProvider: auth,
            sync: sync,
            coordinator: coordinator,
            connectivity: FakeConnectivityMonitor(isOnline: true),
            anonymousAccountDeleter: FakeAnonymousAccountDeleter()
        )
        auth.setRefreshedAccessTokenHandler {
            auth.simulateRemoteInvalidation(kind: .anonymous)
            await Task.yield()
        }

        let login = Task { await loginViewModel.signIn(.google) }
        await sync.waitUntilRestoreStarted()
        sync.releaseRestore()
        await login.value
        // 대기 중인 anonymous logout 전이까지 합류해 추가 reset 여부를 결정적으로 관찰한다.
        await coordinator.handleRemoteSessionInvalidation(.member)

        #expect(loginViewModel.flowState == .completed)
        #expect(auth.signInProviders == [.google])
        #expect(sync.memberIDsAtReset == [memberID])
        #expect(recorder.events == [
            .beginAccountSwitch,
            .resetSyncStateForAccountSwitch,
            .restoreStarted,
            .restoreFinished,
            .finishAccountSwitch
        ])
    }

    @Test("pending purge와 현재 신원이 같으면 suspended 시작 뒤 부팅 kick이 완결한다")
    func matchingPendingPurgeStartsSuspendedAndBootKickCompletes() async throws {
        let memberID = UUID()
        let auth = FakeAuthService(makeSignedInUserID: { memberID })
        try await auth.signIn(.google)
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(clientEntryID: UUID()))
        try await repository.markPurgePending(memberID: memberID.uuidString)
        let service = BootstrapPurgeService(connectivity: connectivity)
        var didClearData = false
        let session = try await AppDependencyFactory.makeRecoveringSessionDependencies(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            services: AppLedgerServices(
                sync: LedgerService(),
                purge: service,
                maxPurgeRetries: 0
            ),
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {},
            onDataCleared: { didClearData = true },
            hasPendingCategoryWork: { false },
            onBeforeLedgerPush: {},
            onAfterLedgerPush: {}
        )

        try await Self.waitUntil {
            session.dataPurgeCoordinator.state == .completed
        }

        #expect(service.deleteCount == 1)
        #expect(try await repository.count() == 0)
        #expect(try await repository.purgePendingMemberID() == nil)
        #expect(!session.syncEngine.isPushSuspendedForPurge)
        #expect(session.syncEngine.ledgerRevision == 1)
        #expect(didClearData)
    }

    @Test("pending purge 신원이 다르면 마커만 해제하고 SyncEngine을 정상 시작한다")
    func mismatchedPendingPurgeClearsMarkerAndStartsNormally() async throws {
        let auth = FakeAuthService(makeSignedInUserID: { UUID() })
        try await auth.signIn(.google)
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.markPurgePending(memberID: UUID().uuidString)

        let session = try await AppDependencyFactory.makeRecoveringSessionDependencies(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            services: AppLedgerServices(
                sync: LedgerService(),
                purge: BootstrapPurgeService(connectivity: connectivity)
            ),
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {},
            onDataCleared: {},
            hasPendingCategoryWork: { false },
            onBeforeLedgerPush: {},
            onAfterLedgerPush: {}
        )

        #expect(!session.syncEngine.isPushSuspendedForPurge)
        #expect(try await repository.purgePendingMemberID() == nil)
    }

    @Test("오프라인 부팅 purge는 pending을 유지하고 온라인 전이에서 자동 완결한다")
    func offlineBootPurgeCompletesOnOnlineTransition() async throws {
        let memberID = UUID()
        let auth = FakeAuthService(makeSignedInUserID: { memberID })
        try await auth.signIn(.google)
        let connectivity = FakeConnectivityMonitor(isOnline: false)
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        try await repository.insert(Self.makeTransaction(clientEntryID: UUID()))
        try await repository.markPurgePending(memberID: memberID.uuidString)
        let service = BootstrapPurgeService(connectivity: connectivity)
        let session = try await AppDependencyFactory.makeRecoveringSessionDependencies(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            services: AppLedgerServices(
                sync: LedgerService(),
                purge: service,
                maxPurgeRetries: 0
            ),
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {},
            onDataCleared: {},
            hasPendingCategoryWork: { false },
            onBeforeLedgerPush: {},
            onAfterLedgerPush: {}
        )

        try await Self.waitUntil {
            session.dataPurgeCoordinator.state == .completionPending(acknowledged: false)
        }
        #expect(try await repository.purgePendingMemberID() == memberID.uuidString)
        #expect(session.syncEngine.isPushSuspendedForPurge)

        connectivity.setOnline(true)
        try await Self.waitUntil {
            let pendingMemberID = try await repository.purgePendingMemberID()
            return session.dataPurgeCoordinator.state == .completed && pendingMemberID == nil
        }

        #expect(service.deleteCount == 2)
        #expect(try await repository.count() == 0)
        #expect(!session.syncEngine.isPushSuspendedForPurge)
        #expect(session.dataPurgeCoordinator.state == .completed)
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

@MainActor
private final class BootstrapPurgeService: LedgerPurging {
    private let connectivity: FakeConnectivityMonitor
    private(set) var deleteCount = 0

    init(connectivity: FakeConnectivityMonitor) {
        self.connectivity = connectivity
    }

    func deleteAll(accessToken _: String) async throws {
        deleteCount += 1
        guard connectivity.isOnline else {
            throw APIError.transport(URLError(.notConnectedToInternet))
        }
    }
}

/// 이 스위트는 로그아웃만 다루므로 탈퇴 경로는 호출되지 않는다. 주입만 채운다.
@MainActor
private struct UnusedWithdrawalService: WithdrawalRequesting {
    func withdraw(appleAuthorizationCode _: String?) async throws {
        Issue.record("이 시나리오에서 탈퇴 요청이 나가면 안 된다.")
    }
}

private struct UnusedIntegrationPurgeService: LedgerPurging {
    func deleteAll(accessToken _: String) async throws {
        Issue.record("이 시나리오에서 데이터 전체 삭제 요청이 나가면 안 된다.")
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

    static func makeDataPurgeCoordinator(
        session: SessionTransitionCoordinator,
        sync: SyncEngine,
        store: TransactionRepository,
        auth: FakeAuthService,
        connectivity: FakeConnectivityMonitor
    ) -> DataPurgeCoordinator {
        DataPurgeCoordinator(
            session: session,
            purgeSync: sync,
            purgeStore: store,
            ledgerService: UnusedIntegrationPurgeService(),
            authProvider: auth,
            connectivity: connectivity,
            onDataCleared: {}
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

// MARK: - 서버에서 지워진 익명 세션

extension LogoutAndBootstrapIntegrationTests {
    /// Supabase에서 익명 유저를 지워도 로컬 세션 객체는 남는다. 그 상태의 push는 401을 맞고
    /// refresh가 세션을 지우며 무효화를 알린다. 그때 신원이 갈리므로 리셋이 먼저 돌아야 한다 —
    /// 리셋 전에 나가도 되는 원장 요청은 401을 맞은 최초 1건뿐이다. 리셋이 늦으면 로컬 행이 옛
    /// 신원의 서버 카테고리 id를 든 채 새 신원으로 나가 서버가 CATEGORY_NOT_FOUND를 돌려준다.
    ///
    /// 코디네이터를 `let`으로 붙잡고 대기 조건을 단언 대상(`resetCount`)으로 두는 것이 이 테스트의
    /// 전제다. `_ =`로 버리면 deinit이 무효화 구독을 cancel하고, 대기 조건을 프록시로 두면 이미
    /// 참이라 즉시 반환해 코디네이터가 돌 기회를 못 받는다 — 둘 다 결함과 무관하게 빨간불을 만든다.
    @Test("서버가 지운 익명 세션을 새 신원으로 대체할 때 이전 신원의 행을 리셋 없이 밀지 않는다")
    func staleAnonymousSessionReissueResetsBeforePushingPreviousRows() async throws {
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let staleIdentity = try #require(auth.currentUserID)
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let database = try AppDatabase.inMemory()
        let repository = TransactionRepository(database: database)
        let recorder = SyncPushRequestRecorder()
        var resetCount = 0
        var ledgerRequestsBeforeReset: Int?
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncPushURLProtocol.self]
        let syncEngine = SyncEngine(
            repository: repository,
            ledgerService: LedgerService(client: APIClient(
                session: URLSession(configuration: configuration),
                authProvider: auth
            )),
            authProvider: auth,
            connectivity: connectivity,
            onAccountSwitchReset: {
                resetCount += 1
                ledgerRequestsBeforeReset = recorder.snapshot().count
            }
        )
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: syncEngine,
            anonymousSync: syncEngine,
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {}
        )
        try await repository.insert(Self.makeTransaction(clientEntryID: UUID()))
        // 지워진 신원의 refresh는 로컬 세션까지 지우고 무효화를 알린다(supabase-swift 실제 동작).
        auth.setRefreshedAccessTokenHandler { [weak auth] in
            auth?.simulateRemoteInvalidation(removingCurrentSession: true, kind: .anonymous)
        }
        SyncPushURLProtocol.handler = { request in
            recorder.record(request)
            return try response(
                for: request,
                statusCode: 401,
                data: Data(#"{"success":false,"code":"UNAUTHORIZED","message":"gone"}"#.utf8)
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        await syncEngine.pushPending()
        // 앱은 여기서 멈추지 않는다 — debounce 재시도와 다음 저장이 곧바로 push를 다시 민다.
        await syncEngine.pushPending()
        await Self.waitUntil { resetCount == 1 }

        #expect(auth.currentUserID != staleIdentity)
        #expect(resetCount == 1)
        #expect(ledgerRequestsBeforeReset == 1)
        withExtendedLifetime(coordinator) {}
    }
}

// MARK: - 지워진 익명 세션과 카테고리 큐

/// 익명 신원 A 시절 서버 id를 받은 카테고리를, 신원이 갈린 뒤 그대로 다시 보내는지 본다.
/// 실기(2026-08-26)에서 서버가 `CATEGORY_NOT_FOUND`를 돌려준 요청이 원장이 아니라 카테고리
/// 큐였다 — `flushPending`은 `onBeforeLedgerPush`로 push 안에서 돌아 원장보다 먼저 나간다.
@MainActor
private final class StaleIdentityCategoryServiceStub: CustomCategoryServicing {
    private let onUpdate: @MainActor (Int) async -> Void
    private(set) var updateCalls: [Int] = []

    init(onUpdate: @escaping @MainActor (Int) async -> Void) {
        self.onUpdate = onUpdate
    }

    func fetchCustomCategories(transactionType _: String) async throws -> [CategoryDTO] {
        []
    }

    func createCustomCategory(name _: String, transactionType _: String) async throws -> CategoryDTO {
        throw APIError.server(code: "CATEGORY_NOT_FOUND", message: "gone")
    }

    func updateCustomCategory(id: Int, name _: String) async throws -> CategoryDTO {
        updateCalls.append(id)
        await onUpdate(updateCalls.count)
        throw updateCalls.count == 1
            ? APIError.server(code: "UNAUTHORIZED", message: "dead session")
            : APIError.server(code: "CATEGORY_NOT_FOUND", message: "gone")
    }

    func reorderCustomCategories(orderedIDs _: [Int], transactionType _: String) async throws -> [CategoryDTO] {
        []
    }

    func deleteCustomCategory(id _: Int) async throws {
        throw APIError.server(code: "CATEGORY_NOT_FOUND", message: "gone")
    }
}

extension LogoutAndBootstrapIntegrationTests {
    @Test(
        "지워진 익명 세션에서 카테고리 큐가 새 신원으로 옛 서버 id를 다시 보내지 않는다"
    )
    // swiftlint:disable:next function_body_length
    func staleAnonymousSessionDoesNotReflushPreviousIdentityCategories() async throws {
        let auth = FakeAuthService()
        try await auth.ensureIdentity()
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let database = try AppDatabase.inMemory()
        let repository = TransactionRepository(database: database)
        let cache = CustomCategoryCacheRepository(database: database)
        // 익명 신원 A 시절 서버가 부여한 id 55. 신원이 갈리면 새 계정엔 없는 id다.
        try await cache.replaceSynced([
            CachedCustomCategory(id: 55, transactionType: .expense, name: "야식")
        ])

        var resetCount = 0
        var categoryUpdatesBeforeReset: Int?
        var store: CustomCategoryStore?
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncPushURLProtocol.self]
        let service = StaleIdentityCategoryServiceStub { [weak auth] callIndex in
            // 첫 전송은 죽은 신원 A로 나가 401을 맞는다. 그 401 처리가 로컬 세션을 지우고
            // 무효화를 알리는 것이 supabase-swift의 실제 동작이다.
            guard callIndex == 1 else { return }
            auth?.simulateRemoteInvalidation(removingCurrentSession: true, kind: .anonymous)
        }
        let syncEngine = SyncEngine(
            repository: repository,
            ledgerService: LedgerService(client: APIClient(
                session: URLSession(configuration: configuration),
                authProvider: auth
            )),
            authProvider: auth,
            connectivity: connectivity,
            hasPendingCategoryWork: { store?.hasPendingWork() ?? false },
            onBeforeLedgerPush: { await store?.flushPending() },
            onAfterLedgerPush: { await store?.flushPendingDeletes() },
            onAccountSwitchReset: {
                resetCount += 1
                categoryUpdatesBeforeReset = service.updateCalls.count
                try await store?.resetForAccountSwitch()
            }
        )
        let categoryStore = try CustomCategoryStore(service: service, cache: cache, authProvider: auth)
        store = categoryStore
        categoryStore.configure { operation in
            try await syncEngine.performLocalWrite(operation)
        }
        let coordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: auth,
            connectivity: connectivity,
            sync: syncEngine,
            anonymousSync: syncEngine,
            cleanupMarker: InMemoryLogoutCleanupMarker(),
            onLogoutCleanup: {}
        )
        SyncPushURLProtocol.handler = { request in
            try response(
                for: request,
                statusCode: 401,
                data: Data(#"{"success":false,"code":"UNAUTHORIZED","message":"dead"}"#.utf8)
            )
        }
        defer { SyncPushURLProtocol.handler = nil }

        try await categoryStore.rename(id: 55, name: "야식 수정")
        await syncEngine.pushPending()
        await syncEngine.pushPending()
        await Self.waitUntil { resetCount == 1 }

        // 신원 A로 나간 최초 1건만 리셋보다 앞설 수 있다. 2건이면 새 신원으로 옛 id를 다시 보낸 것이다.
        #expect(categoryUpdatesBeforeReset == 1)
        // 404 수렴이 돌면 사용자에게 "쓰던 카테고리가 삭제됐어요"가 뜬다 — 재발급은 삭제가 아니다.
        #expect(categoryStore.consumeSyncNotice() != .categoryNotFound)
        withExtendedLifetime(coordinator) {}
    }
}
