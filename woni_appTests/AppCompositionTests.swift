//
//  AppCompositionTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct AppCompositionTests {
    @Test("유닛 테스트 호스트는 XCTest 설정 경로 환경 변수를 제공한다")
    func unitTestHostProvidesXCTestConfigurationPath() {
        #expect(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
    }

    @Test("수정 라우트는 clientEntryID UUID를 그대로 전달한다")
    func editRoutePreservesClientEntryID() throws {
        let clientEntryID = UUID()
        let original = LocalTransaction(
            clientEntryID: clientEntryID,
            amount: 100,
            currencyCode: "KRW",
            categoryID: 10,
            assetID: 20,
            transactionType: .expense,
            transactionDate: "2026-07-24",
            memo: "edit"
        )

        switch EntryPresentation.edit(clientEntryID) {
        case let .edit(routedID):
            #expect(routedID == clientEntryID)
        default:
            Issue.record("edit 표시 상태가 UUID payload를 유지해야 한다")
        }

        let dependencies = try AppDependencyFactory.makeSeedDependencies(inMemory: true)
        let viewModel = AppDependencyFactory.makeAddExpenseViewModel(
            dependencies: dependencies,
            baseCurrency: .krw,
            mode: .edit(original: original)
        )
        #expect(viewModel.mode == .edit(original: original))
    }

    @Test("부트스트랩 factory는 AddExpense와 Settings가 같은 SyncEngine·repository를 공유한다")
    func compositionRootSharesSyncEngineAndRepository() async throws {
        let dependencies = try AppDependencyFactory.makeSeedDependencies(inMemory: true)
        // 네트워크 없이 로컬 경계만 검증하기 위해 오프라인으로 고정한다(디바운스 push는 no-op).
        // #require로 fake 연결성 전제를 확정해, 타입이 달라 조용히 온라인으로 진행하는 일을 막는다.
        let connectivity = try #require(dependencies.connectivity as? FakeConnectivityMonitor)
        connectivity.setOnline(false)

        let addViewModel = AppDependencyFactory.makeAddExpenseViewModel(
            dependencies: dependencies,
            baseCurrency: .krw
        )
        await addViewModel.load()
        // 카테고리·자산은 자동 선택되지 않으므로, 저장 거부 원인이 미선택이 아닌
        // 로그아웃 정지임을 격리하려면 먼저 골라 둔다.
        addViewModel.selectedCategoryId = try #require(addViewModel.visibleCategories.first?.id)
        addViewModel.selectedAssetId = try #require(addViewModel.assets.first?.id)

        // 공유 엔진을 로그아웃용으로 정지시키면 같은 엔진을 트리거로 쓰는 AddExpense 저장이
        // 거부된다. makeAddExpenseViewModel이 별도 엔진을 만들면 저장이 통과 → step5-Med1 회귀 포착.
        await dependencies.syncEngine.suspendPushForLogout()
        addViewModel.amount = 1000
        await addViewModel.save()
        #expect(!addViewModel.saveSucceeded)
        #expect(try await dependencies.transactionRepository.count() == 0)

        // 정지를 풀면 저장이 통과하고 공유 repository에 반영된다.
        dependencies.syncEngine.resumePushAfterLogout()
        await addViewModel.save()
        #expect(addViewModel.saveSucceeded)
        #expect(try await dependencies.transactionRepository.count() == 1)

        // 같은 dependencies로 만든 Settings VM의 로그아웃 가드가 그 항목을 인식한다(공유 repository).
        let settingsViewModel = AppDependencyFactory.makeSettingsViewModel(dependencies: dependencies)
        let recreatedSettingsViewModel = AppDependencyFactory.makeSettingsViewModel(
            dependencies: dependencies
        )
        #expect(settingsViewModel.coordinator === dependencies.sessionCoordinator)
        #expect(recreatedSettingsViewModel.coordinator === dependencies.sessionCoordinator)
        #expect(settingsViewModel.dataPurgeCoordinator === dependencies.dataPurgeCoordinator)
        #expect(recreatedSettingsViewModel.dataPurgeCoordinator === dependencies.dataPurgeCoordinator)

        await settingsViewModel.requestLogout()
        #expect(settingsViewModel.logoutState == .awaitingUnsyncedConfirmation)
        #expect(recreatedSettingsViewModel.logoutState == .awaitingUnsyncedConfirmation)
        #expect(try await dependencies.transactionRepository.count() == 1)
    }

    @Test("seed 조립은 온라인 복귀 시 세션 진입점을 통해 익명 신원을 확보한다")
    func seedCompositionEnsuresIdentityOnOnlineTransition() async throws {
        let dependencies = try AppDependencyFactory.makeSeedDependencies(inMemory: true)
        let auth = try #require(dependencies.authProvider as? FakeAuthService)
        let connectivity = try #require(dependencies.connectivity as? FakeConnectivityMonitor)

        #expect(auth.currentUserID == nil)
        connectivity.setOnline(true)
        for _ in 0 ..< 10000 {
            if auth.currentUserID != nil {
                break
            }
            await Task.yield()
        }

        #expect(auth.currentUserID != nil)
        #expect(auth.anonymousSignInCount == 1)
    }

    @Test("부팅 purge 준비는 같은 신원 마커만 SyncEngine 시작 중단으로 유지한다")
    func bootPurgePreparationSuspendsOnlyMatchingIdentity() async throws {
        let memberID = UUID()
        let repository = try TransactionRepository(database: AppDatabase.inMemory())
        let auth = FakeAuthService(makeSignedInUserID: { memberID })
        try await auth.signIn(.google)
        try await repository.markPurgePending(memberID: memberID.uuidString)

        let startsSuspended = try await AppDependencyFactory.prepareIncompletePurgeRecovery(
            purgeStore: repository,
            authProvider: auth
        )

        #expect(startsSuspended)
        #expect(try await repository.purgePendingMemberID() == memberID.uuidString)

        let otherRepository = try TransactionRepository(database: AppDatabase.inMemory())
        try await otherRepository.markPurgePending(memberID: UUID().uuidString)

        let startsNormally = try await AppDependencyFactory.prepareIncompletePurgeRecovery(
            purgeStore: otherRepository,
            authProvider: auth
        )

        #expect(!startsNormally)
        #expect(try await otherRepository.purgePendingMemberID() == nil)
    }

    @Test("seed 조립 purge는 ledger 변경을 발행하고 커스텀 카테고리를 DB·메모리에서 지운다")
    func seedCompositionClearsLedgerAndCustomCategoriesAfterPurge() async throws {
        let dependencies = try AppDependencyFactory.makeSeedDependencies(inMemory: true)
        let auth = try #require(dependencies.authProvider as? FakeAuthService)
        try await auth.signIn(.google)
        let memberID = try #require(auth.currentUserID)
        try await dependencies.transactionRepository.insert(LocalTransaction(
            clientEntryID: UUID(),
            amount: Decimal(100),
            currencyCode: "KRW",
            categoryID: 10,
            assetID: 20,
            transactionType: .expense,
            transactionDate: "2026-08-13",
            memo: nil
        ))
        try await dependencies.transactionRepository.markPurgePending(
            memberID: memberID.uuidString
        )
        let customCategoryID = try await dependencies.customCategoryStore.create(
            name: "purge 대상",
            type: .expense
        )
        try await dependencies.customCategoryStore.reorder(
            orderedIDs: [customCategoryID],
            type: .expense
        )
        #expect(dependencies.customCategoryStore.expenseCategories.map(\.id) == [customCategoryID])
        #expect(dependencies.customCategoryStore.hasPendingWork())
        let initialRevision = dependencies.syncEngine.ledgerRevision

        await dependencies.dataPurgeCoordinator.resumeIfPending()

        #expect(try await dependencies.transactionRepository.count() == 0)
        #expect(dependencies.syncEngine.ledgerRevision == initialRevision + 1)
        #expect(dependencies.customCategoryStore.expenseCategories.isEmpty)
        #expect(!dependencies.customCategoryStore.hasPendingWork())
        #expect(dependencies.dataPurgeCoordinator.state == .completed)
    }
}

