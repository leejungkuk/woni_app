//
//  woni_appApp.swift
//  woni_app
//
//  Created by J on 6/2/26.
//

import OSLog
import SwiftUI

// 프로덕션 파일이 file_length를 넘긴 채 남아 있는 예외 2곳 중 하나다 — lint 계산값 828줄로
// warning(500)뿐 아니라 error(800)까지 넘겼다.
// 앱 부트스트랩·의존성 조립·전역 라이프사이클이 한 파일에 뭉쳐 있는 게 원인이므로 분할이 정답이고,
// 이 주석은 "허용"이 아니라 남은 부채 표시다. 여기에 새 책임을 더 얹지 마라.
// swiftlint:disable file_length

@main
struct WoniApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var startupState: AppStartupState = .loading
    @State private var didStartDependencyLoad = false
    @State private var languageStore = AppLanguageStore()
    @State private var baseCurrencyStore = BaseCurrencyStore()

    init() {
        WoniFontFamily.register()
    }

    var body: some Scene {
        WindowGroup {
            appContent
                .task {
                    await loadDependenciesIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active,
                          case let .loaded(dependencies) = startupState
                    else {
                        return
                    }
                    Task {
                        await dependencies.handleForegroundActivation()
                    }
                }
                .environment(languageStore)
                .environment(baseCurrencyStore)
        }
    }

    @ViewBuilder
    private var appContent: some View {
        switch startupState {
        case .loading:
            AppLoadingView()
        case let .loaded(dependencies):
            MainRootView(
                dependencies: dependencies,
                languageStore: languageStore,
                baseCurrencyStore: baseCurrencyStore
            )
        case let .failed(error):
            AppStartupFailureView(error: error, language: languageStore.language)
        }
    }

    @MainActor
    private func loadDependenciesIfNeeded() async {
        // XCTest 호스트 부팅이 실 네트워크와 실 파일 DB를 건드리지 않도록 조립을 시작하지 않는다.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        guard !didStartDependencyLoad else {
            return
        }

        didStartDependencyLoad = true
        startupState = .loading

        do {
            let dependencies = try await Self.makeDependencies()
            startupState = .loaded(dependencies)
            if scenePhase == .active {
                await dependencies.handleForegroundActivation()
            }
        } catch {
            startupState = .failed(error)
        }
    }

    /// UI 테스트 실행일 때만 격리된 의존성으로 갈아끼운다. 릴리스 빌드에는 분기 자체가 남지 않는다.
    private static func makeDependencies() async throws -> AppDependencies {
        #if DEBUG
            if UITestSupport.isEnabled {
                return try await UITestSupport.makeDependencies()
            }
        #endif
        return try await AppDependencyFactory.makeMainDependencies()
    }
}

private enum AppStartupState {
    case loading
    case loaded(AppDependencies)
    case failed(Error)
}

private struct AppLoadingView: View {
    var body: some View {
        ProgressView()
            .tint(WoniColor.olive100)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WoniColor.base10)
    }
}

private struct AppStartupFailureView: View {
    let error: Error
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 8) {
            Text(WoniStrings.appStartFailedTitle(language))
                .woniFont(.body1)
                .foregroundStyle(WoniColor.gray100)
            Text(error.localizedDescription)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray80)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WoniColor.base10)
    }
}

@MainActor
@Observable
final class ForegroundActivationSignal {
    private(set) var revision = 0

    func bump() {
        revision += 1
    }
}

@MainActor
final class ForegroundMainReloadCoordinator {
    private var lastHandledRevision = 0

    func handle(
        revision: Int,
        baseCurrency: SelectableCurrency,
        reload: @MainActor () async -> Void
    ) async {
        guard revision > lastHandledRevision else {
            return
        }

        lastHandledRevision = revision
        guard baseCurrency != .krw else {
            return
        }

        await reload()
    }
}

private struct MainRootView: View {
    let dependencies: AppDependencies
    let languageStore: AppLanguageStore
    let baseCurrencyStore: BaseCurrencyStore
    @State private var mainViewModel: MainViewModel
    @State private var sessionViewModel: MainRootSessionViewModel
    @State private var foregroundReloadCoordinator = ForegroundMainReloadCoordinator()
    @State private var lastUsedCurrencyStore = LastUsedCurrencyStore()
    @State private var navigationPath: [MainRoute] = []
    @State private var entryPresentation: EntryPresentation?
    @State private var toastMessage: String?

