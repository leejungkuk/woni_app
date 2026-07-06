import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showLogin = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showSupportPending = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "설정") {
                dismiss()
            }
            .zIndex(1)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsRow(title: "기본 통화", value: "KRW")
                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 11) {
                        SettingsRow(title: "언어 설정") {
                            openSystemSettings()
                        }
                        SettingsRow(title: "로그인/회원가입") {
                            showLogin = true
                        }
                    }
                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 11) {
                        SettingsRow(title: "앱 버전", value: appVersion)
                        SettingsRow(title: "고객센터") {
                            showSupportPending = true
                        }
                        SettingsRow(title: "서비스 약관") {
                            showTerms = true
                        }
                        SettingsRow(title: "개인정보 보호정책") {
                            showPrivacy = true
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(WoniColor.gray00)
        }
        .background(WoniColor.gray00)
        .sheet(isPresented: $showLogin) {
            LoginSheet()
        }
        .navigationDestination(isPresented: $showTerms) {
            LegalTextView(title: "서비스 약관", clauses: LegalContent.termsOfService)
        }
        .navigationDestination(isPresented: $showPrivacy) {
            LegalTextView(
                title: "개인정보 보호정책",
                clauses: [],
                pendingNote: LegalContent.privacyPolicyPending
            )
        }
        .alert("고객센터", isPresented: $showSupportPending) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("고객센터 연결은 준비 중입니다.")
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
