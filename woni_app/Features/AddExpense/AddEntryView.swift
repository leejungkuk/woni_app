import SwiftUI

struct AddEntryView: View {
    @Environment(AppLanguageStore.self) private var languageStore

    @State private var viewModel: AddExpenseViewModel
    @State private var isCalendarExpanded = false
    @State private var showCurrencyPicker = false
    @State private var showYearMonthPicker = false

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
                    options: SelectableCurrency.entryPickerOptions,
                    language: language,
                    accentColor: accentColor
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
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
                Text(WoniStrings.save(language))
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.base10)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(viewModel.canSave && !viewModel.isSaving ? accentColor : WoniColor.gray20)
                    .clipShape(Capsule())
                    .woniShadow(.shadow1)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSave || viewModel.isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(WoniColor.gray00)
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
        guard viewModel.canSave, !viewModel.isSaving else {
            return
        }

        Task {
            await viewModel.save()
            if viewModel.saveSucceeded {
                onSaved()
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
        AddEntryView(viewModel: viewModel, onClose: {}, onSaved: {})
            .environment(AppLanguageStore(systemLocale: Locale(identifier: "ko_KR")))
    } else {
        Text("Preview unavailable")
    }
}
