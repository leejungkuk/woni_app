import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageStore.self) private var languageStore
    @Environment(BaseCurrencyStore.self) private var baseCurrencyStore
    @State private var viewModel: SettingsViewModel

    @State private var showLogin = false
    @State private var showBaseCurrencyPicker = false
    @State private var showLanguageSettings = false
    @State private var legalSheet: LegalLink?
    @State private var showSupportPending = false

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var language: AppLanguage {
        languageStore.language
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    /// 회원은 계정까지, 비회원은 데이터만 지운다(D3). 행·식별자는 하나로 유지하고 제목만 나눈다.
    private var withdrawTitle: String {
        viewModel.loginViewModel.identityState == .signedIn
            ? WoniStrings.withdraw(language)
            : WoniStrings.deleteMyData(language)
    }

    private var withdrawConfirmMessage: String {
        guard viewModel.loginViewModel.identityState == .signedIn else {
            return WoniStrings.withdrawConfirmMessageGuest(language)
        }
        return viewModel.withdrawalState == .awaitingConfirmation(isAppleLinked: true)
            ? WoniStrings.withdrawConfirmMessageMemberApple(language)
            : WoniStrings.withdrawConfirmMessageMember(language)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                SettingsHeader(title: WoniStrings.settingsTitle(language)) {
                    dismiss()
                }
                .zIndex(1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if viewModel.loginViewModel.identityState == .signedIn {
                            SettingsRow(
                                title: WoniStrings.myInfo(language),
                                value: viewModel.loginViewModel.signedInEmail
                            )
                            .accessibilityIdentifier("settings.row.myInfo")
                            SettingsDivider()
                        }

                        SettingsRow(
                            title: WoniStrings.baseCurrency(language),
                            value: baseCurrencyStore.baseCurrency.rawValue
                        ) {
                            showBaseCurrencyPicker = true
                        }
                        .accessibilityIdentifier("settings.row.baseCurrency")
                        SettingsDivider()

                        VStack(alignment: .leading, spacing: 11) {
                            SettingsRow(title: WoniStrings.languageRow(language)) {
                                showLanguageSettings = true
                            }
                            .accessibilityIdentifier("settings.row.language")
                            if viewModel.loginViewModel.identityState == .anonymous {
                                SettingsRow(title: WoniStrings.loginSignup(language)) {
                                    showLogin = true
                                }
                                // 로그아웃/cleanup 진행 중에는 로그인 진입을 막는다. VM 재생성 후
                                // 세션이 이미 없어 identityState가 anonymous로 보여도, 이전 멤버
                                // 로컬 데이터 정리가 끝나기 전 로그인해 데이터가 섞이는 것을 방지한다.
                                // 삭제 확인 이후에는 로그인 진입도 막는다. 전이는 차단이 아니라 큐잉이라
                                // 막지 않으면 삭제 완료 직후 새 익명 신원에 로그인이 시작된다.
                                .disabled(viewModel.isLoginBlocked || viewModel.isWithdrawalBlockingEntry)
                            } else {
                                SettingsRow(
                                    title: WoniStrings.logout(language),
                                    value: viewModel.isLoggingOut
                                        ? WoniStrings.logoutSyncing(language)
                                        : nil
                                ) {
                                    Task {
                                        await viewModel.requestLogout()
                                    }
                                }
                                .accessibilityIdentifier("settings.row.logout")
                                .disabled(
                                    viewModel.isLoggingOut
                                        || viewModel.needsCleanup
                                        || viewModel.isWithdrawalBlockingEntry
                                )
                            }
                        }
                        SettingsDivider()

                        VStack(alignment: .leading, spacing: 11) {
                            SettingsRow(title: WoniStrings.appVersion(language), value: appVersion)
                            SettingsRow(title: WoniStrings.support(language)) {
                                showSupportPending = true
                            }
                            .accessibilityIdentifier("settings.row.support")
                            SettingsRow(title: WoniStrings.terms(language)) {
                                legalSheet = LegalContent.termsOfServiceLink(language)
                            }
                            .accessibilityIdentifier("settings.row.terms")
                            SettingsRow(title: WoniStrings.privacy(language)) {
                                legalSheet = LegalContent.privacyPolicyLink(language)
                            }
                            .accessibilityIdentifier("settings.row.privacy")
                        }

                        SettingsDivider()
                        SettingsRow(
                            title: withdrawTitle,
                            value: viewModel.withdrawalState == .deleting
                                ? WoniStrings.withdrawInProgress(language)
                                : nil
                        ) {
                            viewModel.prepareWithdrawal()
                        }
                        .accessibilityIdentifier("settings.row.withdraw")
                        .disabled(viewModel.isWithdrawalBlockingEntry)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
                .background(WoniColor.gray00)
            }

            if showBaseCurrencyPicker {
                CurrencyPickerOverlay(
                    selection: Binding(
                        get: { baseCurrencyStore.baseCurrency.rawValue },
                        set: { code in
                            guard let currency = SelectableCurrency(rawValue: code) else {
                                return
                            }
                            baseCurrencyStore.baseCurrency = currency
                        }
                    ),
                    isPresented: $showBaseCurrencyPicker,
                    options: SelectableCurrency.entryPickerOptions,
                    language: language,
                    accentColor: WoniColor.terracotta110
                )
            }
        }
        .background(WoniColor.gray00)
        .sheet(isPresented: $showLogin) {
            LoginSheet(language: language, viewModel: viewModel.loginViewModel)
        }
        .navigationDestination(isPresented: $showLanguageSettings) {
            LanguageSettingsView()
        }
        .sheet(item: $legalSheet) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        .alert(WoniStrings.support(language), isPresented: $showSupportPending) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {}
        } message: {
            Text(WoniStrings.supportPending(language))
        }
        .alert(
            withdrawTitle,
            isPresented: Binding(
                get: {
                    if case .awaitingConfirmation = viewModel.withdrawalState { true } else { false }
                },
                // 확인을 누르면 상태가 .deleting으로 바뀌며 이 알럿이 닫히고, 그때도 setter가 온다.
                // 그 호출을 취소로 해석하면 진행 중인 삭제 상태가 지워진다 — 확인 대기 중일 때만 취소다.
                set: { isPresented in
                    if !isPresented, case .awaitingConfirmation = viewModel.withdrawalState {
                        viewModel.cancelWithdrawal()
                    }
                }
            )
        ) {
            Button(WoniStrings.cancel(language), role: .cancel) {}
            Button(WoniStrings.withdrawConfirmAction(language), role: .destructive) {
                Task {
                    await viewModel.confirmWithdrawal()
                }
            }
        } message: {
            Text(withdrawConfirmMessage)
        }
        // 완료 시점에는 이미 새 익명 신원이라 행 제목이 "내 데이터 삭제"로 바뀌어 있다. 제목에
        // 완료 문구를 두어 방금 무엇이 끝났는지가 신원 전환에 흔들리지 않게 한다.
        .alert(
            WoniStrings.withdrawCompletedMessage(language),
            isPresented: Binding(
                get: {
                    if case .completed = viewModel.withdrawalState { true } else { false }
                },
                set: { isPresented in
                    if !isPresented {
                        viewModel.acknowledgeWithdrawalCompletion()
                    }
                }
            )
        ) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {
                dismiss()
            }
        } message: {
            if viewModel.withdrawalState == .completed(appleUnlinkPending: true) {
                Text(WoniStrings.withdrawCompletedAppleNote(language))
            }
        }
        .alert(
            withdrawTitle,
            isPresented: Binding(
                get: { viewModel.withdrawalState == .failed },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissWithdrawalFailure()
                    }
                }
            )
        ) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {}
        } message: {
            Text(WoniStrings.withdrawFailedMessage(language))
        }
        .alert(
            withdrawTitle,
            isPresented: Binding(
                get: { viewModel.withdrawalState == .offline },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissWithdrawalOffline()
                    }
                }
            )
        ) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {}
        } message: {
            Text(WoniStrings.withdrawOfflineMessage(language))
        }
        .alert(
            WoniStrings.unsyncedLogoutTitle(language),
            isPresented: Binding(
                get: { viewModel.hasUnsyncedLogoutWarning },
                set: { _ in }
            )
        ) {
            Button(WoniStrings.cancel(language), role: .cancel) {
                viewModel.cancelForcedLogout()
            }
            Button(WoniStrings.forceLogout(language), role: .destructive) {
                Task {
                    await viewModel.confirmForcedLogout()
                }
            }
        } message: {
            Text(WoniStrings.unsyncedLogoutMessage(language))
        }
        .alert(
            WoniStrings.logoutFailedTitle(language),
            isPresented: Binding(
                get: { viewModel.hasLogoutFailure },
                set: { _ in }
            )
        ) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {
                viewModel.dismissLogoutFailure()
            }
        } message: {
            Text(WoniStrings.logoutFailedMessage(language))
        }
        .alert(
            WoniStrings.logoutCleanupRequiredTitle(language),
            isPresented: Binding(
                get: { viewModel.needsCleanup },
                set: { _ in }
            )
        ) {
            Button(WoniStrings.retry(language)) {
                Task {
                    await viewModel.retryCleanup()
                }
            }
        } message: {
            Text(WoniStrings.logoutCleanupRequiredMessage(language))
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
