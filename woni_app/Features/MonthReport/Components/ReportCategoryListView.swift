//
//  ReportCategoryListView.swift
//  woni_app
//

import SwiftUI

struct ReportCategoryListView: View {
    let items: [ReportCategoryItem]
    let categoryName: (Int) -> String
    let formatAmount: (Decimal) -> String
    var onSelect: (Int) -> Void = { _ in }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    onSelect(item.categoryID)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(WoniColor.chartColor(forRank: item.colorRank))
                            .frame(width: 10, height: 10)

                        Text(categoryName(item.categoryID))
                            .woniFont(.body3)
                            .foregroundStyle(WoniColor.gray100)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(formatAmount(item.amount))
                            .woniFont(.body3)
                            .foregroundStyle(WoniColor.gray100)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)

                        Text("\(item.percent)%")
                            .woniFont(.small1)
                            .foregroundStyle(WoniColor.gray60)
                            .frame(width: 34, alignment: .trailing)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WoniColor.gray40)
                            .frame(width: 12)
                    }
                    .frame(height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("report.category.row.\(item.categoryID)")
            }
        }
    }
}
