import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var viewModel: SettingsViewModel

    @State private var showLogin = false
    @State private var showLanguageSettings = false
    @State private var legalSheet: LegalLink?
    /// 확인을 누른 시점의 신원. 삭제가 끝나면 이미 새 익명 신원이라 그때 판별하면
    /// 회원 탈퇴에도 게스트 문구가 나온다. 문구가 아니라 신원만 들고 있어야 삭제 도중
    /// 언어를 바꿔도 완료 알림이 최신 언어로 나온다.
    @State private var withdrewAsMember: Bool?
    /// 이 화면에서 확인한 purge만 완료 토스트를 띄운다. 부팅·foreground 복구 완료는 조용히 소비한다.
    @State private var startedPurgeHere = false

    /// 삭제를 마치고 화면을 닫는다. 완료는 홈에서 토스트로 알린다.
    let onFinish: (_ wasMember: Bool) -> Void

    init(viewModel: SettingsViewModel, onFinish: @escaping (_ wasMember: Bool) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onFinish = onFinish
    }

    private var language: AppLanguage {
        languageStore.language
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var isSignedIn: Bool {
        viewModel.loginViewModel.identityState == .signedIn
    }

    /// 회원은 계정까지, 비회원은 데이터만 지운다(D3). 행·식별자는 하나로 유지하고 제목만 나눈다.
    private var withdrawTitle: String {
        isSignedIn ? WoniStrings.withdraw(language) : WoniStrings.deleteMyData(language)
    }

    private var withdrawConfirmMessage: String {
        guard isSignedIn else {
            return WoniStrings.withdrawConfirmMessageGuest(language)
        }
        return viewModel.withdrawalState == .awaitingConfirmation(isAppleLinked: true)
            ? WoniStrings.withdrawConfirmMessageMemberApple(language)
            : WoniStrings.withdrawConfirmMessageMember(language)
    }

    private var withdrawConfirmTitle: String {
        isSignedIn
            ? WoniStrings.withdrawConfirmTitleMember(language)
            : WoniStrings.withdrawConfirmTitleGuest(language)
    }

    private var withdrawConfirmActionTitle: String {
        isSignedIn
            ? WoniStrings.withdrawActionMember(language)
            : WoniStrings.withdrawActionGuest(language)
    }

    private var isWithdrawalAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = viewModel.withdrawalState {
            return true
        }
        return false
    }

    private var isPurgeAwaitingConfirmation: Bool {
        viewModel.purgeState == .awaitingConfirmation
    }

    private var isPurgeBlockingSessionEntry: Bool {
        isPurgeAwaitingConfirmation || viewModel.isPurgeBlockingEntry
    }

    var body: some View {
        ZStack {
            content

            if case .awaitingConfirmation = viewModel.withdrawalState {
                WoniConfirmDialog(
                    title: withdrawConfirmTitle,
                    message: withdrawConfirmMessage,
                    confirmTitle: withdrawConfirmActionTitle,
                    cancelTitle: WoniStrings.cancel(language),
                    identifier: "settings.withdrawDialog",
                    onConfirm: {
                        withdrewAsMember = isSignedIn
                        Task {
                            await viewModel.confirmWithdrawal()
                        }
                    },
                    onCancel: {
                        withdrewAsMember = nil
                        viewModel.cancelWithdrawal()
                    }
                )
            }

            if isPurgeAwaitingConfirmation {
                WoniConfirmDialog(
                    title: WoniStrings.withdrawConfirmTitleGuest(language),
                    message: WoniStrings.purgeConfirmMessage(language),
                    confirmTitle: WoniStrings.withdrawActionGuest(language),
                    cancelTitle: WoniStrings.cancel(language),
                    identifier: "settings.purgeDialog",
                    onConfirm: {
                        startedPurgeHere = true
                        Task {
                            await viewModel.confirmPurge()
                        }
                    },
                    onCancel: {
                        startedPurgeHere = false
                        viewModel.cancelPurge()
                    }
                )
            }
        }
    }
}