    init(
        dependencies: AppDependencies,
        languageStore: AppLanguageStore,
        baseCurrencyStore: BaseCurrencyStore
    ) {
        self.dependencies = dependencies
        self.languageStore = languageStore
        self.baseCurrencyStore = baseCurrencyStore
        let mainViewModel = MainViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            customCategoryStore: dependencies.customCategoryStore,
            rateProvider: dependencies.mainRateProvider,
            baseRateResolver: BaseRateResolver(
                cache: dependencies.exchangeRateCache,
                seedRateProvider: dependencies.mainRateProvider
            ),
            baseCurrency: baseCurrencyStore.baseCurrency,
            language: languageStore.language
        )
        _mainViewModel = State(initialValue: mainViewModel)
        _sessionViewModel = State(initialValue: MainRootSessionViewModel(
            coordinator: dependencies.sessionCoordinator,
            reloadMain: { await mainViewModel.reload() }
        ))
    }

    var body: some View {
        Group {
            if sessionViewModel.isCleanupBlocking {
                MainRootCleanupBlockingView(
                    language: languageStore.language,
                    retry: {
                        Task {
                            await sessionViewModel.retryCleanup()
                        }
                    }
                )
            } else {
                NavigationStack(path: $navigationPath) {
                    MainView(
                        viewModel: mainViewModel,
                        language: languageStore.language,
                        onAdd: { defaultDate in
                            entryPresentation = .create(defaultDate)
                        },
                        onSelectEntry: { clientEntryID in
                            entryPresentation = .edit(clientEntryID)
                        },
                        onOpenSettings: {
                            navigationPath.append(.settings)
                        }
                    )
                    .navigationDestination(for: MainRoute.self) { _ in
                        settingsDestination()
                    }
                }
                .woniToast($toastMessage)
                .fullScreenCover(item: $entryPresentation) { presentation in
                    switch presentation {
                    case let .create(defaultDate):
                        addExpenseDestination(defaultDate: defaultDate)
                    case let .edit(clientEntryID):
                        editEntryDestination(clientEntryID: clientEntryID)
                    }
                }
            }
        }
        .onAppear {
            mainViewModel.applyLanguage(languageStore.language)
        }
        .onChange(of: languageStore.language) { _, newValue in
            mainViewModel.applyLanguage(newValue)
        }
        .onChange(of: baseCurrencyStore.baseCurrency) { _, newValue in
            lastUsedCurrencyStore.clear()
            Task {
                await mainViewModel.applyBaseCurrency(newValue)
            }
        }
        .onChange(
            of: dependencies.foregroundActivationSignal.revision,
            initial: true
        ) { _, revision in
            Task {
                await foregroundReloadCoordinator.handle(
                    revision: revision,
                    baseCurrency: baseCurrencyStore.baseCurrency,
                    reload: { _ = await mainViewModel.reload() }
                )
            }
        }
        .onChange(
            of: dependencies.sessionCoordinator.remoteLogoutNotice,
            initial: true
        ) { _, isPresented in
            Task {
                await sessionViewModel.handleRemoteLogoutNoticeChange(isPresented)
            }
        }
        .onChange(of: sessionViewModel.navigationResetGeneration) { _, _ in
            navigationPath.removeAll()
            entryPresentation = nil
        }
        .alert(
            WoniStrings.remoteLogoutTitle(languageStore.language),
            isPresented: remoteLogoutAlertBinding
        ) {
            Button(WoniStrings.confirmOK(languageStore.language), role: .cancel) {
                sessionViewModel.acknowledgeRemoteLogoutNotice()
            }
        } message: {
            Text(WoniStrings.remoteLogoutMessage(languageStore.language))
        }
        .task {
            let syncEngine = dependencies.syncEngine
            await mainViewModel.observeLedgerChanges(
                syncEngine.ledgerDidChange,
                revision: { syncEngine.ledgerRevision }
            )
        }
    }

    private var remoteLogoutAlertBinding: Binding<Bool> {
        Binding(
            get: { sessionViewModel.isRemoteLogoutAlertPresented },
            set: { isPresented in
                if !isPresented {
                    sessionViewModel.acknowledgeRemoteLogoutNotice()
                }
            }
        )
    }

    private func settingsDestination() -> some View {
        SettingsView(
            viewModel: AppDependencyFactory.makeSettingsViewModel(dependencies: dependencies),
            onFinish: { wasMember in
                dismissCurrentRoute()
                toastMessage = wasMember
                    ? WoniStrings.withdrawCompletedToastMember(languageStore.language)
                    : WoniStrings.withdrawCompletedToastGuest(languageStore.language)
            }
        )
    }

    private func addExpenseDestination(defaultDate: Date) -> some View {
        let viewModel = AppDependencyFactory.makeAddExpenseViewModel(
            dependencies: dependencies,
            baseCurrency: baseCurrencyStore.baseCurrency,
            lastUsedCurrencyStore: lastUsedCurrencyStore
        )
        viewModel.date = defaultDate
        return AddEntryView(
            viewModel: viewModel,
            makeCategoryManageViewModel: makeCategoryManageViewModel,
            makeCategoryAddViewModel: makeCategoryAddViewModel,
            onClose: finishCurrentRouteAndReload,
            onFinish: finishEntryRoute
        )
        .toolbar(.hidden, for: .navigationBar)
    }

    private func makeCategoryManageViewModel(tab: EntryType) -> CategoryManageViewModel {
        AppDependencyFactory.makeCategoryManageViewModel(dependencies: dependencies, tab: tab)
    }

    private func makeCategoryAddViewModel(
        tab: EntryType,
        mode: CategoryAddViewModel.Mode,
        name: String
    ) -> CategoryAddViewModel {
        AppDependencyFactory.makeCategoryAddViewModel(
            dependencies: dependencies,
            tab: tab,
            mode: mode,
            name: name
        )
    }

    @ViewBuilder
    private func editEntryDestination(clientEntryID: UUID) -> some View {
        if let original = mainViewModel.transaction(clientEntryID: clientEntryID) {
            AddEntryView(
                viewModel: AppDependencyFactory.makeAddExpenseViewModel(
                    dependencies: dependencies,
                    baseCurrency: baseCurrencyStore.baseCurrency,
                    mode: .edit(original: original)
                ),
                makeCategoryManageViewModel: makeCategoryManageViewModel,
                makeCategoryAddViewModel: makeCategoryAddViewModel,
                // 이 화면에서도 카테고리 관리로 들어가 이름을 바꿀 수 있다. 저장 없이 닫아도
                // 내역 스냅샷은 이미 갱신됐으므로, 새 내역 경로와 똑같이 홈을 다시 읽는다.
                onClose: finishCurrentRouteAndReload,
                onFinish: finishEntryRoute
            )
            .toolbar(.hidden, for: .navigationBar)
        } else {
            MissingEntryView(
                language: languageStore.language,
                onClose: finishCurrentRouteAndReload
            )
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// 입력 화면 종료 공통 처리. 삭제로 끝났을 때만 홈에서 완료 토스트를 띄운다.
    private func finishEntryRoute(didDelete: Bool) {
        finishCurrentRouteAndReload()
        if didDelete {
            toastMessage = WoniStrings.entryDeletedToast(languageStore.language)
        }
    }

    private func finishCurrentRouteAndReload() {
        entryPresentation = nil
        Task {
            await mainViewModel.reload()
        }
    }

    private func dismissCurrentRoute() {
        guard !navigationPath.isEmpty else {
            return
        }

        navigationPath.removeLast()
    }
}

private struct MissingEntryView: View {
    let language: AppLanguage
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(WoniStrings.transactionNotFoundTitle(language))
                .woniFont(.body1)
                .foregroundStyle(WoniColor.gray100)
            Text(WoniStrings.transactionNotFoundMessage(language))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray60)
                .multilineTextAlignment(.center)
            Button(WoniStrings.confirmOK(language), action: onClose)
                .buttonStyle(.borderedProminent)
                .tint(WoniColor.olive100)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WoniColor.base10)
    }
}

