import SwiftUI

/// 보고 있는 달의 기준점. 월을 더할 때 말일이 짧은 달에 걸려 날짜가 밀리지 않도록 1일로 맞춘다.
/// `init`에서도 써야 해 파일 스코프에 둔다.
private func firstOfMonth(_ date: Date) -> Date {
    let calendar = WoniDateFormat.defaultCalendar
    return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
}

struct AddEntryView: View {
    @Environment(AppLanguageStore.self) private var languageStore

    @State private var viewModel: AddExpenseViewModel
    /// 인라인 달력이 보고 있는 달. 선택 날짜(`viewModel.date`)와 분리해야 월을 옮겨도
    /// 선택 표시가 따라다니지 않는다.
    @State private var calendarMonth: Date
    @State private var isCalendarExpanded = false
    @State private var showCurrencyPicker = false
    @State private var showYearMonthPicker = false
    @State private var showDeleteConfirmation = false
    @State private var showTransactionNotFoundAlert = false
    @State private var showDeleteErrorAlert = false
    @State private var toastMessage: String?

    let onClose: () -> Void
    let onFinish: (_ didDelete: Bool) -> Void

    init(
        viewModel: AddExpenseViewModel,
        onClose: @escaping () -> Void,
        onFinish: @escaping (_ didDelete: Bool) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        _calendarMonth = State(initialValue: firstOfMonth(viewModel.date))
        self.onClose = onClose
        self.onFinish = onFinish
    }

    private var accent: ChipButton.ChipAccent {
        viewModel.selectedTab == .expense ? .terracotta : .olive
    }

    private var accentColor: Color {
        viewModel.selectedTab == .expense ? WoniColor.terracotta100 : WoniColor.olive100
    }

    private var language: AppLanguage {
        languageStore.language
    }

    private var isEditing: Bool {
        if case .edit = viewModel.mode {
            return true
        }
        return false
    }

    var body: some View {
        NavigationStack {
            rootScreen
                .navigationDestination(for: EntryRoute.self) { route in
                    // 라우트 골격만 먼저 둔다 — 목적지 본체는 관리·추가 화면 구현에서 채운다.
                    switch route {
                    case .manage:
                        EmptyView()
                    case .add:
                        EmptyView()
                    }
                }
        }
    }

    /// cover 루트 화면. 오버레이(픽커·달력·다이얼로그)는 push 화면과 섞이지 않도록
    /// 이 ZStack 안에 남긴다.
    private var rootScreen: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                    .zIndex(1)
                tabBar

