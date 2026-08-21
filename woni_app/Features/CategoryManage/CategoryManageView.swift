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
                    // 자리를 비키는 다른 행과 드롭 직후 복귀만 애니메이션한다. 드래그 오프셋까지
                    // 애니메이션에 넣으면 끄는 행이 손가락을 늦게 따라온다.
                    .animation(.easeInOut(duration: 0.2), value: viewModel.rows.map(\.id))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.draggingID)
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
        .onAppear {
            isTopmost = true
            _ = viewModel.consumeSyncNotice()
        }
        .onChange(of: viewModel.syncNotice) { _, notice in
            guard notice != nil, isTopmost else {
                return
            }
            showSyncNotice()
        }
        .onDisappear { isTopmost = false }
    }
}

private extension CategoryManageView {
    /// 행 조작 잠금 — 삭제 요청 중이거나 드래그가 커밋될 때까지.
    var isRowLocked: Bool {
        viewModel.isDeleting || viewModel.isReordering
    }

    /// 삭제·드래그 진행 중에는 전환을 막아 대상 목록을 고정한다.
    var typeIndicator: some View {
        EntryTypeTabBar(
            selected: viewModel.tab,
            identifierPrefix: "categoryManage",
            isEnabled: !isRowLocked
        ) {
            viewModel.selectTab($0)
        }
    }

    func rowView(_ row: CategoryManageViewModel.Row) -> some View {
        let isDragging = viewModel.draggingID == row.id

        return HStack(spacing: 12) {
            reorderHandle(row)

            NavigationLink(value: EntryRoute.editCategory(
                viewModel.tab,
                id: row.id,
                name: row.category.displayNameKo
            )) {
                HStack {
                    Text(rowLabel(row.category))
                        .woniFont(.body3)
                        .foregroundStyle(WoniColor.gray100)

                    Spacer()
                }
                // 행 높이를 채워야 한다. 텍스트 높이만 잡으면 위아래 여백이 히트 테스트에서 빠져
                // 이름을 정확히 눌러야만 수정 화면이 열린다(커밋 e7bb408과 같은 함정).
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("categoryManage.edit.\(row.id)")
            .disabled(isRowLocked)

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
            .disabled(isRowLocked)
        }
        .padding(.horizontal, 20)
        .frame(height: CategoryManageViewModel.rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WoniColor.base20)
                .frame(height: 1)
        }
        // 끌고 지나가는 동안 아래 행이 비쳐 보이지 않게 그 행만 불투명하게 만든다.
        .background(isDragging ? WoniColor.base10 : .clear)
        .offset(y: isDragging ? viewModel.draggingOffset : 0)
        .zIndex(isDragging ? 1 : 0)
    }

    /// 드래그는 핸들에만 붙인다 — 행 본문은 `NavigationLink`(행 탭=수정)을 그대로 살린다(R2).
    func reorderHandle(_ row: CategoryManageViewModel.Row) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(WoniColor.gray60)
            // 아이콘은 시안대로 24×24(x=20)지만 히트영역은 44×44를 확보한다 — 24pt만 잡으면
            // 커밋 e7bb408과 같은 함정에 빠진다. 음수 패딩으로 레이아웃 폭만 24로 되돌린다.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .padding(.horizontal, -10)
            .gesture(
                // 좌표계는 `.global`이어야 한다. 기본 `.local`은 끌리는 행의 `.offset(y:)`과 함께
                // 움직여 translation이 자기 이동량만큼 상쇄되고(계측: 168pt를 끌어도 1칸만 이동),
                // 손가락이 실제로 지난 거리가 인덱스 계산에 도달하지 못한다.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        // 시작은 한 번이고, 다른 행이 끌리는 중이면 이 행의 프레임은 버린다.
                        guard viewModel.beginDrag(id: row.id) else {
                            return
                        }
                        viewModel.updateDrag(translation: value.translation.height)
                    }
                    .onEnded { _ in
                        commitReorder { await viewModel.endDrag(id: row.id) }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(WoniStrings.categoryReorderHandle(language))
            .accessibilityIdentifier("categoryManage.reorderHandle.\(row.id)")
            .accessibilityAction(named: Text(WoniStrings.categoryReorderMoveUp(language))) {
                commitReorder { await viewModel.move(id: row.id, by: -1) }
            }
            .accessibilityAction(named: Text(WoniStrings.categoryReorderMoveDown(language))) {
                commitReorder { await viewModel.move(id: row.id, by: 1) }
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
            case .failed:
                toastMessage = WoniStrings.categoryDeleteFailedToast(language)
            }
        }
    }

    /// 로컬 저장 자체가 거부된 경우만 알린다 — 전송 실패는 큐가 조용히 재시도한다(R8).
    func commitReorder(_ commit: @escaping () async -> CategoryManageViewModel.ReorderOutcome?) {
        Task {
            guard await commit() == .localWriteRejected, isTopmost else {
                return
            }
            toastMessage = WoniStrings.categoryUpdateFailedToast(language)
        }
    }

    func showSyncNotice() {
        guard let notice = viewModel.consumeSyncNotice() else {
            return
        }
        switch notice {
        case let .limitExceeded(pendingCreateCount):
            toastMessage = WoniStrings.categorySyncLimitExceededToast(
                language,
                pendingCount: pendingCreateCount
            )
        case .categoryNotFound:
            toastMessage = WoniStrings.categorySyncNotFoundToast(language)
        }
    }
}