@MainActor
@Observable
final class MainRootSessionViewModel {
    private let coordinator: SessionTransitionCoordinator
    private let reloadMain: @MainActor () async -> Void
    private var handledRemoteLogoutNotice = false
    private var isCompletingCleanup = false

    private(set) var navigationResetGeneration = 0

    init(
        coordinator: SessionTransitionCoordinator,
        reloadMain: @escaping @MainActor () async -> Void
    ) {
        self.coordinator = coordinator
        self.reloadMain = reloadMain
    }

    var isRemoteLogoutAlertPresented: Bool {
        coordinator.remoteLogoutNotice
    }

    var isCleanupBlocking: Bool {
        coordinator.needsCleanup || isCompletingCleanup
    }

    func handleRemoteLogoutNoticeChange(_ isPresented: Bool) async {
        guard isPresented else {
            handledRemoteLogoutNotice = false
            return
        }
        guard !handledRemoteLogoutNotice else {
            return
        }

        handledRemoteLogoutNotice = true
        navigationResetGeneration += 1
        await reloadMain()
    }

    func acknowledgeRemoteLogoutNotice() {
        coordinator.acknowledgeRemoteLogoutNotice()
    }

    func retryCleanup() async {
        guard coordinator.needsCleanup, !isCompletingCleanup else {
            return
        }
        isCompletingCleanup = true
        await coordinator.retryCleanup()
        if !coordinator.needsCleanup {
            navigationResetGeneration += 1
            await reloadMain()
        }
        isCompletingCleanup = false
    }
}

private struct MainRootCleanupBlockingView: View {
    let language: AppLanguage
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(WoniStrings.logoutCleanupRequiredTitle(language))
                .woniFont(.h4)
                .foregroundStyle(WoniColor.gray100)
            Text(WoniStrings.logoutCleanupRequiredMessage(language))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray80)
                .multilineTextAlignment(.center)
            Button(WoniStrings.retry(language), action: retry)
                .buttonStyle(.borderedProminent)
                .tint(WoniColor.olive100)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WoniColor.base10)
    }
}

enum MainRoute: Hashable {
    case settings
}

enum EntryPresentation: Identifiable, Hashable {
    case create(Date)
    case edit(UUID)

    var id: Self {
        self
    }
}

struct AppDependencies {
    nonisolated static let logger = Logger(subsystem: "woni_app", category: "Foreground")

    let transactionRepository: TransactionRepository
    let catalogProvider: CatalogProvider
    let mainRateProvider: RateProvider
    let addExpenseRateProvider: any RateProviding
    let exchangeRateCache: any ExchangeRateCaching
    let customCategoryStore: CustomCategoryStore
    let prefetchRates: @Sendable () async -> Void
    let authProvider: any AuthProviding
    let connectivity: any ConnectivityObserving
    let syncEngine: SyncEngine
    let logoutCleanupMarker: any LogoutCleanupMarking
    let sessionCoordinator: SessionTransitionCoordinator
    let withdrawalCoordinator: WithdrawalCoordinator
    let dataPurgeCoordinator: DataPurgeCoordinator
    let foregroundActivationRunner: ForegroundActivationRunner
    let foregroundActivationSignal: ForegroundActivationSignal

    func handleForegroundActivation() async {
        await foregroundActivationRunner.run {
            await Self.handleForegroundActivation(
                resumePurge: { await dataPurgeCoordinator.resumeIfPending() },
                sync: syncEngine,
                coordinator: sessionCoordinator,
                refreshCustomCategories: { await customCategoryStore.refresh() },
                prefetchRates: prefetchRates,
                signal: foregroundActivationSignal
            )
        }
    }

    static func handleForegroundActivation(
        resumePurge: @MainActor () async -> Void = {},
        sync: any ForegroundSyncing,
        coordinator: SessionTransitionCoordinator,
        refreshCustomCategories: @MainActor () async -> Void = {},
        prefetchRates: @Sendable () async -> Void,
        signal: ForegroundActivationSignal
    ) async {
        await resumePurge()
        await sync.pushPending()
        let shouldPull = await coordinator.runForegroundSessionProbe()
        if shouldPull {
            do {
                try await sync.pullChanges()
            } catch {
                Self.logger.error(
                    "Failed to pull foreground changes: \(String(describing: error), privacy: .private)"
                )
            }
        }
        await refreshCustomCategories()
        await prefetchRates()
        signal.bump()
    }
}

struct AppExchangeRateDependencies {
    let rateProvider: any RateProviding
    let cache: any ExchangeRateCaching
    let prefetchRates: @Sendable () async -> Void
}

struct AppRecoveringSessionDependencies {
    let syncEngine: SyncEngine
    let sessionCoordinator: SessionTransitionCoordinator
    let dataPurgeCoordinator: DataPurgeCoordinator
}

struct AppLedgerServices {
    let sync: LedgerService
    let purge: any LedgerPurging
    let maxPurgeRetries: Int

    init(sync: LedgerService, purge: any LedgerPurging, maxPurgeRetries: Int = 3) {
        self.sync = sync
        self.purge = purge
        self.maxPurgeRetries = maxPurgeRetries
    }
}

