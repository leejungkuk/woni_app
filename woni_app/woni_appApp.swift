//
//  woni_appApp.swift
//  woni_app
//
//  Created by J on 6/2/26.
//

import SwiftUI

@main
struct WoniApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var startupState: AppStartupState = .loading
    @State private var didStartDependencyLoad = false
    @State private var languageStore = AppLanguageStore()

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
        }
    }

    @ViewBuilder
    private var appContent: some View {
        switch startupState {
        case .loading:
            AppLoadingView()
        case let .loaded(dependencies):
            MainRootView(dependencies: dependencies, languageStore: languageStore)
        case let .failed(error):
            AppStartupFailureView(error: error, language: languageStore.language)
        }
    }

    @MainActor
    private func loadDependenciesIfNeeded() async {
        guard !didStartDependencyLoad else {
            return
        }

        didStartDependencyLoad = true
        startupState = .loading

        do {
            let dependencies = try await AppDependencyFactory.makeMainDependencies()
            startupState = .loaded(dependencies)
            if scenePhase == .active {
                await dependencies.handleForegroundActivation()
            }
        } catch {
            startupState = .failed(error)
        }
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

private struct MainRootView: View {
    let dependencies: AppDependencies
    let languageStore: AppLanguageStore
    @State private var mainViewModel: MainViewModel
    @State private var sessionViewModel: MainRootSessionViewModel
    @State private var navigationPath: [MainRoute] = []

    init(dependencies: AppDependencies, languageStore: AppLanguageStore) {
        self.dependencies = dependencies
        self.languageStore = languageStore
        let mainViewModel = MainViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            rateProvider: dependencies.mainRateProvider,
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
                            navigationPath.append(.addExpense(defaultDate))
                        },
                        onOpenSettings: {
                            navigationPath.append(.settings)
                        }
                    )
                    .navigationDestination(for: MainRoute.self) { route in
                        destination(for: route)
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

    @ViewBuilder
    private func destination(for route: MainRoute) -> some View {
        switch route {
        case let .addExpense(defaultDate):
            addExpenseDestination(defaultDate: defaultDate)
        case .settings:
            settingsDestination()
        }
    }

    private func settingsDestination() -> some View {
        SettingsView(viewModel: AppDependencyFactory.makeSettingsViewModel(
            dependencies: dependencies
        ))
    }

    private func addExpenseDestination(defaultDate: Date) -> some View {
        let viewModel = AppDependencyFactory.makeAddExpenseViewModel(dependencies: dependencies)
        viewModel.date = defaultDate
        return AddEntryView(
            viewModel: viewModel,
            onClose: {
                dismissCurrentRoute()
            },
            onSaved: {
                dismissCurrentRoute()
                Task {
                    await mainViewModel.reload()
                }
            }
        )
        .toolbar(.hidden, for: .navigationBar)
    }

    private func dismissCurrentRoute() {
        guard !navigationPath.isEmpty else {
            return
        }

        navigationPath.removeLast()
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

private enum MainRoute: Hashable {
    case addExpense(Date)
    case settings
}

struct AppDependencies {
    let transactionRepository: TransactionRepository
    let catalogProvider: CatalogProvider
    let mainRateProvider: RateProvider
    let addExpenseRateProvider: any RateProviding
    let prefetchRates: @Sendable () async -> Void
    let authProvider: any AuthProviding
    let connectivity: any ConnectivityObserving
    let syncEngine: SyncEngine
    let logoutCleanupMarker: any LogoutCleanupMarking
    let sessionCoordinator: SessionTransitionCoordinator

    func handleForegroundActivation() async {
        await Self.handleForegroundActivation(
            sync: syncEngine,
            coordinator: sessionCoordinator,
            prefetchRates: prefetchRates
        )
    }

    static func handleForegroundActivation(
        sync: any LoginSyncing,
        coordinator: SessionTransitionCoordinator,
        prefetchRates: @Sendable () async -> Void
    ) async {
        await sync.pushPending()
        await coordinator.runForegroundSessionProbe()
        await prefetchRates()
    }
}

enum AppDependencyFactory {
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
        let exchangeRate = makeExchangeRateDependencies(
            database: database,
            seedRateProvider: mainRateProvider
        )
        let authProvider = try SupabaseAuthService()
        let logoutCleanupMarker = LogoutCleanupMarker()
        try await recoverIncompleteLogout(
            repository: transactionRepository,
            authProvider: authProvider,
            cleanupMarker: logoutCleanupMarker
        )
        let connectivity = ConnectivityMonitor()
        let syncEngine = SyncEngine(
            repository: transactionRepository,
            ledgerService: LedgerService(client: APIClient(authProvider: authProvider)),
            authProvider: authProvider,
            connectivity: connectivity
        )
        let sessionCoordinator = SessionTransitionCoordinator(
            repository: transactionRepository,
            authProvider: authProvider,
            connectivity: connectivity,
            sync: syncEngine,
            cleanupMarker: logoutCleanupMarker
        )

        return AppDependencies(
            transactionRepository: transactionRepository,
            catalogProvider: catalogProvider,
            mainRateProvider: mainRateProvider,
            addExpenseRateProvider: exchangeRate.rateProvider,
            prefetchRates: exchangeRate.prefetchRates,
            authProvider: authProvider,
            connectivity: connectivity,
            syncEngine: syncEngine,
            logoutCleanupMarker: logoutCleanupMarker,
            sessionCoordinator: sessionCoordinator
        )
    }

    /// 캐시 저장소 단일 인스턴스를 prefetcher와 provider 양쪽에 주입한다 — 한쪽이라도 누락되면
    /// 폴백 체인이 조용히 비활성화되므로, composition 테스트가 이 함수를 직접 호출해 검증한다.
    static func makeExchangeRateDependencies(
        database: AppDatabase,
        seedRateProvider: RateProvider,
        service: ExchangeRateService = ExchangeRateService(),
        now: @escaping @Sendable () -> Date = Date.init
    ) -> (rateProvider: any RateProviding, prefetchRates: @Sendable () async -> Void) {
        let cacheRepository = ExchangeRateCacheRepository(database: database)
        let prefetcher = ExchangeRatePrefetcher(
            service: service,
            cache: cacheRepository,
            now: now
        )
        let rateProvider = ServerRateProvider(
            service: service,
            seedRateProvider: seedRateProvider,
            cache: cacheRepository
        )
        return (rateProvider, { await prefetcher.prefetchToday() })
    }

    static func makeSeedDependencies(inMemory: Bool = false) throws -> AppDependencies {
        let database: AppDatabase
        if inMemory {
            database = try AppDatabase.inMemory()
        } else {
            database = try AppDatabase()
        }

        let seedData = try SeedLoader().load()
        let mainRateProvider = RateProvider(seedData: seedData)
        let transactionRepository = TransactionRepository(database: database)
        let authProvider = FakeAuthService()
        let connectivity = FakeConnectivityMonitor()
        let logoutCleanupMarker = InMemoryLogoutCleanupMarker()
        let syncEngine = SyncEngine(
            repository: transactionRepository,
            ledgerService: LedgerService(client: APIClient(authProvider: authProvider)),
            authProvider: authProvider,
            connectivity: connectivity
        )
        let sessionCoordinator = SessionTransitionCoordinator(
            repository: transactionRepository,
            authProvider: authProvider,
            connectivity: connectivity,
            sync: syncEngine,
            cleanupMarker: logoutCleanupMarker
        )

        return AppDependencies(
            transactionRepository: transactionRepository,
            catalogProvider: CatalogProvider(seedData: seedData),
            mainRateProvider: mainRateProvider,
            addExpenseRateProvider: SeedRateProviderAdapter(rateProvider: mainRateProvider),
            prefetchRates: {},
            authProvider: authProvider,
            connectivity: connectivity,
            syncEngine: syncEngine,
            logoutCleanupMarker: logoutCleanupMarker,
            sessionCoordinator: sessionCoordinator
        )
    }

    static func makeAddExpenseViewModel(inMemory: Bool = false) throws -> AddExpenseViewModel {
        try makeAddExpenseViewModel(dependencies: makeSeedDependencies(inMemory: inMemory))
    }

    static func makeAddExpenseViewModel(dependencies: AppDependencies) -> AddExpenseViewModel {
        AddExpenseViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            addExpenseRateProvider: dependencies.addExpenseRateProvider,
            syncTrigger: dependencies.syncEngine
        )
    }

    static func makeSettingsViewModel(dependencies: AppDependencies) -> SettingsViewModel {
        let loginViewModel = LoginViewModel(
            authProvider: dependencies.authProvider,
            sync: dependencies.syncEngine,
            coordinator: dependencies.sessionCoordinator,
            connectivity: dependencies.connectivity
        )
        return SettingsViewModel(
            loginViewModel: loginViewModel,
            coordinator: dependencies.sessionCoordinator
        )
    }

    static func recoverIncompleteLogout(
        repository: any LogoutDataProviding,
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
        cleanupMarker.clear()
    }
}
