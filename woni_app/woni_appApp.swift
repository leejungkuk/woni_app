//
//  woni_appApp.swift
//  woni_app
//
//  Created by J on 6/2/26.
//

import SwiftUI

@main
struct WoniApp: App {
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
            SettingsView()
        }
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

        return AppDependencies(
            transactionRepository: TransactionRepository(database: database),
            catalogProvider: catalogProvider,
            mainRateProvider: mainRateProvider,
            addExpenseRateProvider: SeedRateProviderAdapter(rateProvider: mainRateProvider)
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

        return AppDependencies(
            transactionRepository: TransactionRepository(database: database),
            catalogProvider: CatalogProvider(seedData: seedData),
            mainRateProvider: mainRateProvider,
            addExpenseRateProvider: SeedRateProviderAdapter(rateProvider: mainRateProvider)
        )
    }

    static func makeAddExpenseViewModel(inMemory: Bool = false) throws -> AddExpenseViewModel {
        try makeAddExpenseViewModel(dependencies: makeSeedDependencies(inMemory: inMemory))
    }

    static func makeAddExpenseViewModel(dependencies: AppDependencies) -> AddExpenseViewModel {
        AddExpenseViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            rateProvider: dependencies.addExpenseRateProvider
        )
    }
}
