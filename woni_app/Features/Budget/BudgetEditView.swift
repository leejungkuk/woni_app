//
//  BudgetEditView.swift
//  woni_app
//

import SwiftUI

/// 예산 편집 화면(UI_GUIDE "편집 화면"). 상태·판정은 `BudgetEditViewModel` 이 정하고 여기서는 그리기와 입력 전달만 한다.
/// 통화 시트·확인 창·토스트는 이 화면 안에서 그린다 — 전체 화면 모달 안의 오버레이다(UI_GUIDE "탭 안 화면의 피커·확인 창").
struct BudgetEditView: View {
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var viewModel: BudgetEditViewModel
    @State private var focusedField: BudgetEditField?
    @State private var isCurrencyPickerPresented = false
    @State private var toastMessage: String?

    /// 칩 = 내 카테고리 → 기본. 열 때 고정하지 않고 그릴 때마다 읽는다 — 저장이 실패해도 새 카테고리 올리기는 이미
    /// 성공해 목록의 번호가 서버 번호로 바뀌어 있고, 고정된 목록으로는 그 줄의 이름을 못 찾는다.
    private let categories: () -> [Category]

    init(viewModel: BudgetEditViewModel, categories: @escaping () -> [Category]) {
        _viewModel = State(initialValue: viewModel)
        self.categories = categories
    }

    private var language: AppLanguage {
        languageStore.language
    }