// swiftlint:disable:next type_body_length
enum AppDependencyFactory {
    // swiftlint:disable:next function_body_length
    static func makeMainDependencies(inMemory: Bool = false) async throws -> AppDependencies {
        let database: AppDatabase
        if inMemory {
            database = try AppDatabase.inMemory()
        } else {
            database = try AppDatabase()
        }

        let seedData = try SeedLoader().load()
        let catalogProvider = await CatalogLoader(
            service: CatalogService(),
            seedData: seedData
        ).load()
        let mainRateProvider = RateProvider(seedData: seedData)
        let transactionRepository = TransactionRepository(database: database)
        let customCategoryCache = CustomCategoryCacheRepository(database: database)
        let exchangeRate = makeExchangeRateDependencies(
            database: database,
            seedRateProvider: mainRateProvider
        )
        let authProvider = try SupabaseAuthService()
        let logoutCleanupMarker = LogoutCleanupMarker()
        try await recoverIncompleteLogout(
            repository: transactionRepository,
            customCategoryCache: customCategoryCache,
            authProvider: authProvider,
            cleanupMarker: logoutCleanupMarker
        )
        let customCategoryStore = try CustomCategoryStore(
            service: CustomCategoryService(client: APIClient(authProvider: authProvider)),
            cache: customCategoryCache,
            authProvider: authProvider
        )
        let connectivity = ConnectivityMonitor()
        let ledgerService = LedgerService(client: APIClient(authProvider: authProvider))
        let session = try await makeRecoveringSessionDependencies(
            repository: transactionRepository,
            authProvider: authProvider,
            connectivity: connectivity,
            services: AppLedgerServices(sync: ledgerService, purge: ledgerService),
            cleanupMarker: logoutCleanupMarker,
            onLogoutCleanup: { try await customCategoryStore.clear() },
            onDataCleared: { try? await customCategoryStore.clear() },
            hasPendingCategoryWork: { customCategoryStore.hasPendingWork() },
            onBeforeLedgerPush: { await customCategoryStore.flushPending() },
            onAfterLedgerPush: { await customCategoryStore.flushPendingDeletes() },
            onAccountSwitchReset: { try await customCategoryStore.resetForAccountSwitch() }
        )
        // 엔진이 카테고리 훅으로 Store를 잡고 Store가 게이트로 엔진을 잡으면 순환이 된다.
        // 엔진을 weak로 잡고, 사라졌으면 조용히 통과시키지 않고 명시적으로 실패시킨다.
        customCategoryStore.configure { [weak syncEngine = session.syncEngine] operation in
            guard let syncEngine else {
                throw SyncEngineError.localWritesSuspended
            }
            try await syncEngine.performLocalWrite(operation)
        }
        let withdrawalCoordinator = WithdrawalCoordinator(
            session: session.sessionCoordinator,
            authProvider: authProvider,
            connectivity: connectivity,
            withdrawalService: MemberService(client: APIClient(authProvider: authProvider))
        )

        return AppDependencies(
            transactionRepository: transactionRepository,
            catalogProvider: catalogProvider,
            mainRateProvider: mainRateProvider,
            addExpenseRateProvider: exchangeRate.rateProvider,
            exchangeRateCache: exchangeRate.cache,
            customCategoryStore: customCategoryStore,
            prefetchRates: exchangeRate.prefetchRates,
            authProvider: authProvider,
            connectivity: connectivity,
            syncEngine: session.syncEngine,
            logoutCleanupMarker: logoutCleanupMarker,
            sessionCoordinator: session.sessionCoordinator,
            withdrawalCoordinator: withdrawalCoordinator,
            dataPurgeCoordinator: session.dataPurgeCoordinator,
            foregroundActivationRunner: ForegroundActivationRunner(),
            foregroundActivationSignal: ForegroundActivationSignal()
        )
    }

    /// 캐시 저장소 단일 인스턴스를 prefetcher와 provider 양쪽에 주입한다 — 한쪽이라도 누락되면
    /// 폴백 체인이 조용히 비활성화되므로, composition 테스트가 이 함수를 직접 호출해 검증한다.
    static func makeExchangeRateDependencies(
        database: AppDatabase,
        seedRateProvider: RateProvider,
        service: ExchangeRateService = ExchangeRateService(),
        coverageStore: RateBackfillCoverageStore = RateBackfillCoverageStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) -> AppExchangeRateDependencies {
        let cacheRepository = ExchangeRateCacheRepository(database: database)
        let prefetcher = ExchangeRatePrefetcher(
            service: service,
            cache: cacheRepository,
            coverageStore: coverageStore,
            seedCoveredThrough: seedRateProvider.latestSeedBaseDate,
            now: now
        )
        let rateProvider = ServerRateProvider(
            service: service,
            seedRateProvider: seedRateProvider,
            cache: cacheRepository
        )
        return AppExchangeRateDependencies(
            rateProvider: rateProvider,
            cache: cacheRepository,
            prefetchRates: { await prefetcher.backfillMissingRates() }
        )
    }

    // swiftlint:disable:next function_body_length
    static func makeSeedDependencies(
        inMemory: Bool = false,
        customCategoryService: (any CustomCategoryServicing)? = nil
    ) throws -> AppDependencies {
        let database: AppDatabase
        if inMemory {
            database = try AppDatabase.inMemory()
        } else {
            database = try AppDatabase()
        }

        let seedData = try SeedLoader().load()
        let mainRateProvider = RateProvider(seedData: seedData)
        let transactionRepository = TransactionRepository(database: database)
        let exchangeRateCache = ExchangeRateCacheRepository(database: database)
        let customCategoryCache = CustomCategoryCacheRepository(database: database)
        let authProvider = FakeAuthService()
        let customCategoryStore = try CustomCategoryStore(
            service: customCategoryService ?? SeedCustomCategoryService(),
            cache: customCategoryCache,
            authProvider: authProvider
        )
        let connectivity = FakeConnectivityMonitor()
        let logoutCleanupMarker = InMemoryLogoutCleanupMarker()
        let syncEngine = SyncEngine(
            repository: transactionRepository,
            ledgerService: LedgerService(client: APIClient(authProvider: authProvider)),
            authProvider: authProvider,
            connectivity: connectivity,
            hasPendingCategoryWork: { customCategoryStore.hasPendingWork() },
            onBeforeLedgerPush: { await customCategoryStore.flushPending() },
            onAfterLedgerPush: { await customCategoryStore.flushPendingDeletes() },
            onAccountSwitchReset: { try await customCategoryStore.resetForAccountSwitch() }
        )
        customCategoryStore.configure { [weak syncEngine] operation in
            guard let syncEngine else {
                throw SyncEngineError.localWritesSuspended
            }
            try await syncEngine.performLocalWrite(operation)
        }
        let sessionCoordinator = SessionTransitionCoordinator(
            repository: transactionRepository,
            authProvider: authProvider,
            connectivity: connectivity,
            sync: syncEngine,
            anonymousSync: syncEngine,
            cleanupMarker: logoutCleanupMarker,
            onLogoutCleanup: { try await customCategoryStore.clear() }
        )
        let withdrawalCoordinator = WithdrawalCoordinator(
            session: sessionCoordinator,
            authProvider: authProvider,
            connectivity: connectivity,
            withdrawalService: MemberService(client: APIClient(authProvider: authProvider))
        )
        let dataPurgeCoordinator = DataPurgeCoordinator(
            session: sessionCoordinator,
            purgeSync: syncEngine,
            purgeStore: transactionRepository,
            ledgerService: SeedLedgerPurgeService(),
            authProvider: authProvider,
            connectivity: connectivity,
            onDataCleared: {
                syncEngine.publishLedgerChange()
                try? await customCategoryStore.clear()
            }
        )

        return AppDependencies(
            transactionRepository: transactionRepository,
            catalogProvider: CatalogProvider(seedData: seedData),
            mainRateProvider: mainRateProvider,
            addExpenseRateProvider: SeedRateProviderAdapter(rateProvider: mainRateProvider),
            exchangeRateCache: exchangeRateCache,
            customCategoryStore: customCategoryStore,
            prefetchRates: {},
            authProvider: authProvider,
            connectivity: connectivity,
            syncEngine: syncEngine,
            logoutCleanupMarker: logoutCleanupMarker,
            sessionCoordinator: sessionCoordinator,
            withdrawalCoordinator: withdrawalCoordinator,
            dataPurgeCoordinator: dataPurgeCoordinator,
            foregroundActivationRunner: ForegroundActivationRunner(),
            foregroundActivationSignal: ForegroundActivationSignal()
        )
    }

