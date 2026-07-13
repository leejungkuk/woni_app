//
//  woni_appApp.swift
//  woni_app
//
//  Created by J on 6/2/26.
//

import SwiftUI

@main
struct WoniApp: App {
    private let dependenciesResult: Result<AppDependencies, Error>
    @State private var languageStore = AppLanguageStore()

    init() {
        WoniFontFamily.register()
        dependenciesResult = Result {
            try AppDependencyFactory.makeMainDependencies()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch dependenciesResult {
                case let .success(dependencies):
                    MainRootView(dependencies: dependencies, languageStore: languageStore)
                case let .failure(error):
                    VStack(spacing: 8) {
                        Text(WoniStrings.appStartFailedTitle(languageStore.language))
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
            .environment(languageStore)
        }
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
            rateProvider: dependencies.rateProvider,
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
    let rateProvider: RateProvider
}

enum AppDependencyFactory {
    static func makeMainDependencies(inMemory: Bool = false) throws -> AppDependencies {
        let database: AppDatabase
        if inMemory {
            database = try AppDatabase.inMemory()
        } else {
            database = try AppDatabase()
        }

        let seedData = try SeedLoader().load()

        return AppDependencies(
            transactionRepository: TransactionRepository(database: database),
            catalogProvider: CatalogProvider(seedData: seedData),
            rateProvider: RateProvider(seedData: seedData)
        )
    }

    static func makeAddExpenseViewModel(inMemory: Bool = false) throws -> AddExpenseViewModel {
        try makeAddExpenseViewModel(dependencies: makeMainDependencies(inMemory: inMemory))
    }

    static func makeAddExpenseViewModel(dependencies: AppDependencies) -> AddExpenseViewModel {
        AddExpenseViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            rateProvider: dependencies.rateProvider
        )
    }
}
