//
//  woni_appApp.swift
//  woni_app
//
//  Created by J on 6/2/26.
//

import SwiftUI

@main
struct WoniApp: App {
    private let addExpenseViewModelResult: Result<AddExpenseViewModel, Error>

    init() {
        WoniFont.registerFonts()
        addExpenseViewModelResult = Result {
            try AppDependencyFactory.makeAddExpenseViewModel()
        }
    }

    var body: some Scene {
        WindowGroup {
            switch addExpenseViewModelResult {
            case let .success(viewModel):
                AddExpenseView(viewModel: viewModel, onClose: {})
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

enum AppDependencyFactory {
    static func makeAddExpenseViewModel(inMemory: Bool = false) throws -> AddExpenseViewModel {
        let database: AppDatabase
        if inMemory {
            database = try AppDatabase.inMemory()
        } else {
            database = try AppDatabase()
        }

        let seedData = try SeedLoader().load()

        return AddExpenseViewModel(
            transactionRepository: TransactionRepository(database: database),
            catalogProvider: CatalogProvider(seedData: seedData),
            rateProvider: RateProvider(seedData: seedData)
        )
    }
}
