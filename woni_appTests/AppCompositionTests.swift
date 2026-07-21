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
    @Test("부트스트랩 factory는 AddExpense와 Settings가 같은 SyncEngine·repository를 공유한다")
    func compositionRootSharesSyncEngineAndRepository() async throws {
        let dependencies = try AppDependencyFactory.makeSeedDependencies(inMemory: true)
        // 네트워크 없이 로컬 경계만 검증하기 위해 오프라인으로 고정한다(디바운스 push는 no-op).
        // #require로 fake 연결성 전제를 확정해, 타입이 달라 조용히 온라인으로 진행하는 일을 막는다.
        let connectivity = try #require(dependencies.connectivity as? FakeConnectivityMonitor)
        connectivity.setOnline(false)

        let addViewModel = AppDependencyFactory.makeAddExpenseViewModel(dependencies: dependencies)
        await addViewModel.load()

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

        await settingsViewModel.requestLogout()
        #expect(settingsViewModel.logoutState == .awaitingUnsyncedConfirmation)
        #expect(recreatedSettingsViewModel.logoutState == .awaitingUnsyncedConfirmation)
        #expect(try await dependencies.transactionRepository.count() == 1)
    }
}
