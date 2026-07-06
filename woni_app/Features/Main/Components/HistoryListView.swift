import SwiftUI

struct HistoryListView: View {
    let rows: [MainHistoryRow]
    let conversionWarningText: String?

    var body: some View {
        LazyVStack(spacing: 8) {
            if let conversionWarningText {
                conversionWarning(conversionWarningText)
            }

            if rows.isEmpty {
                Color.clear
                    .frame(height: 240)
            } else {
                ForEach(rows) { row in
                    HistoryItemRow(row: row)
                }
            }
        }
        .padding(16)
        .background(WoniColor.base10)
    }

    private func conversionWarning(_ text: String) -> some View {
        Text(text)
            .woniFont(.small1)
            .foregroundStyle(WoniColor.terracotta110)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(WoniColor.terracotta10)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HistoryItemRow: View {
    let row: MainHistoryRow

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray100)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(row.categoryAssetText)
                    .woniFont(.small1)
                    .foregroundStyle(WoniColor.gray80)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let exchangeInfoText = row.exchangeInfoText {
                    Text(exchangeInfoText)
                        .woniFont(.small2)
                        .foregroundStyle(WoniColor.gray60)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.amountText)
                    .woniFont(.body3)
                    .foregroundStyle(row.tone.amountTone.foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                if let secondaryAmountText = row.secondaryAmountText {
                    Text(secondaryAmountText)
                        .woniFont(.small2)
                        .foregroundStyle(WoniColor.gray80)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WoniColor.gray00)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