                saveStatusContent

                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            DateRow(
                                // 달력이 펼쳐진 동안 타이틀과 화살표는 보고 있는 달을 다룬다.
                                date: isCalendarExpanded ? calendarMonth : viewModel.date,
                                language: language,
                                isCalendarExpanded: isCalendarExpanded,
                                onDateChange: { newDate in
                                    if isCalendarExpanded {
                                        calendarMonth = firstOfMonth(newDate)
                                    } else {
                                        viewModel.updateDate(newDate)
                                    }
                                },
                                onTapTitle: {
                                    hideKeyboard()
                                    if isCalendarExpanded {
                                        showYearMonthPicker = true
                                    } else {
                                        calendarMonth = firstOfMonth(viewModel.date)
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            isCalendarExpanded = true
                                        }
                                    }
                                }
                            )

                            if isCalendarExpanded {
                                VStack(spacing: 0) {
                                    InlineCalendarView(
                                        displayedMonth: calendarMonth,
                                        selectedDate: viewModel.date,
                                        language: language,
                                        accentColor: accentColor,
                                        onSelectDate: { viewModel.updateDate($0) },
                                        onSelect: {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                isCalendarExpanded = false
                                            }
                                        }
                                    )
                                    Rectangle().fill(WoniColor.base20).frame(height: 1)
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }

                        VStack(spacing: 0) {
                            AmountInputSection(
                                amount: $viewModel.amount,
                                currencyCode: viewModel.selectedCurrency.rawValue,
                                ratePreview: viewModel.baseRatePreview,
                                isRateStale: viewModel.isCurrentRateStale,
                                isRateEstimated: viewModel.isCurrentRateEstimated,
                                language: language,
                                autoFocusAmount: !isEditing,
                                accent: accent,
                                onTapCurrency: { showCurrencyPicker = true },
                                onMaximumAmountExceeded: {
                                    toastMessage = WoniStrings.amountOverLimitToast(
                                        language,
                                        limit: AddExpenseViewModel.maximumAmountLabel
                                    )
                                }
                            )

                            catalogContent

                            MemoField(
                                title: WoniStrings.memoFieldTitle(language),
                                placeholder: WoniStrings.memoPlaceholder(language),
                                text: $viewModel.memo
                            )

                            if isEditing {
                                deleteButton
                            }
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                hideKeyboard()
                                if isCalendarExpanded {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        isCalendarExpanded = false
                                    }
                                }
                            }
                        )
                    }
                    .padding(.bottom, 24)
                }
                .background(WoniColor.base10)
                .scrollDismissesKeyboard(.interactively)
            }

            if showYearMonthPicker {
                YearMonthPickerOverlay(
                    initialYear: WoniDateFormat.defaultCalendar.component(.year, from: calendarMonth),
                    initialMonth: WoniDateFormat.defaultCalendar.component(.month, from: calendarMonth),
                    language: language,
                    onSave: { year, month in
                        calendarMonth = monthDate(year: year, month: month)
                        showYearMonthPicker = false
                    },
                    onCancel: { showYearMonthPicker = false }
                )
            }

            if showCurrencyPicker {
                CurrencyPickerOverlay(
                    selection: Binding(
                        get: { viewModel.selectedCurrency.rawValue },
                        set: { code in
                            guard let currency = SelectableCurrency(rawValue: code) else {
                                return
                            }
                            viewModel.updateCurrency(currency)
                        }
                    ),
                    isPresented: $showCurrencyPicker,
                    options: viewModel.currencyOptions,
                    language: language,
                    accentColor: accentColor
                )
            }

            if showDeleteConfirmation {
                WoniConfirmDialog(
                    title: WoniStrings.deleteConfirmationTitle(language),
                    message: WoniStrings.deleteConfirmationMessage(language),
                    confirmTitle: WoniStrings.deleteConfirmationDelete(language),
                    cancelTitle: WoniStrings.deleteConfirmationCancel(language),
                    identifier: "entry.deleteDialog",
                    isBusy: viewModel.isDeleting,
                    onConfirm: confirmDelete,
                    onCancel: { showDeleteConfirmation = false }
                )
                .zIndex(10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .woniToast($toastMessage, showsCheckmark: false)
        .task {
            await viewModel.load()
        }
        // initial: true — 수정 진입 직후 load가 끝나며 판정이 켜지는 첫 전이도 놓치지 않고,
        // 이후 store 목록 변경(관리 화면에서 삭제)에도 같은 토스트를 재발화한다.
        .onChange(of: viewModel.isSelectedCategoryMissing, initial: true) { _, isMissing in
            if isMissing {
                toastMessage = WoniStrings.categoryDeletedReselectToast(language)
            }
        }
        .alert(
            WoniStrings.transactionNotFoundTitle(language),
            isPresented: $showTransactionNotFoundAlert
        ) {
            Button(WoniStrings.confirmOK(language)) {
                onFinish(false)
            }
        } message: {
            Text(WoniStrings.transactionNotFoundMessage(language))
        }
        .alert(
            WoniStrings.deleteFailedTitle(language),
            isPresented: $showDeleteErrorAlert
        ) {
            Button(WoniStrings.confirmOK(language), role: .cancel) {}
        } message: {
            Text(WoniStrings.deleteFailedMessage(language))
        }
    }
}

