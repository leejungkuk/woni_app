//
//  CategoryAddView.swift
//  woni_app
//

import SwiftUI

struct CategoryAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageStore.self) private var languageStore

    @State private var viewModel: CategoryAddViewModel
    @State private var toastMessage: String?
    /// 원격 로그아웃 리셋은 isSaving과 무관하게 cover를 강제로 닫으므로, 늦은 완료 콜백은
    /// 이 화면이 최상단일 때만 pop·자동 선택을 수행한다(이중 pop 방지).
    @State private var isTopmost = false

    /// 저장 성공 시 새 카테고리 id와 생성 타입을 넘긴다. 호출자가 pop과 입력 화면
    /// 탭 전환+자동 선택(결정 10, 2026-08-19 복귀 연동)을 맡는다.
    let onSaved: (Int, EntryType) -> Void

    init(viewModel: CategoryAddViewModel, onSaved: @escaping (Int, EntryType) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSaved = onSaved
    }

    private var language: AppLanguage {
        languageStore.language
    }

    private var accentColor: Color {
        viewModel.tab == .expense ? WoniColor.terracotta100 : WoniColor.olive100
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1)
            EntryTypeTabBar(
                selected: viewModel.tab,
                identifierPrefix: "categoryAdd",
                isEnabled: !viewModel.isSaving
            ) {
                viewModel.selectTab($0)
            }
            nameSection
            Spacer()
        }
        .background(WoniColor.base10)
        .toolbar(.hidden, for: .navigationBar)
        // 요청 중 이탈 차단 — `<` disabled와 함께 edge-swipe도 막는다.
        .interactivePopGestureEnabled(!viewModel.isSaving)
        .woniToast($toastMessage, showsCheckmark: false)
        .onAppear { isTopmost = true }
        .onDisappear { isTopmost = false }
    }
}

private extension CategoryAddView {
    var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                CircleIconButton {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WoniColor.gray80)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WoniStrings.back(language))
            .accessibilityIdentifier("categoryAdd.back")
            .disabled(viewModel.isSaving)

            Spacer()

            Button(action: save) {
                Text(WoniStrings.save(language))
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.base10)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(canSubmit ? accentColor : WoniColor.gray20)
                    .clipShape(Capsule())
                    .woniShadow(.shadow1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("categoryAdd.save")
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(WoniColor.gray00)
        .overlay {
            Text(WoniStrings.categoryAddTitle(language))
                .woniFont(.body1)
                .foregroundStyle(WoniColor.gray100)
        }
    }

    var canSubmit: Bool {
        viewModel.canSave && !viewModel.isSaving
    }

    var nameSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(WoniStrings.categoryAddNameLabel(language))
                .woniFont(.small1)
                .foregroundStyle(WoniColor.gray60)

            HStack(spacing: 8) {
                TextField(WoniStrings.categoryAddNamePlaceholder(language), text: $viewModel.name)
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray100)
                    .accessibilityIdentifier("categoryAdd.name")

                Text("\(viewModel.nameLength) / \(CategoryAddViewModel.maxNameLength)")
                    .woniFont(.small1)
                    .foregroundStyle(WoniColor.gray40)
            }
            .padding(.vertical, 12)

            Rectangle()
                .fill(WoniColor.base20)
                .frame(height: 1)

            Text(notice)
                .woniFont(.small1)
                .foregroundStyle(WoniColor.gray60)
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    var notice: String {
        viewModel.tab == .expense
            ? WoniStrings.categoryAddNoticeExpense(language)
            : WoniStrings.categoryAddNoticeIncome(language)
    }

    func save() {
        Task {
            guard let outcome = await viewModel.save(), isTopmost else {
                return
            }
            switch outcome {
            case let .saved(id, type):
                onSaved(id, type)
            case .offline:
                toastMessage = WoniStrings.categoryOfflineCreateToast(language)
            case .limitExceeded:
                toastMessage = WoniStrings.categoryLimitExceededToast(language)
            case .failed:
                toastMessage = WoniStrings.categoryCreateFailedToast(language)
            }
        }
    }
}