    var body: some View {
        let currentCategories = categories()
        ZStack {
            VStack(spacing: 0) {
                header
                    .zIndex(1)

                ScrollView {
                    VStack(spacing: 0) {
                        monthRow
                        content(categories: currentCategories)
                    }
                    .padding(.bottom, 24)
                    // 키보드 내리기는 입력 화면(`AddEntryView`)과 같다 — 빈 곳을 누르거나 스크롤하면 내린다.
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded { hideKeyboard() }
                    )
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(WoniColor.base10)

            if isCurrencyPickerPresented {
                currencyPicker
            }

            if let dialog = viewModel.dialog {
                confirmDialog(dialog)
                    .zIndex(10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // 쓰는 중 이탈 차단 — X·저장 비활성과 함께 끌어 닫기도 막는다.
        .interactiveDismissDisabled(viewModel.isWriting)
        .woniToast($toastMessage, showsCheckmark: false)
        .onChange(of: viewModel.toast) { _, toast in
            guard let toast else {
                return
            }
            toastMessage = toast.message(language)
            viewModel.toast = nil
        }
        // 편집 중 동기화가 새 카테고리를 올려 임시 번호가 서버 번호로 바뀌었을 수 있다.
        .onChange(of: currentCategories.map(\.id)) {
            viewModel.categoriesDidChange()
        }
    }
}

// MARK: 헤더 · 달 줄 · 내용

private extension BudgetEditView {
    /// 카테고리 추가 화면 헤더와 같은 골격·규격. 저장이 꺼지면 `gray20` 이고 눌리지 않는다.
    var header: some View {
        HStack {
            Button {
                dismissKeyboard()
                viewModel.requestClose()
            } label: {
                CircleIconButton {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WoniColor.gray80)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WoniStrings.close(language))
            .accessibilityIdentifier("budgetEdit.close")
            .disabled(viewModel.isWriting)

            Spacer()

            Button(action: save) {
                Text(WoniStrings.save(language))
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.base10)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(viewModel.canSave ? WoniColor.terracotta100 : WoniColor.gray20)
                    .clipShape(Capsule())
                    .woniShadow(.shadow1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("budgetEdit.save")
            .disabled(!viewModel.canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(WoniColor.gray00)
        .overlay {
            Text(WoniStrings.budgetEditTitle(language))
                .woniFont(.body1)
                .foregroundStyle(WoniColor.gray100)
        }
    }

    /// 날짜 이동 줄(UI_GUIDE "날짜 이동 줄", 입력 화면 `DateRow` 와 같은 간격). 피커를 띄우지 않는다.
    /// 범위 끝 화살표는 `gray20`, 신원 없는 비회원은 화살표가 없다.
    var monthRow: some View {
        HStack(spacing: 14) {
            if viewModel.showsMonthArrows {
                monthArrow(
                    systemName: "chevron.left",
                    identifier: "budgetEdit.prev",
                    label: WoniStrings.previousMonth(language),
                    offset: -1,
                    isEnabled: viewModel.canGoPrevious
                )
            }

            Text(WoniDateFormat.monthTitle(
                year: viewModel.month.year,
                month: viewModel.month.month,
                language: language
            ))
            .woniFont(.body1)
            .foregroundStyle(WoniColor.gray100)
            .frame(minHeight: 44)
            .accessibilityIdentifier("budgetEdit.monthTitle")

            if viewModel.showsMonthArrows {
                monthArrow(
                    systemName: "chevron.right",
                    identifier: "budgetEdit.next",
                    label: WoniStrings.nextMonth(language),
                    offset: 1,
                    isEnabled: viewModel.canGoNext
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    func monthArrow(
        systemName: String,
        identifier: String,
        label: String,
        offset: Int,
        isEnabled: Bool
    ) -> some View {
        Button {
            dismissKeyboard()
            Task { await viewModel.go(by: offset) }
        } label: {
            Image(systemName: systemName)
                .foregroundStyle(isEnabled ? WoniColor.gray80 : WoniColor.gray20)
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// 읽는 중에는 입력 칸 자리에 로딩 원 하나(예산 탭 대기와 같은 모양, 문구 없음), 읽지 못하면 안내 한 줄.
    @ViewBuilder
    func content(categories: [Category]) -> some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 320)
                .accessibilityIdentifier("budgetEdit.loading")
        case .loadFailed:
            Text(WoniStrings.budgetEditMonthLoadFailed(language))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray60)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 320)
                .accessibilityIdentifier("budgetEdit.loadFailed")
        case .editing:
            BudgetEditForm(
                viewModel: viewModel,
                categories: categories,
                language: language,
                focusedField: $focusedField,
                dismissKeyboard: dismissKeyboard,
                onTapCurrency: { isCurrencyPickerPresented = true },
                onLimitExceeded: { toastMessage = BudgetEditToast.amountOverLimit.message(language) }
            )
        }
    }
}

// MARK: 오버레이 · 동작

private extension BudgetEditView {
    struct DialogText {
        let title: String
        let message: String
        let confirmTitle: String
        let identifier: String
    }

    var currencyPicker: some View {
        CurrencyPickerOverlay(
            selection: Binding(
                get: { viewModel.draft.currency.rawValue },
                set: { code in
                    guard let currency = CurrencyCode(rawValue: code) else {
                        return
                    }
                    viewModel.selectCurrency(currency)
                }
            ),
            isPresented: $isCurrencyPickerPresented,
            options: SelectableCurrency.entryPickerOptions,
            language: language,
            accentColor: WoniColor.terracotta100
        )
    }

    func confirmDialog(_ dialog: BudgetEditDialog) -> some View {
        let text = dialogText(dialog)
        return WoniConfirmDialog(
            title: text.title,
            message: text.message,
            confirmTitle: text.confirmTitle,
            cancelTitle: WoniStrings.cancel(language),
            identifier: text.identifier,
            isBusy: viewModel.isWriting,
            onConfirm: {
                Task { await viewModel.confirmDialog() }
            },
            onCancel: { viewModel.cancelDialog() }
        )
    }

    /// 문구 정본은 시안 ⑯. 불러오기 확인 창은 제목만 있다.
    func dialogText(_ dialog: BudgetEditDialog) -> DialogText {
        switch dialog {
        case .changeCurrency:
            DialogText(
                title: WoniStrings.budgetEditChangeCurrencyTitle(language),
                message: WoniStrings.budgetEditChangeCurrencyMessage(language),
                confirmTitle: WoniStrings.budgetEditChange(language),
                identifier: "budgetEdit.dialog.currency"
            )
        case .replaceWithPrevious:
            DialogText(
                title: WoniStrings.budgetEditReplaceWithPreviousTitle(language),
                message: "",
                confirmTitle: WoniStrings.budgetEditChange(language),
                identifier: "budgetEdit.dialog.previous"
            )
        case .leave:
            DialogText(
                title: WoniStrings.budgetEditLeaveTitle(language),
                message: WoniStrings.budgetEditLeaveMessage(language),
                confirmTitle: WoniStrings.budgetEditLeave(language),
                identifier: "budgetEdit.dialog.leave"
            )
        case .deleteMonth:
            DialogText(
                title: WoniStrings.budgetEditDeleteDialogTitle(month: viewModel.month.month, language: language),
                message: WoniStrings.budgetEditDeleteDialogMessage(language),
                confirmTitle: WoniStrings.deleteConfirmationDelete(language),
                identifier: "budgetEdit.dialog.delete"
            )
        case .clearAll:
            DialogText(
                title: language == .ko ? "입력한 금액을 모두 지울까요?" : "Clear all the amounts you entered?",
                message: "",
                confirmTitle: language == .ko ? "지우기" : "Clear",
                identifier: "budgetEdit.dialog.clearAll"
            )
        }
    }

    /// 저장은 키보드를 먼저 내리지 않는다 — 내리면 전체 칸 입력 끝의 합계 맞춤이 먼저 돌아, 저장이 맞춘 전체를 보여 주고
    /// 멈추는 대신 그대로 저장한다(`BudgetEditViewModel.save()`). 저장이 끝난 뒤 내려 맞춘 전체를 칸이 다시 그리게 한다.
    func save() {
        Task {
            await viewModel.save()
            dismissKeyboard()
        }
    }

    /// 포커스 중인 칸은 바깥 값으로 다시 그리지 않는다(`BudgetAmountTextField`) — 불러온 값·옮긴 달 값 대신 옛 글자가 남고
    /// 이어 치는 키가 그 글자로 값을 덮는다. 칸 값을 바꿀 수 있는 동작 앞에서 먼저 내린다(임시 결정 2026-10-03 #26).
    /// 포커스 상태도 여기서 확정한다 — 응답자 체인 해제에만 기대지 않는다(`AmountInputSection` 통화 버튼과 같다).
    func dismissKeyboard() {
        focusedField = nil
        hideKeyboard()
    }
}
