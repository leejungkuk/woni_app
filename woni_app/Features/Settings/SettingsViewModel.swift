//
//  SettingsViewModel.swift
//  woni_app
//

import Observation

@MainActor
@Observable
final class SettingsViewModel {
    typealias LogoutState = SessionTransitionCoordinator.LogoutState

    let loginViewModel: LoginViewModel
    let coordinator: SessionTransitionCoordinator

    init(
        loginViewModel: LoginViewModel,
        coordinator: SessionTransitionCoordinator
    ) {
        self.loginViewModel = loginViewModel
        self.coordinator = coordinator
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
}
