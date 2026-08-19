//
//  CategoryManageView.swift
//  woni_app
//

import SwiftUI

struct CategoryManageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLanguageStore.self) private var languageStore

    @State private var viewModel: CategoryManageViewModel
    @State private var toastMessage: String?
    /// 원격 로그아웃 리셋은 isDeleting과 무관하게 cover를 강제로 닫으므로, 늦은 완료
    /// 콜백은 이 화면이 최상단일 때만 후속 동작을 한다.
    @State private var isTopmost = false

    init(viewModel: CategoryManageViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var language: AppLanguage {
        languageStore.language
    }

    private var accentColor: Color {
        viewModel.tab == .expense ? WoniColor.terracotta100 : WoniColor.olive100
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                SettingsHeader(
                    title: WoniStrings.categoryManageTitle(language),
                    backLabel: WoniStrings.back(language)
                ) {
                    dismiss()
                }
                // 요청 중 이탈 차단 — `<`와 edge-swipe를 함께 막는다. 사용자 이탈이 아닌
                // 강제 종료(원격 로그아웃 리셋)는 완료 콜백의 isTopmost 가드가 막는다.
                .disabled(viewModel.isDeleting)
                .zIndex(1)

                typeIndicator

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.rows, content: rowView)

                        if viewModel.showsLoadError {
                            loadErrorSection
                        } else if viewModel.showsEmptyState {
                            emptySection
                        }

                        Text(WoniStrings.categoryManageDefaultNotice(language))
                            .woniFont(.small1)
                            .foregroundStyle(WoniColor.gray60)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                    }
                }
                .background(WoniColor.base10)

                addButton
            }
            .background(WoniColor.gray00)

            if viewModel.pendingDeletion != nil {
                // 파괴적 확인 문구는 기존 항목 삭제 다이얼로그와 동일하다(시안 ④⑪).
                WoniConfirmDialog(
                    title: WoniStrings.deleteConfirmationTitle(language),
                    message: WoniStrings.deleteConfirmationMessage(language),
                    confirmTitle: WoniStrings.deleteConfirmationDelete(language),
                    cancelTitle: WoniStrings.deleteConfirmationCancel(language),
                    identifier: "categoryManage.deleteDialog",
                    isBusy: viewModel.isDeleting,
                    onConfirm: confirmDelete,
                    onCancel: { viewModel.cancelDelete() }
                )
                .zIndex(10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled(!viewModel.isDeleting)
        .woniToast($toastMessage, showsCheckmark: false)
        .onAppear { isTopmost = true }
        .onDisappear { isTopmost = false }
    }
}

private extension CategoryManageView {
    /// 관리 대상 타입 전환 탭(2026-08-19 사용자 결정 — 진입 탭 고정에서 전환 가능으로 변경).
    /// 삭제 진행 중에는 전환을 막아 요청 대상 목록을 고정한다.
    var typeIndicator: some View {
        HStack(spacing: 0) {
            typeButton(
                .expense,
                title: WoniStrings.tabExpense(language),
                activeColor: WoniColor.terracotta100
            )
            typeButton(
                .income,
                title: WoniStrings.tabIncome(language),
                activeColor: WoniColor.olive100
            )
        }
        .background(WoniColor.gray00)
    }

    func typeButton(_ tab: EntryType, title: String, activeColor: Color) -> some View {
        let isActive = viewModel.tab == tab
        return Button {
            viewModel.selectTab(tab)
        } label: {
            Text(title)
                .woniFont(.body2)
                .foregroundStyle(isActive ? activeColor : WoniColor.gray40)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? activeColor : WoniColor.base20)
                        .frame(height: isActive ? 2 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("categoryManage.tab.\(tab == .expense ? "expense" : "income")")
        .disabled(viewModel.isDeleting)
    }

    func rowView(_ row: CategoryManageViewModel.Row) -> some View {
        HStack(spacing: 12) {
            Text(rowLabel(row.category))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray100)

            Spacer()

            Button {
                viewModel.requestDelete(row.category)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WoniColor.gray60)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WoniStrings.deleteEntry(language))
            .accessibilityIdentifier("categoryManage.delete.\(row.id)")
            .disabled(viewModel.isDeleting)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WoniColor.base20)
                .frame(height: 1)
        }
    }

    /// 기본은 icon 필드를 이름 앞에 붙이고, 커스텀은 이름에 이모지가 이미 포함돼 icon이 nil이다
    /// (칩 `EntryChipItem.displayLabel`과 같은 규칙).
    func rowLabel(_ category: Category) -> String {
        let name = language == .ko ? category.displayNameKo : category.displayNameEn
        return category.icon.map { "\($0) \(name)" } ?? name
    }

    var emptySection: some View {
        VStack(spacing: 8) {
            Text(WoniStrings.categoryManageEmptyTitle(language))
                .woniFont(.body2)
                .foregroundStyle(WoniColor.gray100)
            Text(WoniStrings.categoryManageEmptySubtitle(language))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray60)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    var loadErrorSection: some View {
        VStack(spacing: 12) {
            Text(WoniStrings.categoryManageLoadFailed(language))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray80)

            Button {
                Task {
                    await viewModel.retryRefresh()
                }
            } label: {
                Text(WoniStrings.retry(language))
                    .woniFont(.body3)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .overlay {
                        Capsule().stroke(accentColor, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("categoryManage.retry")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    var addButton: some View {
        NavigationLink(value: EntryRoute.add(viewModel.tab)) {
            Text(WoniStrings.categoryAddButton(language))
                .woniFont(.body2)
                .foregroundStyle(WoniColor.base10)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(accentColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("categoryManage.add")
        .disabled(viewModel.isDeleting)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    func confirmDelete() {
        Task {
            guard let outcome = await viewModel.confirmDelete(), isTopmost else {
                return
            }
            switch outcome {
            case .success:
                break
            case .offline:
                toastMessage = WoniStrings.categoryOfflineDeleteToast(language)
            case .blockedByPendingEntries:
                toastMessage = WoniStrings.categoryDeletePendingEntriesToast(language)
            case .failed:
                toastMessage = WoniStrings.categoryDeleteFailedToast(language)
            }
        }
    }
}
