//
//  MonthReportView.swift
//  woni_app
//

import SwiftUI

struct MonthReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MonthReportViewModel
    @State private var foregroundReloadCoordinator = ForegroundMainReloadCoordinator()

    let ledgerChanges: () -> AsyncStream<Void>
    let ledgerRevision: () -> Int
    let foregroundActivationSignal: ForegroundActivationSignal
    let onSelectCategory: (Int) -> Void

    init(
        viewModel: MonthReportViewModel,
        ledgerChanges: @escaping () -> AsyncStream<Void>,
        ledgerRevision: @escaping () -> Int,
        foregroundActivationSignal: ForegroundActivationSignal,
        onSelectCategory: @escaping (Int) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.ledgerChanges = ledgerChanges
        self.ledgerRevision = ledgerRevision
        self.foregroundActivationSignal = foregroundActivationSignal
        self.onSelectCategory = onSelectCategory
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ReportSummaryTabs(
                items: viewModel.summaryItems,
                selected: viewModel.selectedKind,
                onSelect: viewModel.setKind
            )
            fixedChart
            reportContent
        }
        .horizontalPaging(onPage: changeMonth)
        .background(WoniColor.base10)
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled()
        .task {
            await viewModel.observeLedgerChanges(
                ledgerChanges(),
                revision: ledgerRevision
            )
        }
        .onChange(of: foregroundActivationSignal.revision) { _, revision in
            Task {
                await foregroundReloadCoordinator.handle(
                    revision: revision,
                    baseCurrency: viewModel.baseCurrency,
                    reload: { await viewModel.reload() }
                )
            }
        }
    }
}

private extension MonthReportView {
    static let scrollTopID = "report.scroll.top"

