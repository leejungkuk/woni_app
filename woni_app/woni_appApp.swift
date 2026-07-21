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
                        await dependencies.syncEngine.pushPending()
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
                await dependencies.syncEngine.pushPending()
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
    @State private var navigationPath: [MainRoute] = []

    init(dependencies: AppDependencies, languageStore: AppLanguageStore) {
        self.dependencies = dependencies
        self.languageStore = languageStore
        _mainViewModel = State(initialValue: MainViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            rateProvider: dependencies.mainRateProvider,
            language: languageStore.language
        ))
    }

    var body: some View {
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
        .onAppear {
            mainViewModel.applyLanguage(languageStore.language)
        }
        .onChange(of: languageStore.language) { _, newValue in
            mainViewModel.applyLanguage(newValue)
        }
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

private enum MainRoute: Hashable {
    case addExpense(Date)
    case settings
}

struct AppDependencies {
    let transactionRepository: TransactionRepository
    let catalogProvider: CatalogProvider
    let mainRateProvider: RateProvider
    let addExpenseRateProvider: any RateProviding
    let authProvider: any AuthProviding
    let connectivity: any ConnectivityObserving
    let syncEngine: SyncEngine
    let logoutCleanupMarker: any LogoutCleanupMarking
    let sessionCoordinator: SessionTransitionCoordinator
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
            addExpenseRateProvider: ServerRateProvider(seedRateProvider: mainRateProvider),
            authProvider: authProvider,
            connectivity: connectivity,
            syncEngine: syncEngine,
            logoutCleanupMarker: logoutCleanupMarker,
            sessionCoordinator: sessionCoordinator
        )
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
            coordinator: dependencies.sessionCoordinator
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
