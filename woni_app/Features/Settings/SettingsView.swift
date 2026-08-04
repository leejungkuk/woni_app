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
    @State private var showWithdrawPending = false

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var language: AppLanguage {
        languageStore.language
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
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
                                .disabled(viewModel.isLoginBlocked)
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
                                .disabled(viewModel.isLoggingOut || viewModel.needsCleanup)
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

                        if viewModel.loginViewModel.identityState == .signedIn {
                            SettingsDivider()
                            SettingsRow(title: WoniStrings.withdraw(language)) {
                                showWithdrawPending = true
                            }
                            .accessibilityIdentifier("settings.row.withdraw")
                        }
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
        .alert(WoniStrings.withdraw(language), isPresented: $showWithdrawPending) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {}
        } message: {
            Text(WoniStrings.withdrawPending(language))
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