    var header: some View {
        ZStack {
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
                .accessibilityLabel(WoniStrings.back(viewModel.language))
                .accessibilityIdentifier("report.back")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 0) {
                monthButton(
                    systemName: "chevron.left",
                    identifier: "report.month.prev",
                    label: WoniStrings.previousMonth(viewModel.language),
                    offset: -1
                )

                Text(viewModel.monthTitle)
                    .woniFont(.body1)
                    .foregroundStyle(WoniColor.gray100)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("report.monthTitle")

                monthButton(
                    systemName: "chevron.right",
                    identifier: "report.month.next",
                    label: WoniStrings.nextMonth(viewModel.language),
                    offset: 1
                )
            }
            .padding(.horizontal, 72)
        }
        .frame(height: 52)
        .background(WoniColor.gray00)
    }

    func monthButton(
        systemName: String,
        identifier: String,
        label: String,
        offset: Int
    ) -> some View {
        Button {
            changeMonth(by: offset)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WoniColor.gray80)
                .frame(width: 32, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    var fixedChart: some View {
        if !viewModel.isLoading, viewModel.errorMessage == nil, viewModel.summary != .empty {
            switch viewModel.selectedKind {
            case .expense where viewModel.summary.expense != 0,
                 .income where viewModel.summary.income != 0:
                DonutChartView(
                    slices: viewModel.donutSlices,
                    items: viewModel.categoryItems,
                    modeTitle: selectedSummaryItem?.title ?? "",
                    modeTitleColor: viewModel.selectedKind == .expense
                        ? WoniColor.terracotta110
                        : WoniColor.olive110,
                    amountText: selectedSummaryItem?.amountText ?? "",
                    accessibilitySummary: donutAccessibilitySummary
                )
                .padding(.top, 20)
                .frame(maxWidth: .infinity)
                .background(WoniColor.gray00)
            case .total:
                ReportCompareBars(
                    items: viewModel.summaryItems,
                    summary: viewModel.summary,
                    remainingTitle: WoniStrings.reportRemaining(viewModel.language)
                )
            case .expense, .income:
                EmptyView()
            }
        }
    }

    var reportContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.scrollTopID)

                    LazyVStack(spacing: 0) {
                        content

                        if let warning = viewModel.conversionWarningText {
                            conversionWarning(warning)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .onChange(of: viewModel.selectedKind) { _, _ in
                proxy.scrollTo(Self.scrollTopID, anchor: .top)
            }
            .onChange(of: viewModel.selectedMonth) { _, _ in
                proxy.scrollTo(Self.scrollTopID, anchor: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WoniColor.base10)
    }

    @ViewBuilder
    var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .tint(WoniColor.olive100)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
        } else if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.terracotta100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        } else if viewModel.summary.expense == 0, viewModel.summary.income == 0 {
            emptyMonth
        } else {
            switch viewModel.selectedKind {
            case .expense where viewModel.summary.expense == 0:
                emptyTab(kind: .expense)
            case .income where viewModel.summary.income == 0:
                emptyTab(kind: .income)
            case .expense, .income:
                categoryContent
            case .total:
                totalContent
            }
        }
    }

    var emptyMonth: some View {
        Text(WoniStrings.reportMonthEmpty(viewModel.language))
            .woniFont(.body2)
            .foregroundStyle(WoniColor.gray60)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280)
            .accessibilityIdentifier("report.empty.month")
    }

    func emptyTab(kind: MainSummaryItem.Kind) -> some View {
        VStack(spacing: 8) {
            Text(WoniStrings.reportTabEmptyTitle(kind, language: viewModel.language))
                .woniFont(.body2)
                .foregroundStyle(WoniColor.gray100)
            Text(WoniStrings.reportTabEmptyHint(kind, language: viewModel.language))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray60)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 280)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("report.empty.tab")
    }

    var categoryContent: some View {
        ReportCategoryListView(
            items: viewModel.categoryItems,
            categoryName: viewModel.categoryDisplayName,
            formatAmount: viewModel.formatBaseAmount,
            onSelect: onSelectCategory
        )
        .padding(.top, 16)
    }

    var totalContent: some View {
        VStack(spacing: 0) {
            totalSection(kind: .expense, items: viewModel.expenseCategoryItems)
            totalSection(kind: .income, items: viewModel.incomeCategoryItems)
        }
    }

    func totalSection(
        kind: MainSummaryItem.Kind,
        items: [ReportCategoryItem]
    ) -> some View {
        let item = summaryItem(kind: kind)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item?.title ?? "")
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.gray100)

                Spacer(minLength: 8)

                Text(item?.amountText ?? "")
                    .woniFont(.body2)
                    .foregroundStyle(
                        item?.tone.amountTone.foregroundColor
                            ?? WoniColor.gray100
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .padding(.horizontal, 16)

            if items.isEmpty {
                Text(WoniStrings.reportTabEmptyTitle(kind, language: viewModel.language))
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray60)
                    .padding(.horizontal, 16)
            } else {
                ReportCategoryListView(
                    items: items,
                    categoryName: viewModel.categoryDisplayName,
                    formatAmount: viewModel.formatBaseAmount,
                    onSelect: onSelectCategory
                )
            }
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var selectedSummaryItem: MainSummaryItem? {
        summaryItem(kind: viewModel.selectedKind)
    }

    func summaryItem(kind: MainSummaryItem.Kind) -> MainSummaryItem? {
        viewModel.summaryItems.first { $0.kind == kind }
    }

    var donutAccessibilitySummary: String {
        guard let leading = viewModel.categoryItems.first else {
            return ""
        }
        let amount = selectedSummaryItem?.amountText ?? ""
        return WoniStrings.reportDonutAccessibility(
            kind: viewModel.selectedKind,
            total: (amount, viewModel.baseCurrency),
            leading: (
                viewModel.categoryDisplayName(categoryID: leading.categoryID),
                leading.percent
            ),
            moreCategoryCount: viewModel.categoryItems.count - 1,
            language: viewModel.language
        )
    }

    func conversionWarning(_ text: String) -> some View {
        Text(text)
            .woniFont(.small1)
            .foregroundStyle(WoniColor.terracotta110)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(WoniColor.terracotta10)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("report.conversionWarning")
    }

    func changeMonth(by offset: Int) {
        viewModel.setMonth(
            viewModel.selectedMonth.addingMonths(offset, calendar: viewModel.calendar)
        )
    }
}

#Preview("Month report 393pt") {
    if let dependencies = try? AppDependencyFactory.makeSeedDependencies(inMemory: true) {
        let viewModel = MonthReportViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            customCategoryStore: dependencies.customCategoryStore,
            rateProvider: dependencies.mainRateProvider,
            baseRateResolver: BaseRateResolver(
                cache: dependencies.exchangeRateCache,
                seedRateProvider: dependencies.mainRateProvider
            ),
            baseCurrency: .krw,
            language: .ko
        )
        MonthReportView(
            viewModel: viewModel,
            ledgerChanges: { dependencies.syncEngine.ledgerDidChange },
            ledgerRevision: { dependencies.syncEngine.ledgerRevision },
            foregroundActivationSignal: dependencies.foregroundActivationSignal,
            onSelectCategory: { _ in }
        )
        .frame(width: 393, height: 852)
        .onAppear {
            viewModel.start(
                month: viewModel.selectedMonth,
                language: .ko,
                baseCurrency: .krw,
                revision: dependencies.syncEngine.ledgerRevision
            )
        }
    } else {
        Text("Preview unavailable")
    }
}
