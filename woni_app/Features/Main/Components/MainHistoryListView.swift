import SwiftUI

struct MainHistoryListView: View {
    let rows: [MainHistoryRow]

    var body: some View {
        LazyVStack(spacing: 8) {
            if rows.isEmpty {
                Color.clear
                    .frame(height: 240)
            } else {
                ForEach(rows) { row in
                    MainHistoryCard(row: row)
                }
            }
        }
    }
}

private struct MainHistoryCard: View {
    let row: MainHistoryRow

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.woni(.body3))
                    .foregroundColor(Color.Woni.gray100)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(row.categoryAssetText)
                    .font(.woni(.small1))
                    .foregroundColor(Color.Woni.gray80)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let exchangeInfoText = row.exchangeInfoText {
                    Text(exchangeInfoText)
                        .font(.custom(WoniFont.fontName, size: 10))
                        .foregroundColor(Color.Woni.gray60)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.amountText)
                    .font(.woni(.body3))
                    .foregroundColor(row.tone.foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                if let secondaryAmountText = row.secondaryAmountText {
                    Text(secondaryAmountText)
                        .font(.custom(WoniFont.fontName, size: 10))
                        .foregroundColor(Color.Woni.gray80)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.Woni.gray00)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
