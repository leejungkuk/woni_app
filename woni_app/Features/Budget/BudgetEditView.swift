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
    /// 결제수단 칸 입력 중 스크롤 맞춤의 재료 — 결제수단 줄·섹션 끝 프레임(편집 본문 기준) · 스크롤 영역 프레임(window 기준) ·
    /// 떠 있는 키보드의 최종 프레임(알림의 `keyboardFrameEndUserInfoKey`, 내려가면 nil).
    @State private var scrollFrames: [BudgetEditKeyboardScroll.ScrollID: CGRect] = [:]
    @State private var scrollViewFrame: CGRect = .zero
    @State private var keyboardFrame: CGRect?

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

                scrollBody(categories: currentCategories)
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
                onLimitExceeded: { toastMessage = BudgetEditToast.amountOverLimit.message(language) },
                onScrollFrame: { scrollID, frame in scrollFrames[scrollID] = frame }
            )
        }
    }
}

// MARK: 본문 스크롤 · 결제수단 칸 키보드 맞춤

private extension BudgetEditView {
    /// 결제수단 칸에 입력 중이면 그 칸부터 섹션 맨 아래 줄까지 키보드 위에 보이게 맞춘다(UI_GUIDE "결제수단 칸에 입력 중이면 …").
    /// 맞추는 때: 키보드가 올라올 때 · 결제수단 칸으로 포커스가 옮겨 올 때 · 섹션 맨 아래 줄이 바뀔 때(경고 줄 ↔ 나눌 수 있는 금액).
    /// 전체·카테고리 칸과 포커스가 빠질 때는 손대지 않는다 — iOS 기본 동작 그대로다.
    func scrollBody(categories: [Category]) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    monthRow
                    content(categories: categories)
                }
                .padding(.bottom, 24)
                .coordinateSpace(.named(BudgetEditKeyboardScroll.contentSpace))
                // 키보드 내리기는 입력 화면(`AddEntryView`)과 같다 — 빈 곳을 누르거나 스크롤하면 내린다.
                // 코드로 옮기는 스크롤(맞춤)은 끌기가 아니라 키보드를 내리지 않는다.
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { hideKeyboard() }
                )
            }
            .scrollDismissesKeyboard(.interactively)
            // 보이는 높이는 이 프레임과 키보드 최종 프레임으로 센다(`BudgetEditKeyboardScroll.visibleHeight`). SwiftUI 가 이 영역을
            // 키보드만큼 줄이는 때는 키보드 알림과 순서가 정해져 있지 않아, 이 영역 높이만으로 판단하지 않는다.
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { frame in
                scrollViewFrame = frame
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) {
                let endFrame = $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
                keyboardFrame = endFrame?.cgRectValue
                alignPaymentSection(scrollProxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardFrame = nil
            }
            .onChange(of: focusedField) {
                alignPaymentSection(scrollProxy)
            }
            .onChange(of: viewModel.draft.paymentExcess != nil) {
                alignPaymentSection(scrollProxy)
            }
        }
    }

    /// 키보드가 다 올라온 뒤의 높이로 판단한다 — 알림에 실린 키보드 최종 프레임으로 세서, 올라오는 도중이든 SwiftUI 가 스크롤
    /// 영역을 아직 안 줄였든 같은 값이다. 처음 포커스는 `keyboardWillShow` 에서 맞춘다: `keyboardDidShow` 까지 기다리면 iOS 가
    /// 그 직후 입력 중인 칸만 보이게 끄는 스크롤과 겹쳐 맞춤이 덮인다(2026-10-04 실측). 키보드가 이미 떠 있으면 바로 맞춘다.
    /// 한 박자 늦춰 레이아웃이 끝난 프레임으로 판단한다 — 섹션 맨 아래 줄이 바뀐 직후에는 섹션이 아직 옛 높이다.
    func alignPaymentSection(_ scrollProxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            guard let keyboardFrame,
                  case let .payment(group)? = focusedField,
                  let field = scrollFrames[.paymentRow(group)],
                  let section = scrollFrames[.paymentSectionEnd]
            else {
                return
            }
            let alignment = BudgetEditKeyboardScroll.alignment(
                fieldTop: field.minY,
                sectionBottom: section.maxY,
                visibleHeight: BudgetEditKeyboardScroll.visibleHeight(
                    scrollFrame: scrollViewFrame,
                    keyboardFrame: keyboardFrame
                )
            )
            let target = BudgetEditKeyboardScroll.target(
                for: alignment,
                field: BudgetEditKeyboardScroll.ScrollID.paymentRow(group),
                sectionEnd: .paymentSectionEnd
            )
            scrollProxy.scrollTo(target.id, anchor: target.anchor)
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
                title: WoniStrings.budgetEditClearAllTitle(language),
                message: "",
                confirmTitle: WoniStrings.budgetEditClear(language),
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
