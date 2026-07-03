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

    init() {
        WoniFont.registerFonts()
        dependenciesResult = Result {
            try AppDependencyFactory.makeMainDependencies()
        }
    }

    var body: some Scene {
        WindowGroup {
            switch dependenciesResult {
            case let .success(dependencies):
                MainRootView(dependencies: dependencies)
            case let .failure(error):
                VStack(spacing: 8) {
                    Text("앱을 시작할 수 없습니다.")
                        .font(.woni(.body1))
                        .foregroundColor(Color.Woni.gray100)
                    Text(error.localizedDescription)
                        .font(.woni(.body3))
                        .foregroundColor(Color.Woni.gray80)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.Woni.base10)
            }
        }
    }
}

private struct MainRootView: View {
    let dependencies: AppDependencies
    @State private var mainViewModel: MainViewModel
    @State private var isAddExpensePresented = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _mainViewModel = State(initialValue: MainViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            rateProvider: dependencies.rateProvider
        ))
    }

    var body: some View {
        MainView(
            viewModel: mainViewModel,
            onAdd: {
                isAddExpensePresented = true
            }
        )
        .sheet(
            isPresented: $isAddExpensePresented,
            onDismiss: {
                Task {
                    await mainViewModel.reload()
                }
            },
            content: {
                AddExpenseView(
                    viewModel: AppDependencyFactory.makeAddExpenseViewModel(dependencies: dependencies),
                    onClose: {
                        isAddExpensePresented = false
                    }
                )
            }
        )
    }
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
