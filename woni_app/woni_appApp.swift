//
//  woni_appApp.swift
//  woni_app
//
//  Created by J on 6/2/26.
//

import OSLog
import SwiftUI

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
                            navigationPath.append(.addExpense(defaultDate))
                        },
                        onSelectEntry: { clientEntryID in
                            navigationPath.append(.editEntry(clientEntryID))
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
        case let .editEntry(clientEntryID):
            editEntryDestination(clientEntryID: clientEntryID)
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
        let viewModel = AppDependencyFactory.makeAddExpenseViewModel(
            dependencies: dependencies,
            baseCurrency: baseCurrencyStore.baseCurrency,
            lastUsedCurrencyStore: lastUsedCurrencyStore
        )
        viewModel.date = defaultDate
        return AddEntryView(
            viewModel: viewModel,
            onClose: {
                dismissCurrentRoute()
            },
            onSaved: {
                finishCurrentRouteAndReload()
            }
        )
        .toolbar(.hidden, for: .navigationBar)
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
                onClose: {
                    dismissCurrentRoute()
                },
                onSaved: {
                    finishCurrentRouteAndReload()
                }
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

    private func finishCurrentRouteAndReload() {
        dismissCurrentRoute()
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
    case addExpense(Date)
    case editEntry(UUID)
    case settings
}

struct AppDependencies {
    nonisolated static let logger = Logger(subsystem: "woni_app", category: "Foreground")

    let transactionRepository: TransactionRepository
    let catalogProvider: CatalogProvider
    let mainRateProvider: RateProvider
    let addExpenseRateProvider: any RateProviding
    let exchangeRateCache: any ExchangeRateCaching
    let prefetchRates: @Sendable () async -> Void
    let authProvider: any AuthProviding
    let connectivity: any ConnectivityObserving
    let syncEngine: SyncEngine
    let logoutCleanupMarker: any LogoutCleanupMarking
    let sessionCoordinator: SessionTransitionCoordinator
    let foregroundActivationRunner: ForegroundActivationRunner
    let foregroundActivationSignal: ForegroundActivationSignal

    func handleForegroundActivation() async {
        await foregroundActivationRunner.run {
            await Self.handleForegroundActivation(
                sync: syncEngine,
                coordinator: sessionCoordinator,
                prefetchRates: prefetchRates,
                signal: foregroundActivationSignal
            )
        }
    }

    static func handleForegroundActivation(
        sync: any ForegroundSyncing,
        coordinator: SessionTransitionCoordinator,
        prefetchRates: @Sendable () async -> Void,
        signal: ForegroundActivationSignal
    ) async {
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
        await prefetchRates()
        signal.bump()
    }
}

struct AppExchangeRateDependencies {
    let rateProvider: any RateProviding
    let cache: any ExchangeRateCaching
    let prefetchRates: @Sendable () async -> Void
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
            exchangeRateCache: exchangeRate.cache,
            prefetchRates: exchangeRate.prefetchRates,
            authProvider: authProvider,
            connectivity: connectivity,
            syncEngine: syncEngine,
            logoutCleanupMarker: logoutCleanupMarker,
            sessionCoordinator: sessionCoordinator,
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
        let exchangeRateCache = ExchangeRateCacheRepository(database: database)
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
            exchangeRateCache: exchangeRateCache,
            prefetchRates: {},
            authProvider: authProvider,
            connectivity: connectivity,
            syncEngine: syncEngine,
            logoutCleanupMarker: logoutCleanupMarker,
            sessionCoordinator: sessionCoordinator,
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
            addExpenseRateProvider: dependencies.addExpenseRateProvider,
            baseCurrency: baseCurrency,
            lastUsedCurrencyStore: lastUsedCurrencyStore,
            syncTrigger: dependencies.syncEngine,
            mode: mode
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

#if DEBUG
    /// XCUITest 전용 실행 훅. `-uiTest` launch argument가 있을 때만 켜지며 릴리스 빌드에서는 컴파일되지 않는다.
    ///
    /// 실기기 DB와 Supabase 세션에 의존하면 테스트가 이전 실행의 잔재에 좌우되므로,
    /// in-memory DB + Fake 인증·연결성(`makeSeedDependencies`)으로 갈아끼워 매 실행을 격리한다.
    enum UITestSupport {
        static let enableFlag = "-uiTest"
        static let seedLedgerFlag = "-uiTestSeedLedger"

        /// 시드가 넣는 값. 테스트가 기대값을 하드코딩하지 않도록 여기서 단일 정의한다.
        enum Fixture {
            static let expenseID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
            static let incomeID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
            static let otherDayID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
            static let previousMonthID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))
            static let nextMonthID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5))
            static let unconvertedID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6))
            static let expenseAmount: Decimal = 10000
            static let incomeAmount: Decimal = 30000
            static let otherDayAmount: Decimal = 5000
            static let unconvertedAmount: Decimal = 10
            static let previousMonthAmount: Decimal = 7000
            static let nextMonthAmount: Decimal = 4000
            static let expenseMemo = "UITestExpense"
            static let incomeMemo = "UITestIncome"
            static let otherDayMemo = "UITestOtherDay"
            static let unconvertedMemo = "UITestUSD"
            static let previousMonthMemo = "UITestPreviousMonth"
            static let nextMonthMemo = "UITestNextMonth"
            /// 카페/음료 · 체크카드 (시드 카탈로그 ID). 미환산 거래는 오늘 거래와 다른 분류를 써 행 대조를 구분한다.
            static let unconvertedCategoryID = 2
            static let unconvertedAssetID = 2
            /// 환율 스냅샷 시작일 이전 날짜. 이 값이 스냅샷 범위 안으로 들어오면 미환산 경고 검증이 무의미해진다.
            static let unconvertedDate = "2024-06-15"
            /// 식비 · 신용카드 · 급여 · 현금 (시드 카탈로그 ID)
            static let expenseCategoryID = 1
            static let expenseAssetID = 1
            static let incomeCategoryID = 14
            static let incomeAssetID = 3
        }

        static var isEnabled: Bool {
            ProcessInfo.processInfo.arguments.contains(enableFlag)
        }

        static func makeDependencies() async throws -> AppDependencies {
            let dependencies = try AppDependencyFactory.makeSeedDependencies(inMemory: true)
            if ProcessInfo.processInfo.arguments.contains(seedLedgerFlag) {
                try await seedLedger(into: dependencies.transactionRepository)
            }
            return dependencies
        }

        /// 오늘·다른 날짜·인접 월에 거래를 넣어 선택 필터와 월 이동 갱신을 한 fixture로 검증한다.
        private static func seedLedger(into repository: TransactionRepository) async throws {
            for transaction in seedTransactions() {
                try await repository.insert(transaction)
            }
        }

        private static func seedTransactions() -> [LocalTransaction] {
            let dates = SeedDates()
            return [
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
                )
            ]
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
