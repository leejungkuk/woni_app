//
//  ReportCompareBars.swift
//  woni_app
//

import SwiftUI

struct ReportCompareBars: View {
    let items: [MainSummaryItem]
    let summary: MainMonthlySummary
    let remainingTitle: String

    var body: some View {
        VStack(spacing: 12) {
            bar(kind: .expense, amount: summary.expense, color: WoniColor.terracotta100)
            bar(kind: .income, amount: summary.income, color: WoniColor.olive100)

            Rectangle()
                .fill(WoniColor.base20)
                .frame(height: 1)

            HStack {
                Text(remainingTitle)
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray80)
                Spacer()
                Text(signedRemainingText)
                    .woniFont(.body1)
                    .foregroundStyle(summary.totalTone.amountTone.foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(WoniColor.gray00)
    }

    private var maximumAmount: Decimal {
        max(summary.expense, summary.income)
    }

    private var signedRemainingText: String {
        guard let text = item(kind: .total)?.amountText else {
            return ""
        }
        return Self.remainingText(amountText: text, total: summary.total)
    }

    /// 합계 금액은 부호 없이 오므로 "남은 돈"의 부호는 여기서 붙인다 — 흑자 "+", 적자 "-", 0 은 그대로.
    static func remainingText(amountText: String, total: Decimal) -> String {
        if total > 0 {
            return "+\(amountText)"
        }
        if total < 0 {
            return "-\(amountText)"
        }
        return amountText
    }

    private func item(kind: MainSummaryItem.Kind) -> MainSummaryItem? {
        items.first { $0.kind == kind }
    }

    private func ratio(for amount: Decimal) -> CGFloat {
        guard maximumAmount > 0 else {
            return 0
        }
        return CGFloat(truncating: NSDecimalNumber(decimal: amount / maximumAmount))
    }

    private func bar(kind: MainSummaryItem.Kind, amount: Decimal, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(item(kind: kind)?.title ?? "")
                    .woniFont(.small1)
                    .foregroundStyle(WoniColor.gray80)
                Spacer()
                Text(item(kind: kind)?.amountText ?? "")
                    .woniFont(.small1)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(WoniColor.gray10)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color)
                        .frame(width: proxy.size.width * ratio(for: amount))
                }
            }
            .frame(height: 14)
        }
    }
}