    static func makeAddExpenseViewModel(
        inMemory: Bool = false,
        baseCurrency: SelectableCurrency = .krw
    ) throws -> AddExpenseViewModel {
        try makeAddExpenseViewModel(
            dependencies: makeSeedDependencies(inMemory: inMemory),
            baseCurrency: baseCurrency
        )
    }

    static func makeAddExpenseViewModel(
        dependencies: AppDependencies,
        baseCurrency: SelectableCurrency,
        lastUsedCurrencyStore: LastUsedCurrencyStore? = nil,
        mode: AddExpenseViewModel.Mode = .create
    ) -> AddExpenseViewModel {
        AddExpenseViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            customCategoryStore: dependencies.customCategoryStore,
            addExpenseRateProvider: dependencies.addExpenseRateProvider,
            baseCurrency: baseCurrency,
            lastUsedCurrencyStore: lastUsedCurrencyStore,
            syncTrigger: dependencies.syncEngine,
            mode: mode
        )
    }

    static func makeCategoryManageViewModel(
        dependencies: AppDependencies,
        tab: EntryType
    ) -> CategoryManageViewModel {
        CategoryManageViewModel(
            tab: tab,
            customCategoryStore: dependencies.customCategoryStore
        )
    }

    static func makeSettingsViewModel(dependencies: AppDependencies) -> SettingsViewModel {
        let loginViewModel = LoginViewModel(
            authProvider: dependencies.authProvider,
            sync: dependencies.syncEngine,
            coordinator: dependencies.sessionCoordinator,
            connectivity: dependencies.connectivity,
            anonymousAccountDeleter: MemberService(
                client: APIClient(authProvider: dependencies.authProvider)
            ),
            onSignInCompleted: { await dependencies.customCategoryStore.refresh() }
        )
        return SettingsViewModel(
            loginViewModel: loginViewModel,
            coordinator: dependencies.sessionCoordinator,
            withdrawalCoordinator: dependencies.withdrawalCoordinator,
            dataPurgeCoordinator: dependencies.dataPurgeCoordinator
        )
    }

    static func recoverIncompleteLogout(
        repository: any LogoutDataProviding,
        customCategoryCache: any CustomCategoryCaching,
        authProvider: any AuthProviding,
        cleanupMarker: any LogoutCleanupMarking
    ) async throws {
        guard cleanupMarker.isPending else {
            return
        }
        if authProvider.currentUserID != nil {
            // sign-out 네트워크 실패가 앱 부팅을 막지 않도록 격리한다. Supabase는 로컬 세션을
            // 먼저 제거한 뒤 원격 revoke를 시도하므로 throw해도 세션은 대개 이미 무효화됐고,
            // 미완료 로그아웃 복구의 핵심(멤버 로컬 데이터 정리)은 아래 clearForLogout이 담당한다.
            // 세션이 살아남더라도 로컬이 비므로 새 신원에 이전 데이터가 섞이지 않는다.
            try? await authProvider.signOut()
        }
        // 로컬 정리 실패만 전파한다. marker를 남긴 채 부팅이 실패하면 다음 부팅에서 재시도된다(idempotent).
        try await repository.clearForLogout(force: true)
        try await customCategoryCache.clearAll()
        cleanupMarker.clear()
    }

    static func prepareIncompletePurgeRecovery(
        purgeStore: any PurgeStateStoring,
        authProvider: any AuthProviding
    ) async throws -> Bool {
        guard let pendingMemberID = try await purgeStore.purgePendingMemberID() else {
            return false
        }
        guard authProvider.currentUserID?.uuidString == pendingMemberID else {
            try await purgeStore.clearPurgeMarker()
            return false
        }
        return true
    }

    // swiftlint:disable:next function_parameter_count
    static func makeRecoveringSessionDependencies(
        repository: TransactionRepository,
        authProvider: any AuthProviding,
        connectivity: any ConnectivityObserving,
        services: AppLedgerServices,
        cleanupMarker: any LogoutCleanupMarking,
        onLogoutCleanup: @escaping @MainActor () async throws -> Void,
        onDataCleared: @escaping @MainActor () async -> Void,
        hasPendingCategoryWork: @escaping @MainActor () async -> Bool,
        onBeforeLedgerPush: @escaping @MainActor () async -> Void,
        onAfterLedgerPush: @escaping @MainActor () async -> Void,
        onAccountSwitchReset: @escaping @MainActor () async throws -> Void = {}
    ) async throws -> AppRecoveringSessionDependencies {
        let startsSyncSuspended = try await prepareIncompletePurgeRecovery(
            purgeStore: repository,
            authProvider: authProvider
        )
        let syncEngine = SyncEngine(
            repository: repository,
            ledgerService: services.sync,
            authProvider: authProvider,
            connectivity: connectivity,
            startSuspended: startsSyncSuspended,
            hasPendingCategoryWork: hasPendingCategoryWork,
            onBeforeLedgerPush: onBeforeLedgerPush,
            onAfterLedgerPush: onAfterLedgerPush,
            onAccountSwitchReset: onAccountSwitchReset
        )
        let sessionCoordinator = SessionTransitionCoordinator(
            repository: repository,
            authProvider: authProvider,
            connectivity: connectivity,
            sync: syncEngine,
            anonymousSync: syncEngine,
            cleanupMarker: cleanupMarker,
            onLogoutCleanup: onLogoutCleanup
        )
        let dataPurgeCoordinator = DataPurgeCoordinator(
            session: sessionCoordinator,
            purgeSync: syncEngine,
            purgeStore: repository,
            ledgerService: services.purge,
            authProvider: authProvider,
            connectivity: connectivity,
            onDataCleared: {
                syncEngine.publishLedgerChange()
                await onDataCleared()
            },
            maxAmbiguousRetries: services.maxPurgeRetries
        )
        Task { await dataPurgeCoordinator.resumeIfPending() }
        return AppRecoveringSessionDependencies(
            syncEngine: syncEngine,
            sessionCoordinator: sessionCoordinator,
            dataPurgeCoordinator: dataPurgeCoordinator
        )
    }
}

