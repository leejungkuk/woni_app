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
        let rows = viewModel.entryRows(categoryID: categoryID)
        return VStack(spacing: 0) {
            header
            sortChips
            list(rows)
        }
        .background(WoniColor.base10)
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled()
    }
}

private extension CategoryDetailView {
    static let scrollTopID = "report.detail.scroll.top"

    var header: some View {
        HStack(spacing: 8) {
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

            Text(WoniStrings.reportDetailTitle(
                category: categoryName,
                month: viewModel.selectedMonth.month,
                language: viewModel.language,
                calendar: viewModel.calendar
            ))
            .woniFont(.body1)
            .foregroundStyle(WoniColor.gray100)
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(viewModel.formatBaseAmount(viewModel.categoryTotal(categoryID: categoryID)))
                .woniFont(.body2)
                .foregroundStyle(WoniColor.gray100)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(WoniColor.gray00)
    }

    var sortChips: some View {
        HStack(spacing: 12) {
            sortChip(
                field: .date,
                title: WoniStrings.reportSortDate(viewModel.language),
                identifier: "report.sort.date"
            )
            sortChip(
                field: .amount,
                title: WoniStrings.reportSortAmount(viewModel.language),
                identifier: "report.sort.amount"
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    func sortChip(
        field: ReportSortField,
        title: String,
        identifier: String
    ) -> some View {
        let isActive = viewModel.sortField == field
        return Button {
            viewModel.setSort(field: field)
        } label: {
            Text(isActive ? "\(title)\(viewModel.isDescending ? "↓" : "↑")" : title)
                .woniFont(.small1)
                .foregroundStyle(isActive ? WoniColor.gray100 : WoniColor.gray40)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    func list(_ rows: [ReportEntryRow]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.scrollTopID)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .woniFont(.body3)
                            .foregroundStyle(WoniColor.terracotta100)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    } else if rows.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                entryRow(row)
                            }
                        }
                        .padding(.horizontal, 16)
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
    }

    func entryRow(_ row: ReportEntryRow) -> some View {
        Button {
            onSelectEntry(row.id)
        } label: {
            HStack(spacing: 12) {
                Text(rowTitle(row))
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray100)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(viewModel.formatBaseAmount(row.amount))
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray100)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("report.detail.row.\(row.id.uuidString.lowercased())")
    }

    func rowTitle(_ row: ReportEntryRow) -> String {
        let dateText = viewModel.entryDateText(row.transactionDate)
        guard let memo = row.memo else {
            return dateText
        }

        return "\(dateText) · \(memo)"
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
