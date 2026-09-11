//
//  CategoryDetailView.swift
//  woni_app
//

import SwiftUI

struct CategoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MonthReportViewModel
    /// 진입 시점 표시명을 화면이 보관한다 — 수정·삭제로 내역이 0건이 돼도 헤더 이름은 남는다.
    @State private var categoryName: String

    let categoryID: Int
    let onSelectEntry: (UUID) -> Void

    init(
        viewModel: MonthReportViewModel,
        categoryID: Int,
        onSelectEntry: @escaping (UUID) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        _categoryName = State(initialValue: viewModel.categoryDisplayName(categoryID: categoryID))
        self.categoryID = categoryID
        self.onSelectEntry = onSelectEntry
    }

    var body: some View {
        let detail = viewModel.categoryDetail(categoryID: categoryID)
        return VStack(spacing: 0) {
            header
            summaryRow(detail)
            list(detail)
        }
        .background(WoniColor.gray00)
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled()
    }
}

private extension CategoryDetailView {
    static let scrollTopID = "report.detail.scroll.top"

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
                .accessibilityIdentifier("report.detail.back")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 0) {
                Text(categoryName)
                    .woniFont(.body1)
                    .foregroundStyle(WoniColor.gray100)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("report.detail.title")
            }
            .padding(.horizontal, 72)
        }
        .frame(height: 52)
        .background(WoniColor.gray00)
    }

    func summaryRow(_ detail: ReportCategoryDetail) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(detail.periodText)
                .woniFont(.body2)
                .foregroundStyle(WoniColor.gray80)
                .accessibilityIdentifier("report.detail.period")

            Spacer(minLength: 8)

            Text(detail.totalText)
                .woniFont(.body1)
                .foregroundStyle(detail.tone.amountTone.foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityIdentifier("report.detail.total")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(WoniColor.gray00)
    }

    func listHeader(_ detail: ReportCategoryDetail) -> some View {
        HStack(spacing: 16) {
            Text(detail.entryCountText)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray100)
                .accessibilityIdentifier("report.detail.count")

            Spacer(minLength: 8)

            sortControl(
                field: .date,
                title: WoniStrings.reportSortDate(viewModel.language),
                identifier: "report.sort.date"
            )
            sortControl(
                field: .amount,
                title: WoniStrings.reportSortAmount(viewModel.language),
                identifier: "report.sort.amount"
            )
        }
        .padding(.horizontal, 16)
    }

    func sortControl(
        field: ReportSortField,
        title: String,
        identifier: String
    ) -> some View {
        let isActive = viewModel.sortField == field
        return Button {
            viewModel.setSort(field: field)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .woniFont(.body3)
                    .foregroundStyle(isActive ? WoniColor.gray100 : WoniColor.gray40)
                if isActive {
                    sortArrow
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "\(title)\(viewModel.isDescending ? "↓" : "↑")" : title)
        .accessibilityIdentifier(identifier)
    }

    var sortArrow: some View {
        Path { path in
            path.move(to: CGPoint(x: 3, y: 0))
            path.addLine(to: CGPoint(x: 3, y: 8))
            path.move(to: CGPoint(x: 0, y: 5))
            path.addLine(to: CGPoint(x: 3, y: 8))
            path.addLine(to: CGPoint(x: 6, y: 5))
        }
        .stroke(WoniColor.gray100, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        .frame(width: 6, height: 8)
        .rotationEffect(.degrees(viewModel.isDescending ? 0 : 180))
    }

    func list(_ detail: ReportCategoryDetail) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.scrollTopID)

                    listHeader(detail)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .woniFont(.body3)
                            .foregroundStyle(WoniColor.terracotta100)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    } else if detail.sections.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(detail.sections) { section in
                                sectionHeader(section)
                                ForEach(section.rows) { row in
                                    entryCard(row)
                                }
                            }
                        }
                        .padding([.horizontal, .bottom], 16)
                    }
                }
                .padding(.bottom, 24)
            }
            .onChange(of: viewModel.sortField) { _, _ in
                proxy.scrollTo(Self.scrollTopID, anchor: .top)
            }
            .onChange(of: viewModel.isDescending) { _, _ in
                proxy.scrollTo(Self.scrollTopID, anchor: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WoniColor.base10)
    }

    func sectionHeader(_ section: ReportDetailSection) -> some View {
        HStack(spacing: 8) {
            Text(section.dateTitle)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray100)
                .accessibilityIdentifier("report.detail.date.\(section.id)")

            Spacer(minLength: 0)

            if let subtotalText = section.subtotalText {
                Text(subtotalText)
                    .woniFont(.small1)
                    .foregroundStyle(section.tone.amountTone.foregroundColor)
                    .accessibilityIdentifier("report.detail.subtotal.\(section.id)")
            }
        }
        .padding(.vertical, 6)
    }

    func entryCard(_ row: MainHistoryRow) -> some View {
        Button {
            onSelectEntry(row.id)
        } label: {
            HistoryItemRow(row: row)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("report.detail.row.\(row.id.uuidString.lowercased())")
    }

    var emptyState: some View {
        Text(WoniStrings.reportMonthEmpty(viewModel.language))
            .woniFont(.body2)
            .foregroundStyle(WoniColor.gray60)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280)
            .accessibilityIdentifier("report.detail.empty")
    }
}