extension AppCompositionTests {
    @Test("factory로 저장한 통화는 다음 신규 입력 기본값으로 이어진다")
    func factoryCarriesSavedCurrencyIntoNextCreate() async throws {
        try await Self.withUserDefaultsSuite { userDefaults in
            let dependencies = try AppDependencyFactory.makeSeedDependencies(inMemory: true)
            let connectivity = try #require(
                dependencies.connectivity as? FakeConnectivityMonitor
            )
            connectivity.setOnline(false)
            let store = LastUsedCurrencyStore(userDefaults: userDefaults)
            let firstViewModel = AppDependencyFactory.makeAddExpenseViewModel(
                dependencies: dependencies,
                baseCurrency: .krw,
                lastUsedCurrencyStore: store
            )
            await firstViewModel.load()
            firstViewModel.selectedCurrency = .thb
            firstViewModel.amount = 1000
            firstViewModel.selectedCategoryId = try #require(
                firstViewModel.visibleCategories.first?.id
            )
            firstViewModel.selectedAssetId = try #require(firstViewModel.assets.first?.id)

            await firstViewModel.save()

            #expect(firstViewModel.saveSucceeded)
            let nextViewModel = AppDependencyFactory.makeAddExpenseViewModel(
                dependencies: dependencies,
                baseCurrency: .krw,
                lastUsedCurrencyStore: store
            )
            #expect(nextViewModel.selectedCurrency == .thb)
        }
    }

    @Test("마지막 사용 통화를 지우면 다음 신규 입력은 새 기준 통화로 열린다")
    func factoryUsesNewBaseCurrencyAfterLastUsedCurrencyIsCleared() async throws {
        try await Self.withUserDefaultsSuite { userDefaults in
            let dependencies = try AppDependencyFactory.makeSeedDependencies(inMemory: true)
            let store = LastUsedCurrencyStore(userDefaults: userDefaults)
            store.record(.thb)

            let beforeClearViewModel = AppDependencyFactory.makeAddExpenseViewModel(
                dependencies: dependencies,
                baseCurrency: .usd,
                lastUsedCurrencyStore: store
            )
            #expect(beforeClearViewModel.selectedCurrency == .thb)

            store.clear()

            let afterClearViewModel = AppDependencyFactory.makeAddExpenseViewModel(
                dependencies: dependencies,
                baseCurrency: .usd,
                lastUsedCurrencyStore: store
            )
            #expect(afterClearViewModel.selectedCurrency == .usd)
        }
    }
}

private extension AppCompositionTests {
    static func withUserDefaultsSuite(
        _ body: (UserDefaults) async throws -> Void
    ) async throws {
        let suiteName = "woni_appTests.AppCompositionTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await body(userDefaults)
    }
}
