import SwiftUI

struct MainView: View {
    @State private var viewModel: MainViewModel
    @State private var isYearMonthPickerPresented = false
    let language: AppLanguage
    let onAdd: (_ defaultDate: Date) -> Void
    let onOpenSettings: () -> Void

    init(
        viewModel: MainViewModel,
        language: AppLanguage,
        onAdd: @escaping (_ defaultDate: Date) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.language = language
        self.onAdd = onAdd
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                MonthHeaderView(
                    monthTitle: viewModel.monthTitle,
                    language: language,
                    onOpenMonthPicker: {
                        isYearMonthPickerPresented = true
                    },
                    onOpenSettings: onOpenSettings
                )
                .zIndex(1)

                TotalsSummaryView(items: viewModel.summaryItems)

                calendarContent

                ScrollView {
                    HistoryListView(
                        rows: viewModel.historyRows,
                        conversionWarningText: viewModel.conversionWarningText
                    )
                    .padding(.bottom, 76)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WoniColor.base10)
            }
            .background(WoniColor.base10)

            addButton
                .padding(16)

            if isYearMonthPickerPresented {
                YearMonthPickerOverlay(
                    initialYear: viewModel.selectedMonth.year,
                    initialMonth: viewModel.selectedMonth.month,
                    language: language,
                    onSave: { year, month in
                        isYearMonthPickerPresented = false
                        Task {
                            await viewModel.setMonth(year: year, month: month)
                        }
                    },
                    onCancel: {
                        isYearMonthPickerPresented = false
                    }
                )
                .zIndex(2)
            }
        }
        .background(WoniColor.base10)
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        if viewModel.isLoading {
            ProgressView()
                .tint(WoniColor.olive100)
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .background(WoniColor.gray00)
        } else if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.terracotta100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(WoniColor.gray00)
        } else {
            MonthCalendarGrid(
                days: viewModel.calendarDays,
                language: language,
                formatAmount: viewModel.formatBaseAmount,
                onSelect: { day in
                    viewModel.selectDay(day)
                },
                handleSwipe: { horizontal, vertical in
                    Task {
                        await viewModel.handleSwipe(horizontal: horizontal, vertical: vertical)
                    }
                }
            )
        }
    }

    private var addButton: some View {
        Button {
            onAdd(viewModel.defaultEntryDate)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WoniColor.base10)
                .frame(width: 52, height: 52)
                .background(WoniColor.terracotta100)
                .clipShape(Circle())
                .woniShadow(.shadow1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WoniStrings.addTransactionA11y(language))
    }
}

#Preview {
    if let dependencies = try? AppDependencyFactory.makeSeedDependencies(inMemory: true) {
        MainView(
            viewModel: MainViewModel(
                transactionRepository: dependencies.transactionRepository,
                catalogProvider: dependencies.catalogProvider,
                rateProvider: dependencies.mainRateProvider
            ),
            language: .ko,
            onAdd: { _ in },
            onOpenSettings: {}
        )
    } else {
        Text("Preview unavailable")
    }
}
