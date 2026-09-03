//
//  ReportSummaryTabs.swift
//  woni_app
//

import SwiftUI

struct ReportSummaryTabs: View {
    let items: [MainSummaryItem]
    let selected: MainSummaryItem.Kind
    let onSelect: (MainSummaryItem.Kind) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { item in
                Button {
                    onSelect(item.kind)
                } label: {
                    VStack(spacing: 6) {
                        VStack(spacing: 2) {
                            Text(item.title)
                                .woniFont(.small1)
                                .foregroundStyle(WoniColor.gray80)

                            Text(item.amountText)
                                .woniFont(.small1)
                                .foregroundStyle(item.tone.amountTone.foregroundColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                        }
                        .padding(.horizontal, 4)

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(selected == item.kind ? indicatorColor(for: item.kind) : Color.clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("report.tab.\(item.kind.rawValue)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(WoniColor.gray00)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WoniColor.base20)
                .frame(height: 1)
        }
    }

    private func indicatorColor(for kind: MainSummaryItem.Kind) -> Color {
        switch kind {
        case .expense:
            WoniColor.terracotta100
        case .income:
            WoniColor.olive100
        case .total:
            WoniColor.gray80
        }
    }
}
