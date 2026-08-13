//
//  SettingsViewModel.swift
//  woni_app
//

import Observation

@MainActor
@Observable
final class SettingsViewModel {
    typealias LogoutState = SessionTransitionCoordinator.LogoutState
    typealias WithdrawalState = WithdrawalCoordinator.WithdrawalState
    typealias PurgeState = DataPurgeCoordinator.PurgeState

    let loginViewModel: LoginViewModel
    let coordinator: SessionTransitionCoordinator
    let withdrawalCoordinator: WithdrawalCoordinator
    let dataPurgeCoordinator: DataPurgeCoordinator

    init(
        loginViewModel: LoginViewModel,
        coordinator: SessionTransitionCoordinator,
        withdrawalCoordinator: WithdrawalCoordinator,
        dataPurgeCoordinator: DataPurgeCoordinator
    ) {
        self.loginViewModel = loginViewModel
        self.coordinator = coordinator
        self.withdrawalCoordinator = withdrawalCoordinator
        self.dataPurgeCoordinator = dataPurgeCoordinator
    }

    var logoutState: LogoutState {
        coordinator.logoutState
    }

    var isLoggingOut: Bool {
        coordinator.isLoggingOut
    }

    var hasUnsyncedLogoutWarning: Bool {
        coordinator.hasUnsyncedLogoutWarning
    }

    var hasLogoutFailure: Bool {
        coordinator.hasLogoutFailure
    }

    var needsCleanup: Bool {
        coordinator.needsCleanup
    }

    var isLoginBlocked: Bool {
        coordinator.isLoginBlocked
    }

    func requestLogout() async {
        await coordinator.requestLogout()
    }

    func confirmForcedLogout() async {
        await coordinator.confirmForcedLogout()
    }

    func cancelForcedLogout() {
        coordinator.cancelForcedLogout()
    }

    func dismissLogoutFailure() {
        coordinator.dismissLogoutFailure()
    }

    func retryCleanup() async {
        await coordinator.retryCleanup()
    }

    var withdrawalState: WithdrawalState {
        withdrawalCoordinator.state
    }

    var isWithdrawalBlockingEntry: Bool {
        withdrawalCoordinator.isBlockingOtherEntry
    }

    func prepareWithdrawal() {
        withdrawalCoordinator.prepareWithdrawal()
    }

    func confirmWithdrawal() async {
        await withdrawalCoordinator.confirmWithdrawal()
    }

    func cancelWithdrawal() {
        withdrawalCoordinator.cancelWithdrawal()
    }

    func acknowledgeWithdrawalCompletion() {
        withdrawalCoordinator.acknowledgeCompletion()
    }

    func dismissWithdrawalFailure() {
        withdrawalCoordinator.dismissFailure()
    }

    func dismissWithdrawalOffline() {
        withdrawalCoordinator.dismissOffline()
    }

    var purgeState: PurgeState {
        dataPurgeCoordinator.state
    }

    var isPurgeBlockingEntry: Bool {
        dataPurgeCoordinator.isBlockingOtherEntry
    }

    /// pending은 로그아웃 등 다른 세션 진입은 허용하지만, purge 자체 재진입은 막아야 한다.
    var isPurgeEntryBlocked: Bool {
        switch purgeState {
        case .idle, .offline:
            false
        case .awaitingConfirmation, .deleting, .completionPending, .completed, .failed:
            true
        }
    }

    func preparePurge() {
        dataPurgeCoordinator.prepare()
    }

    func confirmPurge() async {
        await dataPurgeCoordinator.confirm()
    }

    func cancelPurge() {
        dataPurgeCoordinator.cancel()
    }

    func acknowledgePurgePending() {
        dataPurgeCoordinator.acknowledgePending()
    }

    func acknowledgePurgeCompletion() {
        dataPurgeCoordinator.acknowledgeCompletion()
    }

    func dismissPurgeFailure() {
        dataPurgeCoordinator.dismissFailure()
    }

    func dismissPurgeOffline() {
        dataPurgeCoordinator.dismissOffline()
    }
}