/// 본체 enum이 type_body_length 상한이라 extension으로 분리했다.
extension AppDependencyFactory {
    static func makeCategoryAddViewModel(
        dependencies: AppDependencies,
        tab: EntryType,
        mode: CategoryAddViewModel.Mode,
        name: String
    ) -> CategoryAddViewModel {
        CategoryAddViewModel(
            tab: tab,
            customCategoryStore: dependencies.customCategoryStore,
            mode: mode,
            name: name
        )
    }
}

private struct SeedLedgerPurgeService: LedgerPurging {
    func deleteAll(accessToken _: String) async throws {}
}

/// 시드 조립용 인메모리 커스텀 카테고리 서비스. UI 테스트가 고정 목록·오류·지연을 제어한다.
@MainActor
private final class SeedCustomCategoryService: CustomCategoryServicing {
    private var nextID: Int
    private var categories: [CatalogTransactionType: [CategoryDTO]]
    private let fetchError: Error?
    private let mutationDelay: Duration?

    init(
        seeded: [CatalogTransactionType: [CategoryDTO]] = [:],
        fetchError: Error? = nil,
        mutationDelay: Duration? = nil
    ) {
        categories = seeded
        self.fetchError = fetchError
        self.mutationDelay = mutationDelay
        nextID = max(1000, (seeded.values.flatMap { $0 }.map(\.id).max() ?? 999) + 1)
    }

    func fetchCustomCategories(transactionType: String) async throws -> [CategoryDTO] {
        guard let type = CatalogTransactionType(rawValue: transactionType) else {
            throw SeedCustomCategoryServiceError.invalidTransactionType
        }
        if let fetchError {
            throw fetchError
        }
        return categories[type] ?? []
    }

    func createCustomCategory(name: String, transactionType: String) async throws -> CategoryDTO {
        guard let type = CatalogTransactionType(rawValue: transactionType) else {
            throw SeedCustomCategoryServiceError.invalidTransactionType
        }
        await applyMutationDelay()
        let category = CategoryDTO(
            id: nextID,
            code: "CUSTOM",
            displayNameKo: name,
            displayNameEn: name,
            icon: nil,
            sortOrder: 1000
        )
        nextID += 1
        categories[type, default: []].append(category)
        return category
    }

    func updateCustomCategory(id: Int, name: String) async throws -> CategoryDTO {
        await applyMutationDelay()
        for type in CatalogTransactionType.allCases {
            guard
                var typeCategories = categories[type],
                let index = typeCategories.firstIndex(where: { $0.id == id })
            else {
                continue
            }
            let current = typeCategories[index]
            let updated = CategoryDTO(
                id: current.id,
                code: current.code,
                displayNameKo: name,
                displayNameEn: name,
                icon: current.icon,
                sortOrder: current.sortOrder
            )
            typeCategories[index] = updated
            categories[type] = typeCategories
            return updated
        }
        // 실서비스와 같은 오류를 던져야 Store의 404 수렴 경로가 시드에서도 그대로 탄다.
        throw APIError.server(code: "CATEGORY_NOT_FOUND", message: "카테고리를 찾을 수 없습니다.")
    }

    func reorderCustomCategories(orderedIDs: [Int], transactionType: String) async throws -> [CategoryDTO] {
        guard let type = CatalogTransactionType(rawValue: transactionType) else {
            throw SeedCustomCategoryServiceError.invalidTransactionType
        }
        await applyMutationDelay()
        let current = categories[type] ?? []
        let currentIDs = Set(current.map(\.id))
        guard orderedIDs.allSatisfy(currentIDs.contains) else {
            // 실서비스와 같은 오류를 던져야 Store의 404 수렴 경로가 시드에서도 그대로 탄다.
            throw APIError.server(code: "CATEGORY_NOT_FOUND", message: "카테고리를 찾을 수 없습니다.")
        }
        var reordered = current.map { category -> CategoryDTO in
            guard let index = orderedIDs.firstIndex(of: category.id) else {
                return category
            }
            return CategoryDTO(
                id: category.id,
                code: category.code,
                displayNameKo: category.displayNameKo,
                displayNameEn: category.displayNameEn,
                icon: category.icon,
                sortOrder: 1001 + index
            )
        }
        // 서버 목록 정렬(sortOrder ASC, id DESC)과 같아야 UI 테스트가 실서비스와 같은 순서를 본다.
        reordered.sort { $0.sortOrder == $1.sortOrder ? $0.id > $1.id : $0.sortOrder < $1.sortOrder }
        categories[type] = reordered
        return reordered
    }

    func deleteCustomCategory(id: Int) async throws {
        await applyMutationDelay()
        for type in CatalogTransactionType.allCases {
            categories[type]?.removeAll { $0.id == id }
        }
    }

    /// 요청 중 상태(pop 차단·isBusy)를 UI 테스트가 관측할 수 있게 하는 지연 훅.
    private func applyMutationDelay() async {
        guard let mutationDelay else {
            return
        }
        try? await Task.sleep(for: mutationDelay)
    }
}

private enum SeedCustomCategoryServiceError: Error {
    case invalidTransactionType
    case fetchFailed
}

