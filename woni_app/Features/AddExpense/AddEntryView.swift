import SwiftUI

// swiftlint:disable file_length

struct AddEntryView: View {
    @Environment(AppLanguageStore.self) private var languageStore

    @State private var viewModel: AddExpenseViewModel
    @State private var isCalendarExpanded = false
    @State private var showCurrencyPicker = false
    @State private var showYearMonthPicker = false
    @State private var showDeleteConfirmation = false
    @State private var showTransactionNotFoundAlert = false
    @State private var showDeleteErrorAlert = false

    let onClose: () -> Void
    let onSaved: () -> Void

    init(
        viewModel: AddExpenseViewModel,
        onClose: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
        self.onSaved = onSaved
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
                                date: viewModel.date,
                                language: language,
                                isCalendarExpanded: isCalendarExpanded,
                                onDateChange: { viewModel.updateDate($0) },
                                onTapTitle: {
                                    hideKeyboard()
                                    if isCalendarExpanded {
                                        showYearMonthPicker = true
                                    } else {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            isCalendarExpanded = true
                                        }
                                    }
                                }
                            )

                            if isCalendarExpanded {
                                VStack(spacing: 0) {
                                    InlineCalendarView(
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
                                krwToForeignRate: viewModel.krwToForeignRate,
                                convertedBaseAmount: viewModel.convertedBaseAmount,
                                isRateStale: viewModel.isCurrentRateStale,
                                isRateEstimated: viewModel.isCurrentRateEstimated,
                                language: language,
                                accent: accent,
                                onTapCurrency: { showCurrencyPicker = true }
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
                    initialYear: WoniDateFormat.defaultCalendar.component(.year, from: viewModel.date),
                    initialMonth: WoniDateFormat.defaultCalendar.component(.month, from: viewModel.date),
                    language: language,
                    onSave: { year, month in
                        viewModel.updateDate(dateByUpdating(year: year, month: month))
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
                DeleteEntryDialog(
                    language: language,
                    isDeleting: viewModel.isDeleting,
                    onDelete: confirmDelete,
                    onCancel: { showDeleteConfirmation = false }
                )
                .zIndex(10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
        .alert(
            WoniStrings.transactionNotFoundTitle(language),
            isPresented: $showTransactionNotFoundAlert
        ) {
            Button(WoniStrings.confirmOK(language)) {
                onSaved()
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

            Spacer()

            Button(action: save) {
                Text(isEditing ? WoniStrings.editEntryTitle(language) : WoniStrings.save(language))
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.base10)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(canSubmit ? headerActionColor : WoniColor.gray20)
                    .clipShape(Capsule())
                    .woniShadow(.shadow1)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(WoniColor.gray00)
    }

    var headerActionColor: Color {
        isEditing ? WoniColor.olive100 : accentColor
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
                onSaved()
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
                onSaved()
            } else if viewModel.deleteError != nil {
                showDeleteErrorAlert = true
            }
        }
    }

    func dateByUpdating(year: Int, month: Int) -> Date {
        let calendar = WoniDateFormat.defaultCalendar
        let day = calendar.component(.day, from: viewModel.date)
        guard let firstOfMonth = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: 1
        )),
            let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else {
            return viewModel.date
        }
        let clampedDay = min(day, range.count)
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: clampedDay
        )) ?? firstOfMonth
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

private struct DeleteEntryDialog: View {
    let language: AppLanguage
    let isDeleting: Bool
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            WoniColor.gray100.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(WoniStrings.deleteConfirmationTitle(language))
                        .woniFont(.body1)
                        .foregroundStyle(WoniColor.gray100)
                    Text(WoniStrings.deleteConfirmationMessage(language))
                        .woniFont(.body3)
                        .foregroundStyle(WoniColor.gray60)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Rectangle()
                    .fill(WoniColor.base20)
                    .frame(height: 1)

                HStack(spacing: 8) {
                    dialogButton(
                        WoniStrings.deleteConfirmationDelete(language),
                        isPrimary: true,
                        action: onDelete
                    )
                    .disabled(isDeleting)

                    dialogButton(
                        WoniStrings.deleteConfirmationCancel(language),
                        isPrimary: false,
                        action: onCancel
                    )
                    .disabled(isDeleting)
                }
                .padding(16)
            }
            .frame(maxWidth: 360)
            .background(WoniColor.gray00)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .woniShadow(.shadow1)
            .padding(.horizontal, 16)
        }
    }

    private func dialogButton(
        _ title: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .woniFont(isPrimary ? .body2 : .body3)
                .foregroundStyle(isPrimary ? WoniColor.base10 : WoniColor.gray60)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isPrimary ? WoniColor.terracotta100 : WoniColor.gray00)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(
                        isPrimary ? WoniColor.terracotta100 : WoniColor.base20,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
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
        AddEntryView(viewModel: viewModel, onClose: {}, onSaved: {})
            .environment(AppLanguageStore(systemLocale: Locale(identifier: "ko_KR")))
    } else {
        Text("Preview unavailable")
    }
}