private extension SettingsView {
    private var content: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: WoniStrings.settingsTitle(language), backLabel: WoniStrings.back(language)) {
                dismiss()
            }
            .zIndex(1)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isSignedIn {
                        SettingsRow(
                            title: WoniStrings.myInfo(language),
                            value: viewModel.loginViewModel.signedInEmail
                        )
                        .accessibilityIdentifier("settings.row.myInfo")
                        SettingsDivider()
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        if viewModel.loginViewModel.identityState == .anonymous {
                            SettingsRow(title: WoniStrings.loginSignup(language)) {
                                showLogin = true
                            }
                            // 로그아웃/cleanup 진행 중에는 로그인 진입을 막는다. VM 재생성 후
                            // 세션이 이미 없어 identityState가 anonymous로 보여도, 이전 멤버
                            // 로컬 데이터 정리가 끝나기 전 로그인해 데이터가 섞이는 것을 방지한다.
                            // 삭제 확인 이후에는 로그인 진입도 막는다. 전이는 차단이 아니라 큐잉이라
                            // 막지 않으면 삭제 완료 직후 새 익명 신원에 로그인이 시작된다.
                            .disabled(
                                viewModel.isLoginBlocked
                                    || viewModel.isWithdrawalBlockingEntry
                                    || isPurgeBlockingSessionEntry
                            )
                        } else {
                            SettingsRow(
                                title: WoniStrings.logout(language),
                                value: viewModel.isLoggingOut
                                    ? WoniStrings.logoutSyncing(language)
                                    : nil,
                                titleColor: WoniColor.terracotta100
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
                                    || isPurgeBlockingSessionEntry
                            )
                        }

                        SettingsRow(
                            title: withdrawTitle,
                            value: viewModel.withdrawalState == .deleting
                                ? WoniStrings.withdrawInProgress(language)
                                : nil
                        ) {
                            viewModel.prepareWithdrawal()
                        }
                        .accessibilityIdentifier("settings.row.withdraw")
                        .disabled(
                            viewModel.isWithdrawalBlockingEntry
                                || isPurgeBlockingSessionEntry
                        )

                        if isSignedIn {
                            SettingsRow(
                                title: WoniStrings.deleteMyData(language),
                                value: viewModel.purgeState == .deleting
                                    ? WoniStrings.withdrawInProgress(language)
                                    : nil
                            ) {
                                viewModel.preparePurge()
                            }
                            .accessibilityIdentifier("settings.row.deleteMyData")
                            .disabled(
                                viewModel.isPurgeEntryBlocked
                                    || viewModel.isWithdrawalBlockingEntry
                                    || isWithdrawalAwaitingConfirmation
                            )
                        }
                    }
                    SettingsDivider()

                    SettingsRow(title: WoniStrings.languageRow(language)) {
                        showLanguageSettings = true
                    }
                    .accessibilityIdentifier("settings.row.language")
                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 11) {
                        SettingsRow(title: WoniStrings.appVersion(language), value: appVersion)
                        SettingsRow(title: WoniStrings.support(language)) {
                            legalSheet = LegalContent.supportLink
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
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(WoniColor.gray00)
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
        // Apple 연동이 남은 탈퇴만 여기서 알린다. 사용자가 iOS 설정에서 직접 해제해야 하는
        // 안내라 토스트 한 줄에 담기지 않는다. 나머지는 홈에서 토스트로 알린다.
        .alert(
            WoniStrings.withdrawCompletedMessage(language),
            isPresented: Binding(
                get: { viewModel.withdrawalState == .completed(appleUnlinkPending: true) },
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
            Text(WoniStrings.withdrawCompletedAppleNote(language))
        }
        // 삭제 중 이 화면을 벗어나면 완료 전이를 볼 뷰가 없다. 다시 들어왔을 때 `.completed`인 채로
        // 마운트되므로 `initial: true`로 그때도 종단 처리를 한다 — 놓치면 코디네이터가 완료에 머물러
        // 로그인·로그아웃·탈퇴 진입이 영구히 막힌다.
        .onChange(of: viewModel.withdrawalState, initial: true) { _, state in
            guard state == .completed(appleUnlinkPending: false) else {
                return
            }
            let wasMember = withdrewAsMember
            withdrewAsMember = nil
            viewModel.acknowledgeWithdrawalCompletion()
            // 확인을 이 화면에서 누른 경우에만 알린다. 벗어난 사이 끝났다면 회원이었는지 알 수 없고,
            // 완료 후에는 이미 새 익명 신원이라 지금 판별하면 회원 탈퇴에도 게스트 문구가 나간다.
            if let wasMember {
                onFinish(wasMember)
            }
        }
        .onChange(of: viewModel.purgeState, initial: true) { _, state in
            guard state == .completed else {
                return
            }
            let shouldFinish = startedPurgeHere
            startedPurgeHere = false
            viewModel.acknowledgePurgeCompletion()
            if shouldFinish {
                onFinish(false)
            }
        }
        .alert(
            WoniStrings.deleteMyData(language),
            isPresented: Binding(
                get: {
                    viewModel.purgeState == .completionPending(acknowledged: false)
                },
                set: { isPresented in
                    if !isPresented {
                        viewModel.acknowledgePurgePending()
                    }
                }
            )
        ) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {
                viewModel.acknowledgePurgePending()
            }
        } message: {
            Text(WoniStrings.purgePendingMessage(language))
        }
        .alert(
            WoniStrings.deleteMyData(language),
            isPresented: Binding(
                get: { viewModel.purgeState == .failed },
                set: { isPresented in
                    if !isPresented {
                        startedPurgeHere = false
                        viewModel.dismissPurgeFailure()
                    }
                }
            )
        ) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {}
        } message: {
            Text(WoniStrings.withdrawFailedMessage(language))
        }
        .alert(
            WoniStrings.deleteMyData(language),
            isPresented: Binding(
                get: { viewModel.purgeState == .offline },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissPurgeOffline()
                    }
                }
            )
        ) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {}
        } message: {
            Text(WoniStrings.withdrawOfflineMessage(language))
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
        .interactivePopGestureEnabled()
        // `@State(initialValue:)`로 유지되는 이 인스턴스만 구독한다. `LoginSheet`에 또 붙이면
        // 같은 인스턴스가 중복 구독한다.
        .task {
            await viewModel.loginViewModel.observeIdentity()
        }
    }
}