#if DEBUG
    /// XCUITest 전용 실행 훅. `-uiTest` launch argument가 있을 때만 켜지며 릴리스 빌드에서는 컴파일되지 않는다.
    ///
    /// 실기기 DB와 Supabase 세션에 의존하면 테스트가 이전 실행의 잔재에 좌우되므로,
    /// in-memory DB + Fake 인증·연결성(`makeSeedDependencies`)으로 갈아끼워 매 실행을 격리한다.
    enum UITestSupport {
        static let enableFlag = "-uiTest"
        static let seedLedgerFlag = "-uiTestSeedLedger"
        static let clearLastUsedCurrencyFlag = "-uiTestClearLastUsedCurrency"
        static let signInAppleFlag = "-uiTestSignInApple"
        static let signInGoogleFlag = "-uiTestSignInGoogle"
        static let onlineFlag = "-uiTestOnline"
        static let customCategoriesFlag = "-uiTestCustomCategories"
        static let customCategoryFetchErrorFlag = "-uiTestCustomCategoryFetchError"
        static let customCategorySlowFlag = "-uiTestCustomCategorySlow"

        /// 시드가 넣는 값. 테스트가 기대값을 하드코딩하지 않도록 여기서 단일 정의한다.
        enum Fixture {
            static let expenseID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
            static let incomeID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
            static let otherDayID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
            static let previousMonthID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))
            static let nextMonthID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5))
            static let unconvertedID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6))
            static let convertedUSDID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7))
            static let expenseAmount: Decimal = 10000
            static let incomeAmount: Decimal = 30000
            static let otherDayAmount: Decimal = 5000
            static let unconvertedAmount: Decimal = 10
            static let convertedUSDAmount: Decimal = 10
            static let convertedUSDRate: Decimal = 1392.28
            static let convertedUSDKRWAmount: Decimal = 13922.80
            static let previousMonthAmount: Decimal = 7000
            static let nextMonthAmount: Decimal = 4000
            static let expenseMemo = "UITestExpense"
            static let incomeMemo = "UITestIncome"
            static let otherDayMemo = "UITestOtherDay"
            static let unconvertedMemo = "UITestUSD"
            static let convertedUSDMemo = "UITestConvertedUSD"
            static let previousMonthMemo = "UITestPreviousMonth"
            static let nextMonthMemo = "UITestNextMonth"
            /// 카페/음료 · 체크카드 (시드 카탈로그 ID). 미환산 거래는 오늘 거래와 다른 분류를 써 행 대조를 구분한다.
            static let unconvertedCategoryID = 2
            static let unconvertedAssetID = 2
            /// 환율 스냅샷 시작일 이전 날짜. 이 값이 스냅샷 범위 안으로 들어오면 미환산 경고 검증이 무의미해진다.
            static let unconvertedDate = "2024-06-15"
            static let convertedUSDDate = "2025-07-15"
            /// 식비 · 신용카드 · 급여 · 현금 (시드 카탈로그 ID)
            static let expenseCategoryID = 1
            static let expenseAssetID = 1
            static let incomeCategoryID = 14
            static let incomeAssetID = 3
            /// 커스텀 카테고리 fixture — 이름에 이모지가 포함되고 icon 필드는 쓰지 않는다(결정 6).
            static let customExpenseCategoryID = 1001
            static let customExpenseCategoryName = "🏋️ 헬스장"
            /// 재배치 UI 테스트는 "1행을 3칸 아래로"가 성립하려면 4행이 필요하다. id·이름을 고정해
            /// 표시 순서(sortOrder 동률 → id 내림차순)가 실행·기기마다 갈리지 않게 한다.
            static let customExpenseExtraCategories = [
                (id: 1005, name: "📚 도서"),
                (id: 1004, name: "🎬 영화"),
                (id: 1003, name: "🚕 택시")
            ]
            static let customExpenseEntryID = UUID(
                uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8)
            )
            static let customIncomeCategoryID = 1002
            static let customIncomeCategoryName = "🧧 상여금"
        }

        static var isEnabled: Bool {
            ProcessInfo.processInfo.arguments.contains(enableFlag)
        }

        static func makeDependencies() async throws -> AppDependencies {
            if ProcessInfo.processInfo.arguments.contains(clearLastUsedCurrencyFlag) {
                // 키 문자열을 복제하면 저장소 키가 바뀔 때 이 훅만 조용히 무효가 된다. 실제 저장소 동작을 재사용한다.
                await MainActor.run { LastUsedCurrencyStore().clear() }
            }
            let dependencies = try AppDependencyFactory.makeSeedDependencies(
                inMemory: true,
                customCategoryService: makeCustomCategoryService()
            )
            if ProcessInfo.processInfo.arguments.contains(customCategoriesFlag) {
                await dependencies.customCategoryStore.refresh()
            }
            if ProcessInfo.processInfo.arguments.contains(seedLedgerFlag) {
                try await seedLedger(
                    into: dependencies.transactionRepository,
                    includesCustomCategory: ProcessInfo.processInfo.arguments.contains(customCategoriesFlag)
                )
            }
            // 로그인 상태 화면(회원 전용 행·탈퇴 분기)은 이 훅 없이는 자동화할 수 없다 — 기본 조립이 항상 익명이다.
            if ProcessInfo.processInfo.arguments.contains(signInAppleFlag) {
                try await dependencies.authProvider.signIn(.apple)
            } else if ProcessInfo.processInfo.arguments.contains(signInGoogleFlag) {
                try await dependencies.authProvider.signIn(.google)
            }
            // 시드 조립은 오프라인이 기본이라 탈퇴가 오프라인 안내로 끊긴다. 확인 다이얼로그를 보려면 켜야 한다.
            if ProcessInfo.processInfo.arguments.contains(onlineFlag) {
                (dependencies.connectivity as? FakeConnectivityMonitor)?.setOnline(true)
            }
            return dependencies
        }

        /// 커스텀 카테고리 서비스 대역. 플래그로 고정 목록·오류·지연을 조립해 관리·추가 화면
        /// UI 테스트가 서버 없이 상태를 제어한다.
        private static func makeCustomCategoryService() -> SeedCustomCategoryService {
            let arguments = ProcessInfo.processInfo.arguments
            var seeded: [CatalogTransactionType: [CategoryDTO]] = [:]
            if arguments.contains(customCategoriesFlag) {
                seeded = [
                    .expense: [
                        customCategoryDTO(
                            id: Fixture.customExpenseCategoryID,
                            name: Fixture.customExpenseCategoryName
                        )
                    ] + Fixture.customExpenseExtraCategories.map {
                        customCategoryDTO(id: $0.id, name: $0.name)
                    },
                    .income: [
                        customCategoryDTO(
                            id: Fixture.customIncomeCategoryID,
                            name: Fixture.customIncomeCategoryName
                        )
                    ]
                ]
            }
            return SeedCustomCategoryService(
                seeded: seeded,
                fetchError: arguments.contains(customCategoryFetchErrorFlag)
                    ? SeedCustomCategoryServiceError.fetchFailed : nil,
                mutationDelay: arguments.contains(customCategorySlowFlag) ? .seconds(2) : nil
            )
        }

        private static func customCategoryDTO(id: Int, name: String) -> CategoryDTO {
            CategoryDTO(
                id: id,
                code: "CUSTOM",
                displayNameKo: name,
                displayNameEn: name,
                icon: nil,
                sortOrder: 1000
            )
        }

        /// 오늘·다른 날짜·인접 월에 거래를 넣어 선택 필터와 월 이동 갱신을 한 fixture로 검증한다.
        private static func seedLedger(
            into repository: TransactionRepository,
            includesCustomCategory: Bool
        ) async throws {
            for transaction in seedTransactions(includesCustomCategory: includesCustomCategory) {
                try await repository.insert(transaction)
            }
        }

        private static func seedTransactions(includesCustomCategory: Bool) -> [LocalTransaction] {
            let dates = SeedDates()
            var transactions = [
                krwEntry(Fixture.expenseID, Fixture.expenseAmount, .expense, dates.today, Fixture.expenseMemo),
                krwEntry(Fixture.incomeID, Fixture.incomeAmount, .income, dates.today, Fixture.incomeMemo),
                krwEntry(Fixture.otherDayID, Fixture.otherDayAmount, .income, dates.otherDay, Fixture.otherDayMemo),
                krwEntry(
                    Fixture.previousMonthID,
                    Fixture.previousMonthAmount,
                    .income,
                    dates.previousMonth,
                    Fixture.previousMonthMemo
                ),
                krwEntry(
                    Fixture.nextMonthID,
                    Fixture.nextMonthAmount,
                    .expense,
                    dates.nextMonth,
                    Fixture.nextMonthMemo
                ),
                // 환율 스냅샷 시작일 이전이라 환산할 수 없다. 미환산 경고 경로를 태우는 유일한 거래다.
                LocalTransaction(
                    clientEntryID: Fixture.unconvertedID,
                    amount: Fixture.unconvertedAmount,
                    currencyCode: "USD",
                    categoryID: Fixture.unconvertedCategoryID,
                    assetID: Fixture.unconvertedAssetID,
                    transactionType: .expense,
                    transactionDate: Fixture.unconvertedDate,
                    memo: Fixture.unconvertedMemo
                ),
                // 번들 시드의 2025-07-15 USD 환율과 맞춘 환산 완료 조합이다.
                LocalTransaction(
                    clientEntryID: Fixture.convertedUSDID,
                    amount: Fixture.convertedUSDAmount,
                    currencyCode: "USD",
                    categoryID: Fixture.unconvertedCategoryID,
                    assetID: Fixture.unconvertedAssetID,
                    transactionType: .expense,
                    transactionDate: Fixture.convertedUSDDate,
                    memo: Fixture.convertedUSDMemo,
                    appliedRate: Fixture.convertedUSDRate,
                    rateBaseDate: Fixture.convertedUSDDate,
                    krwAmount: Fixture.convertedUSDKRWAmount
                )
            ]
            if includesCustomCategory {
                transactions.append(LocalTransaction(
                    clientEntryID: Fixture.customExpenseEntryID,
                    amount: 12000,
                    currencyCode: "KRW",
                    categoryID: Fixture.customExpenseCategoryID,
                    categorySnapshot: Fixture.customExpenseCategoryName,
                    assetID: Fixture.expenseAssetID,
                    transactionType: .expense,
                    transactionDate: dates.today,
                    memo: "UITestCustomCategory",
                    appliedRate: 1,
                    krwAmount: 12000
                ))
            }
            return transactions
        }

        private static func krwEntry(
            _ id: UUID,
            _ amount: Decimal,
            _ type: LocalTransaction.TransactionType,
            _ date: String,
            _ memo: String
        ) -> LocalTransaction {
            let isExpense = type == .expense
            return LocalTransaction(
                clientEntryID: id,
                amount: amount,
                currencyCode: "KRW",
                categoryID: isExpense ? Fixture.expenseCategoryID : Fixture.incomeCategoryID,
                assetID: isExpense ? Fixture.expenseAssetID : Fixture.incomeAssetID,
                transactionType: type,
                transactionDate: date,
                memo: memo,
                appliedRate: 1,
                krwAmount: amount
            )
        }

        /// 시드가 쓰는 날짜 문자열. 앱과 같은 Asia/Seoul 기준으로 계산한다.
        private struct SeedDates {
            let today: String
            let otherDay: String
            let previousMonth: String
            let nextMonth: String

            init() {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
                let now = Date()
                let lastDay = (calendar.range(of: .day, in: .month, for: now) ?? 1 ..< 2).last ?? 1
                let todayDay = calendar.component(.day, from: now)

                func string(monthOffset: Int, day: Int) -> String {
                    let shifted = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
                    var components = calendar.dateComponents([.year, .month], from: shifted)
                    components.day = day
                    return ServerDateFormatter.localDate.string(from: calendar.date(from: components) ?? shifted)
                }

                today = ServerDateFormatter.localDate.string(from: now)
                // 오늘과 겹치지 않는 같은 달의 다른 날. 말일이면 하루 앞으로 물린다.
                otherDay = string(monthOffset: 0, day: todayDay == lastDay ? max(1, lastDay - 1) : lastDay)
                previousMonth = string(monthOffset: -1, day: 15)
                nextMonth = string(monthOffset: 1, day: 15)
            }
        }
    }
#endif
