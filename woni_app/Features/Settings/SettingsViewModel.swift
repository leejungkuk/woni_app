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

    let loginViewModel: LoginViewModel
    let coordinator: SessionTransitionCoordinator
    let withdrawalCoordinator: WithdrawalCoordinator

    init(
        loginViewModel: LoginViewModel,
        coordinator: SessionTransitionCoordinator,
        withdrawalCoordinator: WithdrawalCoordinator
    ) {
        self.loginViewModel = loginViewModel
        self.coordinator = coordinator
        self.withdrawalCoordinator = withdrawalCoordinator
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
}
