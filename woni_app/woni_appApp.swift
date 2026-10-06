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
    /// 장면이 앞에 있는지 — 준비 끝에서 읽는다. `scenePhase` 는 `.task` 를 만들 때의 값이 남아, 준비 중에 앞으로 와도
    /// 준비 끝에서 옛 값(inactive)을 읽고 첫 활성화를 건너뛴다(2026-10-06 UI 테스트에서 확인). `@State` 는 지금 값이다.
    @State private var isSceneActive = false
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
                .onChange(of: scenePhase, initial: true) { _, phase in
                    isSceneActive = phase == .active
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
            if isSceneActive {
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var mainViewModel: MainViewModel
    @State private var monthReportViewModel: MonthReportViewModel
    @State private var budgetTabViewModel: BudgetTabViewModel
    @State private var sessionViewModel: MainRootSessionViewModel
    @State private var foregroundReloadCoordinator = ForegroundMainReloadCoordinator()
    @State private var lastUsedCurrencyStore = LastUsedCurrencyStore()
    @State private var tabNavigation = TabNavigationModel()
    @State private var overlays = RootOverlayModel()
    @State private var entryPresentation: EntryPresentation?
    @State private var budgetEditPresentation: BudgetEditPresentation?
    @State private var toastMessage: String?
    @State private var budgetToast: BudgetTabToast?

    init(
        dependencies: AppDependencies,
        languageStore: AppLanguageStore,
        baseCurrencyStore: BaseCurrencyStore
    ) {
        self.dependencies = dependencies
        self.languageStore = languageStore
        self.baseCurrencyStore = baseCurrencyStore
        let baseRateResolver = BaseRateResolver(
            cache: dependencies.exchangeRateCache,
            seedRateProvider: dependencies.mainRateProvider
        )
        let mainViewModel = MainViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            customCategoryStore: dependencies.customCategoryStore,
            rateProvider: dependencies.mainRateProvider,
            baseRateResolver: baseRateResolver,
            baseCurrency: baseCurrencyStore.baseCurrency,
            language: languageStore.language
        )
        _mainViewModel = State(initialValue: mainViewModel)
        _monthReportViewModel = State(initialValue: MonthReportViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            customCategoryStore: dependencies.customCategoryStore,
            rateProvider: dependencies.mainRateProvider,
            baseRateResolver: baseRateResolver,
            baseCurrency: baseCurrencyStore.baseCurrency,
            language: languageStore.language
        ))
        let budgetTabViewModel = AppDependencyFactory.makeBudgetTabViewModel(dependencies: dependencies)
        _budgetTabViewModel = State(initialValue: budgetTabViewModel)
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
                // 탭바는 TabView 아래에 둔다 — 겉에 건 `safeAreaInset` 은 탭 안쪽 화면에 전달되지 않아 + 버튼과
                // 스크롤 끝이 탭바 밑에 깔렸다. 아래에 두면 탭 화면(하위 화면 포함)의 아래 끝이 곧 탭바 위다.
                VStack(spacing: 0) {
                    // 탭마다 이동 스택을 따로 둔다. TabView 라서 고르지 않은 탭은 상태를 지닌 채 접근성 트리에서 빠진다.
                    TabView(selection: selectedTabBinding) {
                        tabStack(.ledger) {
                            MainView(
                                viewModel: mainViewModel,
                                language: languageStore.language,
                                onAdd: { defaultDate in
                                    entryPresentation = .create(defaultDate)
                                },
                                onSelectEntry: { clientEntryID in
                                    entryPresentation = .edit(clientEntryID)
                                },
                                overlays: overlays
                            )
                        }
                        tabStack(.report) {
                            monthReportDestination()
                        }
                        tabStack(.budget) {
                            budgetDestination()
                        }
                        tabStack(.settings) {
                            settingsDestination()
                        }
                    }
                    .woniToast($toastMessage)

                    tabBar
                }
                // 오버레이가 떠 있는 동안 뒤 화면과 탭바는 VoiceOver 로도 조작할 수 없다.
                .accessibilityHidden(overlays.presentation != nil)
                // 피커·확인 창은 탭바보다 위에 그린다. 딤과 통화 시트는 각 컴포넌트가 스스로 화면 끝까지 늘려
                // 탭바까지 덮는다. 카드는 입력 화면과 같이 안전 영역 가운데다(UI_GUIDE 피커 — 2026-10-02 사용자 결정).
                .overlay {
                    if let presentation = overlays.presentation {
                        presentation.content
                    }
                }
                .fullScreenCover(item: $entryPresentation) { presentation in
                    switch presentation {
                    case let .create(defaultDate):
                        addExpenseDestination(defaultDate: defaultDate)
                    case let .edit(clientEntryID):
                        editEntryDestination(clientEntryID: clientEntryID)
                    }
                }
                // 예산 편집도 입력 화면처럼 전체 화면 모달이고, 입력 모달을 닫는 곳에서 같이 닫는다.
                .fullScreenCover(item: $budgetEditPresentation, content: budgetEditDestination)
            }
        }
        .onAppear {
            mainViewModel.applyLanguage(languageStore.language)
        }
        .onChange(of: languageStore.language) { _, newValue in
            mainViewModel.applyLanguage(newValue)
            monthReportViewModel.applyLanguage(newValue)
        }
        .onChange(of: baseCurrencyStore.baseCurrency) { _, newValue in
            lastUsedCurrencyStore.clear()
            // 통계는 Task 에 들어가기 전에 동기로 요청한다 — 가계부를 기다린 뒤 부르면 빠르게 바꿀 때
            // 끝나는 순서에 따라 이전 통화가 마지막으로 들어간다.
            monthReportViewModel.requestBaseCurrency(newValue)
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
                    reload: {
                        _ = await mainViewModel.reload()
                        // 통계 탭은 보이지 않을 때도 살아 있으므로 함께 다시 읽는다.
                        await monthReportViewModel.reload()
                    }
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
            tabNavigation.resetAll()
            entryPresentation = nil
            budgetEditPresentation = nil
            budgetTabViewModel.cancelEdit()
            budgetToast = nil
            overlays.dismissAll()
        }
        // 계정이 바뀌는 경로(설정 로그아웃·탈퇴·로그인 계정 전환·원격 로그아웃·정리 재시도)는 모두 코디네이터를
        // 지나므로 여기 한 곳에서 받는다. 선택 탭은 두고 경로만 비운다 — 로그아웃은 설정 탭에 남는다(2026-10-02 사용자 결정).
        .onChange(of: dependencies.sessionCoordinator.identityResetGeneration) { _, _ in
            tabNavigation.clearPaths()
            startMonthReport()
            overlays.dismissAll()
            budgetToast = nil
        }
        // 예산 탭을 떠나면 탭 토스트를 비운다 — `WoniToast` 는 취소되면 메시지를 비우지 않아 돌아왔을 때 다시 뜬다.
        .onChange(of: tabNavigation.selectedTab) { oldTab, _ in
            if oldTab == .budget {
                budgetToast = nil
            }
        }
        .modifier(budgetTabEvents)
        .modifier(budgetAlertPresenting)
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
        .task {
            startMonthReport()
            let syncEngine = dependencies.syncEngine
            await monthReportViewModel.observeLedgerChanges(
                syncEngine.ledgerDidChange,
                revision: { syncEngine.ledgerRevision }
            )
        }
        .task { await observeLedgerForBudgetAlerts() }
    }

    private func monthReportDestination() -> some View {
        MonthReportView(
            viewModel: monthReportViewModel,
            onSelectCategory: { categoryID in
                // 상세는 항상 날짜 내림차순으로 연다 — 직전 상세에서 고른 정렬을 물려받지 않는다.
                monthReportViewModel.resetSort()
                // 연타 중복 push 는 `pushIfAtRoot` 가 경로 상태로만 막는다.
                tabNavigation.pushIfAtRoot(.reportCategory(categoryID: categoryID), on: .report)
            },
            overlays: overlays
        )
    }

    private func monthReportCategoryDestination(categoryID: Int) -> some View {
        CategoryDetailView(
            viewModel: monthReportViewModel,
            categoryID: categoryID,
            onSelectEntry: { clientEntryID in
                entryPresentation = .edit(clientEntryID)
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
        // 리포트 월이 홈 월과 다르면 홈 스냅샷엔 없다 — 리포트 스냅샷까지 찾아야 수정 화면이 열린다.
        let original = mainViewModel.transaction(clientEntryID: clientEntryID)
            ?? monthReportViewModel.transaction(clientEntryID: clientEntryID)
        if let original {
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
        // 로컬 수정은 원장 변경 브로드캐스트를 타지 않으므로 통계 재집계를 여기서 잇는다.
        // 통계 탭은 늘 살아 있어 보이지 않을 때도 다시 집계한다.
        Task {
            await mainViewModel.reload()
            await monthReportViewModel.reload()
        }
    }
}

/// 원격 로그아웃 알림 — 루트 본문 길이 한도(type_body_length) 때문에 따로 둔다.
private extension MainRootView {
    var remoteLogoutAlertBinding: Binding<Bool> {
        Binding(
            get: { sessionViewModel.isRemoteLogoutAlertPresented },
            set: { isPresented in
                if !isPresented {
                    sessionViewModel.acknowledgeRemoteLogoutNotice()
                }
            }
        )
    }
}

/// 탭 구조 — 루트 본문 길이 한도(type_body_length) 때문에 따로 둔다.
private extension MainRootView {
    var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    /// 시스템 탭바는 숨기고 `WoniTabBar` 를 그린다. 하위 화면에서도 탭바가 보인다(2026-10-02 사용자 결정).
    func tabStack<Root: View>(_ tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        let rootView = root()
        return NavigationStack(path: Binding(
            get: { tabNavigation.path(for: tab) },
            set: { tabNavigation.setPath($0, for: tab) }
        )) {
            rootView
                .rootEdgeSwipeBlocked()
                .navigationDestination(for: TabRoute.self) { route in
                    switch route {
                    case let .reportCategory(categoryID):
                        monthReportCategoryDestination(categoryID: categoryID)
                    case .settingsLanguage:
                        LanguageSettingsView()
                    }
                }
        }
        .toolbar(.hidden, for: .tabBar)
        .tag(tab)
    }

    var tabBar: some View {
        WoniTabBar(
            tabs: AppTab.allCases,
            selected: tabNavigation.selectedTab,
            language: languageStore.language,
            onSelect: tabNavigation.select
        )
    }

    /// 탭 토스트는 이 화면 위 하나로 띄운다 — 예산 탭에서만, 탭바 위에 보인다.
    func budgetDestination() -> some View {
        BudgetTabView(
            viewModel: budgetTabViewModel,
            overlays: overlays,
            onEdit: openBudgetEdit,
            onSetBudget: openBudgetEdit
        )
        .woniToast(budgetToastMessage, showsCheckmark: budgetToast?.showsCheckmark ?? false)
    }

    func settingsDestination() -> some View {
        SettingsView(
            viewModel: AppDependencyFactory.makeSettingsViewModel(dependencies: dependencies),
            onOpenLanguage: {
                tabNavigation.pushIfAtRoot(.settingsLanguage, on: .settings)
            },
            onClose: {
                tabNavigation.select(.ledger)
            },
            onFinish: { wasMember in
                tabNavigation.select(.ledger)
                overlays.dismissAll()
                toastMessage = wasMember
                    ? WoniStrings.withdrawCompletedToastMember(languageStore.language)
                    : WoniStrings.withdrawCompletedToastGuest(languageStore.language)
            },
            overlays: overlays
        )
    }

    var budgetTabEvents: BudgetTabEventForwarding {
        BudgetTabEventForwarding(
            viewModel: budgetTabViewModel,
            selectedTab: tabNavigation.selectedTab,
            identityResetGeneration: dependencies.sessionCoordinator.identityResetGeneration,
            syncEngine: dependencies.syncEngine,
            connectivity: dependencies.connectivity
        )
    }

    /// 통계 탭은 앱을 켤 때의 이번 달로 시작하고 그 뒤로는 가계부와 따로 움직인다(2026-10-02 사용자 결정).
    /// 이번 달은 가계부와 같은 시계로 센다.
    func startMonthReport() {
        monthReportViewModel.start(
            month: MainMonth(date: mainViewModel.currentDate, calendar: mainViewModel.calendar),
            language: languageStore.language,
            baseCurrency: baseCurrencyStore.baseCurrency,
            revision: dependencies.syncEngine.ledgerRevision
        )
    }
}

/// 예산 편집 여닫기 — 루트 본문 길이 한도(type_body_length) 때문에 따로 둔다. 열지·어느 달인지·결과를 어떻게 반영할지·어떤
/// 토스트인지는 탭 ViewModel(`editContext`·`beginEdit`·`finishEdit`)과 편집 ViewModel(`BudgetEditOutcome`)이 정하고 여기서는 넘기기만 한다.
/// 넘기는 작업은 뷰가 바뀌어도 취소되지 않게 따로 만든다(`.task` 안에서 부르지 않는다 — 예산 탭 사건 전달과 같은 까닭).
private extension MainRootView {
    /// `수정`·`예산 정하기`.
    func openBudgetEdit() {
        Task {
            switch await budgetTabViewModel.editContext() {
            case let .open(context):
                presentBudgetEdit(context)
            case .serverMonthFailed:
                budgetToast = .serverMonthFailed
            case .unavailable:
                break
            }
        }
    }

    /// 기기 기준통화를 예산 통화로 바꾸지 못하면 열지 않는다 — 다른 통화로 대신 열지 않는다. 두 목록이 같은 13종이라 닿지 않는다.
    func presentBudgetEdit(_ context: BudgetEditViewModel.Context) {
        guard let baseCurrency = CurrencyCode(rawValue: baseCurrencyStore.baseCurrency.rawValue) else {
            return
        }
        let session = budgetTabViewModel.beginEdit()
        let evaluator = dependencies.budgetAlertEvaluator
        // 쓰기 직전에 받은 예산 알림 판정기 표 — 편집 회차마다 따로다. 쓰기 전에 끝난 편집(닫기 등)은 nil 이다.
        var alertToken: BudgetAlertSaveToken?
        let viewModel = AppDependencyFactory.makeBudgetEditViewModel(
            dependencies: dependencies,
            context: context,
            baseCurrency: baseCurrency,
            beginWrite: {
                alertToken = evaluator.savedBudgetToken()
                return budgetTabViewModel.beginWrite()
            },
            onFinish: { finishBudgetEdit($0, session: session, alertToken: alertToken) }
        )
        budgetToast = nil
        budgetEditPresentation = BudgetEditPresentation(id: session, viewModel: viewModel)
    }

    func budgetEditDestination(_ presentation: BudgetEditPresentation) -> some View {
        BudgetEditView(
            viewModel: presentation.viewModel,
            categories: { AppDependencyFactory.budgetEditCategories(dependencies: dependencies) }
        )
    }

    /// 모달은 띄운 회차와 같을 때만 닫는다(`CategoryAddView.isTopmost` 와 같은 생각). 결과 반영(`applyWrite(_:token:)`·
    /// `showAfterEdit(_:)`)과 강제로 닫힌(`navigationResetGeneration`) 편집의 늦은 끝을 버리는 일은 `finishEdit` 이 한다 —
    /// 토스트는 그것이 돌려준 값만 띄운다. 저장·삭제 응답은 쓰기 직전 표와 함께 예산 알림 판정기에도 넘긴다 — 늦은 응답은
    /// 판정기가 표로 버린다(UI_GUIDE "이 기기의 예산 저장·삭제 응답도 확인으로 친다").
    func finishBudgetEdit(_ outcome: BudgetEditOutcome, session: Int, alertToken: BudgetAlertSaveToken?) {
        BudgetAlertPresentation.forward(outcome, token: alertToken, to: dependencies.budgetAlertEvaluator)
        if budgetEditPresentation?.id == session {
            budgetEditPresentation = nil
        }
        Task {
            if let toast = await budgetTabViewModel.finishEdit(outcome, session: session) {
                budgetToast = toast
            }
        }
    }

    var budgetToastMessage: Binding<String?> {
        Binding(
            get: { budgetToast?.message(languageStore.language) },
            set: { message in
                if message == nil {
                    budgetToast = nil
                }
            }
        )
    }
}

/// 예산 알림 — 루트 본문 길이 한도(type_body_length) 때문에 따로 둔다.
private extension MainRootView {
    /// push·pull 이 원장을 바꾼 뒤마다 예산 알림을 판정한다(스펙 :369). foreground 활성화 뒤 판정은
    /// `AppDependencies.handleForegroundActivation()` 이 한다.
    func observeLedgerForBudgetAlerts() async {
        let syncEngine = dependencies.syncEngine
        await dependencies.budgetAlertEvaluator.observeLedgerChanges(syncEngine.ledgerDidChange)
    }

    /// 예산 알림창을 지금 띄울 수 있는지(UI_GUIDE "예산 알림창" 띄우는 때) — 필드마다 루트 상태 하나다.
    /// 편집은 모달(`budgetEditPresentation`)이 아니라 회차로 본다 — 모달은 결과 반영보다 먼저 닫힌다.
    var budgetAlertGate: BudgetAlertGate {
        BudgetAlertGate(
            isAppActive: scenePhase == .active,
            hasRootToast: toastMessage != nil,
            hasBudgetToast: budgetToast != nil,
            isEntryOpen: entryPresentation != nil,
            isEditSessionOpen: budgetTabViewModel.isEditSessionOpen,
            hasRootOverlay: overlays.presentation != nil
        )
    }

    var budgetAlertPresenting: BudgetAlertPresenting {
        BudgetAlertPresenting(gate: budgetAlertGate, evaluator: dependencies.budgetAlertEvaluator, overlays: overlays)
    }
}

/// 예산 알림창을 언제 띄우고 닫는지만 정한다. 무엇을 할지는 `BudgetAlertPresentation` 이 정한다.
/// 기다리는 창이나 조건이 바뀔 때마다(처음 그릴 때 포함) 띄워 본다 — 창이 떠 있으면 조건의 루트 오버레이가 막고,
/// 닫힌 뒤 새 창이 기다리고 있으면 바로 띄운다.
private struct BudgetAlertPresenting: ViewModifier {
    let gate: BudgetAlertGate
    let evaluator: BudgetAlertEvaluator
    let overlays: RootOverlayModel

    func body(content: Content) -> some View {
        content
            .onChange(of: gate, initial: true) { _, gate in
                present(gate)
            }
            .onChange(of: evaluator.pendingAlert) { _, _ in
                present(gate)
            }
            // 로그아웃·계정 전환·purge 면 떠 있는 알림창을 닫는다. purge 는 신원 세대를 올리지 않아 루트의 다른 리셋으로는
            // 닫히지 않는다. 알림창만 닫는다 — 다른 오버레이는 그 화면이 닫는다.
            .onChange(of: evaluator.resetGeneration) { _, _ in
                BudgetAlertPresentation.dismissAfterReset(overlays)
            }
    }

    private func present(_ gate: BudgetAlertGate) {
        BudgetAlertPresentation.presentIfPossible(gate: gate, evaluator: evaluator, overlays: overlays)
    }
}

/// 띄운 예산 편집 하나. `id` 는 탭 ViewModel 이 준 편집 회차다.
private struct BudgetEditPresentation: Identifiable {
    let id: Int
    let viewModel: BudgetEditViewModel
}

/// 예산 탭에 사건을 넘기기만 한다. 다시 읽을지는 `BudgetTabViewModel.send(_:)` 한 곳이 정한다.
/// 사건은 받은 자리에서 동기로 넘긴다 — 따로 만든 작업은 만든 순서대로 돈다는 보장이 없다.
/// 다시 읽기는 ViewModel 이 만든 작업이라 여기서 기다리지 않는다. 기다리면 탭을 옮겨 `.task` 가
/// 취소될 때 함께 취소된 읽기가 실패로 남아 다음에 열 때 '불러올 수 없음' 이 잠깐 보인다.
private struct BudgetTabEventForwarding: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let viewModel: BudgetTabViewModel
    let selectedTab: AppTab
    let identityResetGeneration: Int
    let syncEngine: SyncEngine
    let connectivity: any ConnectivityObserving

    func body(content: Content) -> some View {
        content
            .onChange(of: selectedTab) { oldTab, newTab in
                if let event = BudgetTabViewModel.event(fromTab: oldTab, toTab: newTab) {
                    viewModel.send(event)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.send(.foreground)
                }
            }
            .onChange(of: identityResetGeneration) { _, _ in
                viewModel.send(.identityChanged)
            }
            .task {
                await viewModel.observeLedgerChanges(syncEngine.ledgerDidChange)
            }
            .task {
                await viewModel.observeConnectivity(connectivity.changes)
            }
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
    let budgetAlertEvaluator: BudgetAlertEvaluator

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
        // 활성화가 끝난 뒤 판정한다(스펙 :369). 클로저 안에 두면 판정의 서버 조회가 활성화 구간을 늘려, 그 사이 돌아온
        // 활성화가 자기 push·pull 없이 합류만 한다.
        await budgetAlertEvaluator.evaluate(.foreground)
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
    static func makeMainDependencies(
        inMemory: Bool = false
    ) async throws -> AppDependencies {
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
        // 판정기는 아직 없다 — 운영 판정기(`makeBudgetAlertEvaluator`)와 같은 `.standard` 알림 기록을 비운다.
        try await recoverIncompleteLogout(
            repository: transactionRepository,
            customCategoryCache: customCategoryCache,
            authProvider: authProvider,
            cleanupMarker: logoutCleanupMarker,
            clearBudgetAlertRecords: { BudgetAlertRecordStore().clear() }
        )
        let customCategoryStore = try CustomCategoryStore(
            service: CustomCategoryService(client: APIClient(authProvider: authProvider)),
            cache: customCategoryCache,
            authProvider: authProvider
        )
        let connectivity = ConnectivityMonitor()
        let ledgerService = LedgerService(client: APIClient(authProvider: authProvider))
        // 정리 훅이 잡으므로 훅보다 먼저 만든다. 알림 기록은 훅마다 카테고리 정리 앞에서 비운다 — 그 정리가 던지면 뒤 줄을
        // 건너뛴다(스펙 §4.3).
        let budgetAlertEvaluator = makeBudgetAlertEvaluator(authProvider: authProvider)
        let session = try await makeRecoveringSessionDependencies(
            repository: transactionRepository,
            authProvider: authProvider,
            connectivity: connectivity,
            services: AppLedgerServices(sync: ledgerService, purge: ledgerService),
            cleanupMarker: logoutCleanupMarker,
            onLogoutCleanup: {
                budgetAlertEvaluator.reset()
                try await customCategoryStore.clear()
            },
            clearBudgetAlertRecords: { budgetAlertEvaluator.clearRecords() },
            onDataCleared: {
                budgetAlertEvaluator.reset()
                try? await customCategoryStore.clear()
            },
            hasPendingCategoryWork: { customCategoryStore.hasPendingWork() },
            onBeforeLedgerPush: { await customCategoryStore.flushPending() },
            onAfterLedgerPush: { await customCategoryStore.flushPendingDeletes() },
            onAccountSwitchReset: {
                budgetAlertEvaluator.reset()
                try await customCategoryStore.resetForAccountSwitch()
            }
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
            foregroundActivationSignal: ForegroundActivationSignal(),
            budgetAlertEvaluator: budgetAlertEvaluator
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
        let catalogProvider = CatalogProvider(seedData: seedData)
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
        // 정리 훅이 잡으므로 훅보다 먼저 만든다(운영 조립과 같은 자리·순서).
        let budgetAlertEvaluator = try makeSeedBudgetAlertEvaluator(
            authProvider: authProvider,
            catalogProvider: catalogProvider
        )
        let syncEngine = SyncEngine(
            repository: transactionRepository,
            ledgerService: LedgerService(client: APIClient(authProvider: authProvider)),
            authProvider: authProvider,
            connectivity: connectivity,
            hasPendingCategoryWork: { customCategoryStore.hasPendingWork() },
            onBeforeLedgerPush: { await customCategoryStore.flushPending() },
            onAfterLedgerPush: { await customCategoryStore.flushPendingDeletes() },
            onAccountSwitchReset: {
                budgetAlertEvaluator.reset()
                try await customCategoryStore.resetForAccountSwitch()
            }
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
            onLogoutCleanup: {
                budgetAlertEvaluator.reset()
                try await customCategoryStore.clear()
            }
        )
        syncEngine.configureSessionEntry { [weak sessionCoordinator] in
            await sessionCoordinator?.ensureAnonymousIdentityIfNeeded()
        }
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
            clearBudgetAlertRecords: { budgetAlertEvaluator.clearRecords() },
            onDataCleared: {
                syncEngine.publishLedgerChange()
                budgetAlertEvaluator.reset()
                try? await customCategoryStore.clear()
            }
        )

        return AppDependencies(
            transactionRepository: transactionRepository,
            catalogProvider: catalogProvider,
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
            foregroundActivationSignal: ForegroundActivationSignal(),
            budgetAlertEvaluator: budgetAlertEvaluator
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
        cleanupMarker: any LogoutCleanupMarking,
        clearBudgetAlertRecords: @MainActor () -> Void
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
        // 정상 로그아웃 훅처럼 알림 기록을 비운다. 표식보다 먼저라 아래가 던져도 다음 부팅이 다시 비운다.
        clearBudgetAlertRecords()
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
        clearBudgetAlertRecords: @escaping @MainActor () -> Void,
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
        syncEngine.configureSessionEntry { [weak sessionCoordinator] in
            await sessionCoordinator?.ensureAnonymousIdentityIfNeeded()
        }
        let dataPurgeCoordinator = DataPurgeCoordinator(
            session: sessionCoordinator,
            purgeSync: syncEngine,
            purgeStore: repository,
            ledgerService: services.purge,
            authProvider: authProvider,
            connectivity: connectivity,
            clearBudgetAlertRecords: clearBudgetAlertRecords,
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

    /// 예산 조회는 회원 토큰을 단다 — 서버가 토큰으로 회원을 정한다(`BudgetController` `@CurrentMemberId`).
    /// 서버의 이번 달 확인은 인증 없는 공개 조회다.
    static func makeBudgetTabViewModel(dependencies: AppDependencies) -> BudgetTabViewModel {
        #if DEBUG
            if let scenario = UITestSupport.BudgetScenario.current {
                let catalog = dependencies.catalogProvider
                return makeBudgetTabViewModel(
                    dependencies: dependencies,
                    probeServerMonth: { try scenario.probe() },
                    fetch: { try scenario.fetch(year: $0, month: $1, catalog: catalog) },
                    hasIdentity: { true }
                )
            }
        #endif
        let service = BudgetService(client: APIClient(authProvider: dependencies.authProvider))
        let probe = ServerMonthProbe()
        let authProvider = dependencies.authProvider
        return makeBudgetTabViewModel(
            dependencies: dependencies,
            probeServerMonth: { try await probe.currentMonth() },
            fetch: { try await service.fetch(year: $0, month: $1) },
            hasIdentity: { authProvider.currentUserID != nil }
        )
    }

    private static func makeBudgetTabViewModel(
        dependencies: AppDependencies,
        probeServerMonth: @escaping () async throws -> ServerMonth,
        fetch: @escaping (_ year: Int, _ month: Int) async throws -> MonthlyBudget,
        hasIdentity: @escaping () -> Bool
    ) -> BudgetTabViewModel {
        let repository = dependencies.transactionRepository
        let customCategoryStore = dependencies.customCategoryStore
        return BudgetTabViewModel(
            probeServerMonth: probeServerMonth,
            fetch: fetch,
            unsyncedExpenseCount: { year, month in
                try await repository.unsyncedExpenseCount(month: LedgerMonth(year: year, month: month))
            },
            pendingDeletionCategoryIDs: { try customCategoryStore.pendingDeletionCategoryIDs() },
            hasIdentity: hasIdentity
        )
    }

    /// 예산 알림 판정기 — 예산 탭(`makeBudgetTabViewModel`)과 같은 신원·서버 시각·예산 읽기 경로다.
    static func makeBudgetAlertEvaluator(authProvider: any AuthProviding) -> BudgetAlertEvaluator {
        let service = BudgetService(client: APIClient(authProvider: authProvider))
        let probe = ServerMonthProbe()
        return BudgetAlertEvaluator(
            currentUserID: { authProvider.currentUserID },
            probeServerMonth: { try await probe.currentMonth() },
            fetch: { try await service.fetch(year: $0, month: $1) },
            records: BudgetAlertRecordStore()
        )
    }

    /// 시드 조립의 판정기. 읽는 곳은 `SeedBudgetAlertSources` 다.
    static func makeSeedBudgetAlertEvaluator(
        authProvider: any AuthProviding,
        catalogProvider: CatalogProvider
    ) throws -> BudgetAlertEvaluator {
        let sources = try SeedBudgetAlertSources(catalogProvider: catalogProvider)
        return BudgetAlertEvaluator(
            currentUserID: { authProvider.currentUserID },
            probeServerMonth: sources.probeServerMonth,
            fetch: sources.fetch,
            records: sources.records
        )
    }

    /// 예산 편집의 칩 = 내 카테고리 → 기본(입력 화면 `visibleCategories` 와 같은 순서). 부를 때마다 읽는다 — 열 때 고정하면
    /// 저장이 실패해도 이미 올라간 새 카테고리의 서버 번호를 못 따라간다.
    static func budgetEditCategories(dependencies: AppDependencies) -> [Category] {
        dependencies.customCategoryStore.categories(for: .expense)
            + dependencies.catalogProvider.categories(for: .expense)
    }

    static func makeBudgetEditViewModel(
        dependencies: AppDependencies,
        context: BudgetEditViewModel.Context,
        baseCurrency: CurrencyCode,
        beginWrite: @escaping () -> Int,
        onFinish: @escaping (BudgetEditOutcome) -> Void
    ) -> BudgetEditViewModel {
        let server = BudgetEditServer(dependencies: dependencies)
        let customCategoryStore = dependencies.customCategoryStore
        return BudgetEditViewModel(
            context: context,
            chipOrder: { budgetEditCategories(dependencies: dependencies).map(\.id) },
            baseCurrency: baseCurrency,
            fetch: server.fetch,
            save: server.save,
            delete: server.delete,
            hasIdentity: server.hasIdentity,
            ensureIdentity: server.ensureIdentity,
            flushPendingCategories: { await customCategoryStore.flushPending() },
            resolvedCategoryID: { customCategoryStore.resolvedID(for: $0) },
            refreshCategories: { await customCategoryStore.refresh() },
            beginWrite: beginWrite,
            onFinish: onFinish
        )
    }
}

/// 예산 편집이 서버·신원에 닿는 길. 조회·쓰기는 탭과 같이 회원 토큰을 단다.
/// UI 테스트(`-uiTestBudget<Scenario>`)는 탭과 같은 가짜 응답을 쓰고 신원이 있는 것으로 본다 — 맞추지 않으면 편집 저장만
/// 가짜 인증의 발급 경로를 타서 탭과 다른 신원 상태로 돈다.
private struct BudgetEditServer {
    let fetch: (_ year: Int, _ month: Int) async throws -> MonthlyBudget
    let save: (_ year: Int, _ month: Int, _ request: SaveBudgetRequest) async throws -> MonthlyBudget
    let delete: (_ year: Int, _ month: Int) async throws -> MonthlyBudget
    let hasIdentity: () -> Bool
    let ensureIdentity: () async -> Void

    init(dependencies: AppDependencies) {
        #if DEBUG
            if let scenario = UITestSupport.BudgetScenario.current {
                let catalog = dependencies.catalogProvider
                fetch = { try scenario.fetch(year: $0, month: $1, catalog: catalog) }
                save = { try scenario.save(year: $0, month: $1, request: $2, catalog: catalog) }
                delete = { scenario.delete(year: $0, month: $1) }
                hasIdentity = { true }
                ensureIdentity = {}
                return
            }
        #endif
        let service = BudgetService(client: APIClient(authProvider: dependencies.authProvider))
        let authProvider = dependencies.authProvider
        let sessionCoordinator = dependencies.sessionCoordinator
        fetch = { try await service.fetch(year: $0, month: $1) }
        save = { try await service.save(year: $0, month: $1, request: $2) }
        delete = { try await service.delete(year: $0, month: $1) }
        hasIdentity = { authProvider.currentUserID != nil }
        ensureIdentity = { await sessionCoordinator.ensureAnonymousIdentityIfNeeded() }
    }
}

private struct SeedLedgerPurgeService: LedgerPurging {
    func deleteAll(accessToken _: String) async throws {}
}

/// 시드 조립의 예산 알림 판정기가 읽는 곳 — 서버를 부르지 않는다. 진행률은 UI 테스트 시나리오의 가짜 응답으로만 읽는다 —
/// 알림창 시나리오(`-uiTestBudgetAlert<Scenario>`)가 있으면 그것을, 없으면 예산 시나리오(`-uiTestBudget<Scenario>`)를
/// 읽고, 둘 다 없으면 읽기가 던져 판정하지 않는다. UI 테스트의 알림 기록은 실행마다 비운 전용
/// suite 다 — `UserDefaults.standard` 면 앞 실행의 기록이 남는다.
private struct SeedBudgetAlertSources {
    let probeServerMonth: () async throws -> ServerMonth
    let fetch: (_ year: Int, _ month: Int) async throws -> MonthlyBudget
    let records: BudgetAlertRecordStore

    init(catalogProvider: CatalogProvider) throws {
        #if DEBUG
            if let alertScenario = UITestSupport.BudgetAlertScenario.current {
                var reads = 0
                probeServerMonth = { UITestSupport.BudgetScenario.serverMonth }
                fetch = { year, month in
                    defer { reads += 1 }
                    return try alertScenario.fetch(
                        year: year,
                        month: month,
                        readIndex: reads,
                        catalog: catalogProvider
                    )
                }
                records = try UITestSupport.makeBudgetAlertRecords()
                return
            }
            if UITestSupport.isEnabled {
                let scenario = UITestSupport.BudgetScenario.current
                probeServerMonth = {
                    guard let scenario else {
                        throw SeedBudgetAlertError.noServer
                    }
                    return try scenario.probe()
                }
                fetch = {
                    guard let scenario else {
                        throw SeedBudgetAlertError.noServer
                    }
                    return try scenario.fetch(year: $0, month: $1, catalog: catalogProvider)
                }
                records = try UITestSupport.makeBudgetAlertRecords()
                return
            }
        #endif
        probeServerMonth = { throw SeedBudgetAlertError.noServer }
        fetch = { _, _ in throw SeedBudgetAlertError.noServer }
        records = BudgetAlertRecordStore()
    }
}

private enum SeedBudgetAlertError: Error {
    case noServer
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
        /// 확인 창 누름 막기(`ConfirmDialogTapGuard`)를 3초로 늘린다 — 막는 동안의 누름을 UI 테스트가 결정적으로 누르게.
        static let longTapGuardFlag = "-uiTestLongTapGuard"

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
                try await dependencies.authProvider.ensureIdentity()
                await dependencies.customCategoryStore.refresh()
            }
            // 예산 알림 판정기는 신원이 없으면 서버를 읽지 않는다 — 알림창 UI 테스트는 신원이 있어야 창이 뜬다.
            if BudgetAlertScenario.current != nil {
                try await dependencies.authProvider.ensureIdentity()
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

    /// 예산 탭 UI 테스트 훅. `-uiTestBudget<Scenario>` 가 있으면 서버 대신 고정 응답을 주고 신원이 있는 것으로 본다.
    /// 서버의 이번 달은 2026-10 으로 고정한다 — 실행 날짜와 상관없이 `‹ ›`·피커 범위가 2000-01 ~ 2027-10 이다.
    extension UITestSupport {
        enum BudgetScenario: String, CaseIterable {
            /// 총액 + 카테고리 2개(식비는 넘침) + 결제수단은 신용카드만 몫.
            case setMonth = "-uiTestBudgetSet"
            case notSet = "-uiTestBudgetNotSet"
            case fetchError = "-uiTestBudgetFetchError"
            case probeError = "-uiTestBudgetProbeError"
            /// `setMonth` + 몫 있는 삭제된 카테고리 줄 셋(응답 순서 ①②③): ① 카탈로그에 없음·쓴 돈 있음 ② 카탈로그에 없음·
            /// 쓴 돈 0 ③ 카탈로그에 있음(이 기기에 삭제가 아직 안 도착)·쓴 돈 있음. 저장·삭제는 `setMonth` 와 같다.
            case deletedCategories = "-uiTestBudgetDeletedCategories"

            static let serverMonth = ServerMonth(year: 2026, month: 10)
            /// 시나리오와 함께 주면 저장이 실패한다.
            static let saveErrorFlag = "-uiTestBudgetSaveError"
            /// 이 실행에서 마지막으로 저장한 전체. 예산 알림창의 저장 연결 갈래(`BudgetAlertScenario.afterSave`)가 읽는다.
            private(set) static var lastSavedTotal: Decimal?

            static var current: Self? {
                guard isEnabled else {
                    return nil
                }
                return allCases.first { ProcessInfo.processInfo.arguments.contains($0.rawValue) }
            }

            func probe() throws -> ServerMonth {
                guard self != .probeError else {
                    throw BudgetScenarioError.probeFailed
                }
                return Self.serverMonth
            }

            func fetch(year: Int, month: Int, catalog: CatalogProvider) throws -> MonthlyBudget {
                switch self {
                case .setMonth:
                    Self.setBudget(year: year, month: month, catalog: catalog)
                case .deletedCategories:
                    Self.setBudget(
                        year: year,
                        month: month,
                        catalog: catalog,
                        deletedCategories: Self.deletedCategoryLines(catalog: catalog)
                    )
                case .notSet:
                    Self.notSetBudget(year: year, month: month)
                case .fetchError, .probeError:
                    throw BudgetScenarioError.fetchFailed
                }
            }

            /// `setMonth` 응답에서 통화·전체 예산만 요청 값으로 바꾼다 — 탭의 계약 검사(`isWellFormed`)를 지나야 저장 뒤
            /// 총액 카드가 뜬다.
            func save(
                year: Int,
                month: Int,
                request: SaveBudgetRequest,
                catalog: CatalogProvider
            ) throws -> MonthlyBudget {
                guard !ProcessInfo.processInfo.arguments.contains(Self.saveErrorFlag) else {
                    throw BudgetWriteError.other(BudgetScenarioError.saveFailed)
                }
                Self.lastSavedTotal = request.totalAmount
                return Self.setBudget(
                    year: year,
                    month: month,
                    catalog: catalog,
                    currency: request.currency,
                    totalBudget: request.totalAmount
                )
            }

            /// 그 달을 미설정으로 만든다.
            func delete(year: Int, month: Int) -> MonthlyBudget {
                Self.notSetBudget(year: year, month: month)
            }

            /// 계약대로 남은 일수·하루 권장은 이번 달에만 있다. 삭제된 줄은 보통 줄 뒤에 붙인다. 전체 줄의 쓴 돈만 `spent` 다 —
            /// 예산 알림창 시나리오가 판정기 응답을 만들 때 바꾼다.
            static func setBudget(
                year: Int,
                month: Int,
                catalog: CatalogProvider,
                currency: CurrencyCode = .krw,
                totalBudget: Decimal = 500_000,
                spent: Decimal = 300_000,
                deletedCategories: [BudgetCategoryLine] = []
            ) -> MonthlyBudget {
                let remainingDays = ServerMonth(year: year, month: month) == serverMonth ? 7 : nil
                let total = totalLine(budget: totalBudget, spent: spent)
                let categories = Array(catalog.categories(for: .expense).prefix(2))
                let categoryLines = zip(categories, [
                    line(budget: 200_000, spent: 230_000, status: .exceeded, percent: 115),
                    line(budget: 100_000, spent: 40000, status: .inProgress, percent: 40)
                ]).map { BudgetCategoryLine(category: $0, isDeleted: false, line: $1) }
                return MonthlyBudget(
                    year: year,
                    month: month,
                    currentYear: serverMonth.year,
                    currentMonth: serverMonth.month,
                    remainingDaysIncludingToday: remainingDays,
                    hasAnyBudget: true,
                    status: .inProgress,
                    currency: currency,
                    total: total,
                    paymentGroups: [
                        BudgetPaymentGroupLine(
                            paymentGroup: .creditCard,
                            line: line(budget: 300_000, spent: 250_000, status: .nearLimit, percent: 83)
                        ),
                        BudgetPaymentGroupLine(paymentGroup: .cashAndDebit, line: line(spent: 50000)),
                        BudgetPaymentGroupLine(paymentGroup: .accountAndOther, line: line(spent: 0))
                    ],
                    categories: categoryLines + deletedCategories,
                    otherCategories: otherCategoriesLine(excluding: deletedCategories),
                    missingRateCount: 0,
                    dailyAllowance: remainingDays.map { dailyAllowance(for: total, days: $0) },
                    deletedCategoriesWithSpending: []
                )
            }

            /// 하루 권장액 = 남은 돈 ÷ 남은 날(내림). 넘었으면 금액 없이 넘음이다 — 전체 500,000 · 쓴 돈 300,000 · 7일이면 28,571.
            private static func dailyAllowance(for total: BudgetLine, days: Int) -> DailyAllowance {
                guard var share = total.remainingAmount.map({ $0 / Decimal(days) }) else {
                    return DailyAllowance(amount: nil, isExceeded: true)
                }
                var amount = Decimal()
                NSDecimalRound(&amount, &share, 0, .down)
                return DailyAllowance(amount: amount, isExceeded: false)
            }

            /// 삭제된 줄 ①②③. ①② 는 카탈로그에 없는 번호, ③ 은 카탈로그 셋째 카테고리다 — 앞의 둘은 `setBudget` 의 보통 줄이다.
            private static func deletedCategoryLines(catalog: CatalogProvider) -> [BudgetCategoryLine] {
                let removed = [901, 902].map {
                    Category(
                        id: $0,
                        code: "REMOVED_\($0)",
                        displayNameKo: "지운 카테고리 \($0)",
                        displayNameEn: "Removed \($0)",
                        icon: nil,
                        sortOrder: $0
                    )
                }
                let categories = removed + catalog.categories(for: .expense).dropFirst(2).prefix(1)
                return zip(categories, [
                    line(budget: 30000, spent: 12000, status: .inProgress, percent: 40),
                    line(budget: 20000, spent: 0, status: BudgetStatus.none, percent: 0),
                    line(budget: 50000, spent: 8000, status: .inProgress, percent: 16)
                ]).map { BudgetCategoryLine(category: $0, isDeleted: true, line: $1) }
            }

            /// 그 외 카테고리 = 삭제된 줄이 없을 때의 몫 200,000 · 쓴 돈 30,000 에서 삭제된 줄의 몫·쓴 돈을 뺀 것 — 전체 예산
            /// 500,000 · 쓴 돈 300,000 과 줄 합이 맞는다.
            private static func otherCategoriesLine(excluding deleted: [BudgetCategoryLine]) -> BudgetLine {
                let budget = 200_000 - deleted.compactMap(\.line.budgetAmount).reduce(0, +)
                let spent = 30000 - deleted.map(\.line.actualAmount).reduce(0, +)
                return line(
                    budget: budget,
                    spent: spent,
                    status: .inProgress,
                    percent: NSDecimalNumber(decimal: spent * 100 / budget).intValue
                )
            }

            private static func notSetBudget(year: Int, month: Int) -> MonthlyBudget {
                MonthlyBudget(
                    year: year,
                    month: month,
                    currentYear: serverMonth.year,
                    currentMonth: serverMonth.month,
                    remainingDaysIncludingToday: ServerMonth(year: year, month: month) == serverMonth ? 7 : nil,
                    hasAnyBudget: false,
                    status: .notSet,
                    currency: nil,
                    total: nil,
                    paymentGroups: [],
                    categories: [],
                    otherCategories: nil,
                    missingRateCount: 0,
                    dailyAllowance: nil,
                    deletedCategoriesWithSpending: []
                )
            }

            /// 상태·퍼센트(내림)를 전체 예산과 쓴 돈에 맞춘다 — 넘었는데 진행 중이거나 진행 중인데 퍼센트가 없으면 탭이 계약
            /// 위반으로 버린다. 80% 부터는 서버처럼 임박이다. 쓴 돈 300,000 · 500,000 이면 진행 중 60% 다.
            private static func totalLine(budget: Decimal, spent: Decimal) -> BudgetLine {
                guard spent < budget else {
                    let status: BudgetStatus = spent == budget ? .reached : .exceeded
                    return line(budget: budget, spent: spent, status: status)
                }
                let percent = NSDecimalNumber(decimal: spent * 100 / budget).intValue
                return line(
                    budget: budget,
                    spent: spent,
                    status: percent >= 80 ? .nearLimit : .inProgress,
                    percent: percent
                )
            }

            /// 몫이 있으면 남은 돈 또는 넘은 돈을 서버처럼 채운다. 몫이 없으면 쓴 돈만 있다.
            private static func line(
                budget: Decimal? = nil,
                spent: Decimal,
                status: BudgetStatus? = nil,
                percent: Int? = nil
            ) -> BudgetLine {
                BudgetLine(
                    budgetAmount: budget,
                    actualAmount: spent,
                    status: status,
                    percent: percent,
                    remainingAmount: budget.flatMap { spent > $0 ? nil : $0 - spent },
                    overAmount: budget.flatMap { spent > $0 ? spent - $0 : nil }
                )
            }
        }

        private enum BudgetScenarioError: Error {
            case probeFailed, fetchFailed, saveFailed
        }
    }

    /// 예산 알림창 UI 테스트 훅. `-uiTestBudgetAlert<Scenario>` 가 있으면 신원을 만들고 판정기만 이 응답을 읽는다 — 예산 탭·
    /// 편집은 예산 시나리오(`-uiTestBudget<Scenario>`) 그대로다. 서버의 이번 달은 예산 시나리오와 같은 2026-10 이다.
    /// 알림 기록은 실행마다 비우므로 첫 판정은 늘 처음 확인이라 창이 없다 — 창을 보려면 첫 읽기가 기준 아래여야 한다.
    extension UITestSupport {
        enum BudgetAlertScenario: String, CaseIterable {
            /// 첫 읽기는 전체 500,000 · 쓴 돈 300,000(진행 중 60%), 그 뒤는 쓴 돈 410,000(임박 82% — 남은 돈·하루 권장액).
            case nearLimit = "-uiTestBudgetAlertNearLimit"
            /// 그 뒤는 쓴 돈 530,000(넘음 — 넘은 돈 30,000).
            case exceeded = "-uiTestBudgetAlertExceeded"
            /// 그 뒤는 쓴 돈 500,000(딱 100% — 넘은 돈 없음).
            case reached = "-uiTestBudgetAlertReached"
            /// 저장 연결 — 예산 시나리오와 함께 쓴다. 이 기기에서 저장하기 전은 예산 시나리오 응답 그대로이고, 저장한 뒤는
            /// 마지막으로 저장한 전체에 쓴 돈 340,000 이다(400,000 이면 85% 임박). 저장 응답은 예산 시나리오 그대로다.
            case afterSave = "-uiTestBudgetAlertAfterSave"

            static var current: Self? {
                guard isEnabled else {
                    return nil
                }
                return allCases.first { ProcessInfo.processInfo.arguments.contains($0.rawValue) }
            }

            /// 판정기의 `readIndex` 번째(0부터) 읽기 응답.
            func fetch(year: Int, month: Int, readIndex: Int, catalog: CatalogProvider) throws -> MonthlyBudget {
                switch self {
                case .nearLimit, .exceeded, .reached:
                    guard readIndex > 0 else {
                        return BudgetScenario.setBudget(year: year, month: month, catalog: catalog)
                    }
                    let spent: Decimal = switch self {
                    case .nearLimit: 410_000
                    case .exceeded: 530_000
                    default: 500_000
                    }
                    return BudgetScenario.setBudget(year: year, month: month, catalog: catalog, spent: spent)
                case .afterSave:
                    guard let saved = BudgetScenario.lastSavedTotal else {
                        guard let scenario = BudgetScenario.current else {
                            throw BudgetAlertScenarioError.noBudgetScenario
                        }
                        return try scenario.fetch(year: year, month: month, catalog: catalog)
                    }
                    return BudgetScenario.setBudget(
                        year: year,
                        month: month,
                        catalog: catalog,
                        totalBudget: saved,
                        spent: 340_000
                    )
                }
            }
        }

        private enum BudgetAlertScenarioError: Error {
            case noBudgetScenario
        }
    }

    /// 예산 알림 UI 테스트 훅. `UserDefaults.standard` 를 쓰지 않는다 — 앞 테스트의 알림 기록이 다음 테스트로 새어 결과가 실행
    /// 순서에 따라 바뀐다.
    extension UITestSupport {
        private static let budgetAlertRecordSuiteName = "woni_app.uiTest.budgetAlertRecords"

        /// 예산 알림 알림 기록. 저장소를 만들기 전에 전용 suite 를 비운다 — 앞 실행의 기록이 남지 않게.
        static func makeBudgetAlertRecords() throws -> BudgetAlertRecordStore {
            guard let defaults = UserDefaults(suiteName: budgetAlertRecordSuiteName) else {
                throw NotificationTestError.suiteUnavailable
            }
            defaults.removePersistentDomain(forName: budgetAlertRecordSuiteName)
            return BudgetAlertRecordStore(userDefaults: defaults)
        }

        private enum NotificationTestError: Error {
            case suiteUnavailable
        }
    }
#endif