private extension AddEntryView {
    var header: some View {
        HStack {
            Button(action: onClose) {
                CircleIconButton {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WoniColor.gray80)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WoniStrings.close(language))
            .accessibilityIdentifier("entry.close")

            Spacer()

            Button(action: save) {
                Text(isEditing ? WoniStrings.editEntryTitle(language) : WoniStrings.save(language))
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.base10)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(canSubmit ? accentColor : WoniColor.gray20)
                    .clipShape(Capsule())
                    .woniShadow(.shadow1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("entry.submit")
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(WoniColor.gray00)
    }

    var canSubmit: Bool {
        viewModel.canSave && !viewModel.isSaving && !viewModel.isDeleting
    }

    var deleteButton: some View {
        Button {
            hideKeyboard()
            showDeleteConfirmation = true
        } label: {
            Text(WoniStrings.deleteEntry(language))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.terracotta100)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(WoniColor.base10)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(WoniColor.terracotta100, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("entry.delete")
        .disabled(viewModel.isDeleting || viewModel.isSaving)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: WoniStrings.tabExpense(language), type: .expense, activeColor: WoniColor.terracotta100)
            tabButton(title: WoniStrings.tabIncome(language), type: .income, activeColor: WoniColor.olive100)
        }
        .background(WoniColor.gray00)
    }

    func tabButton(title: String, type: EntryType, activeColor: Color) -> some View {
        Button {
            viewModel.selectedTab = type
        } label: {
            Text(title)
                .woniFont(.body2)
                .foregroundStyle(viewModel.selectedTab == type ? activeColor : WoniColor.gray40)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(viewModel.selectedTab == type ? activeColor : WoniColor.base20)
                        .frame(height: viewModel.selectedTab == type ? 2 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(type == .expense ? "entry.tab.expense" : "entry.tab.income")
        .accessibilityAddTraits(viewModel.selectedTab == type ? .isSelected : [])
    }

    @ViewBuilder
    var saveStatusContent: some View {
        if let saveError = viewModel.saveError {
            Text(saveErrorMessage(saveError))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.terracotta100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(WoniColor.base10)
        }
    }

    @ViewBuilder
    var catalogContent: some View {
        if viewModel.isLoadingCatalog {
            CatalogPlaceholderSection(title: WoniStrings.category(language))
            CatalogPlaceholderSection(title: WoniStrings.asset(language))
        } else if let catalogError = viewModel.catalogError {
            CatalogErrorSection(
                message: catalogError,
                retryTitle: WoniStrings.retry(language),
                accent: accent
            ) {
                Task {
                    await viewModel.load()
                }
            }
        } else {
            ChipSection(
                title: WoniStrings.category(language),
                items: categoryChipItems,
                accent: accent,
                identifierPrefix: "entry.category",
                onSelect: { id in
                    guard let category = viewModel.visibleCategories.first(where: { $0.id == id }) else {
                        return
                    }
                    viewModel.selectCategory(category)
                }
            )

            ChipSection(
                title: WoniStrings.asset(language),
                items: assetChipItems,
                accent: accent,
                identifierPrefix: "entry.asset",
                onSelect: { id in
                    guard let asset = viewModel.assets.first(where: { $0.id == id }) else {
                        return
                    }
                    viewModel.selectAsset(asset)
                }
            )
        }
    }

    var categoryChipItems: [EntryChipItem] {
        viewModel.visibleCategories.map { category in
            EntryChipItem(
                id: category.id,
                label: language == .ko ? category.displayNameKo : category.displayNameEn,
                icon: category.icon,
                isSelected: category.id == viewModel.selectedCategoryId
            )
        }
    }

    var assetChipItems: [EntryChipItem] {
        viewModel.assets.map { asset in
            EntryChipItem(
                id: asset.id,
                label: language == .ko ? asset.displayNameKo : asset.displayNameEn,
                icon: nil,
                isSelected: asset.id == viewModel.selectedAssetId
            )
        }
    }

    func save() {
        guard canSubmit else {
            return
        }

        Task {
            await viewModel.save()
            if viewModel.saveSucceeded {
                onFinish(false)
            } else if viewModel.saveError == .transactionNotFound {
                showTransactionNotFoundAlert = true
            }
        }
    }

    func confirmDelete() {
        Task {
            let didDelete = await viewModel.deleteEntry()
            showDeleteConfirmation = false
            if didDelete {
                onFinish(true)
            } else if viewModel.deleteError != nil {
                showDeleteErrorAlert = true
            }
        }
    }

    func monthDate(year: Int, month: Int) -> Date {
        let calendar = WoniDateFormat.defaultCalendar
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: 1
        )) ?? calendarMonth
    }

    func saveErrorMessage(_ error: AddExpenseSaveError) -> String {
        switch error {
        case .missingSelection:
            WoniStrings.errMissingSelection(language)
        case .invalidAmount:
            WoniStrings.errInvalidAmount(language)
        case .memoTooLong:
            WoniStrings.errMemoTooLong(language)
        case .invalidFutureDate:
            WoniStrings.errFutureDate(language)
        case .transactionNotFound:
            WoniStrings.transactionNotFoundMessage(language)
        case let .system(message):
            message
        }
    }
}

private struct CatalogPlaceholderSection: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray100)
                .padding(.vertical, 12)

            FlowLayout(spacing: 8) {
                ForEach(0 ..< 5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 18)
                        .fill(WoniColor.gray00)
                        .frame(width: index.isMultiple(of: 2) ? 92 : 128, height: 36)
                        .overlay {
                            Capsule().stroke(WoniColor.gray20, lineWidth: 1)
                        }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
    }
}

private struct CatalogErrorSection: View {
    let message: String
    let retryTitle: String
    let accent: ChipButton.ChipAccent
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray80)

            Button(action: onRetry) {
                Text(retryTitle)
                    .woniFont(.body3)
                    .foregroundStyle(accent.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(accent.background)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().stroke(accent.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    if let viewModel = try? AppDependencyFactory.makeAddExpenseViewModel(inMemory: true) {
        AddEntryView(viewModel: viewModel, onClose: {}, onFinish: { _ in })
            .environment(AppLanguageStore(systemLocale: Locale(identifier: "ko_KR")))
    } else {
        Text("Preview unavailable")
    }
}
