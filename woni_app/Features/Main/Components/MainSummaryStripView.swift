import SwiftUI

struct MainSummaryStripView: View {
    let items: [MainSummaryItem]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(items) { item in
                VStack(spacing: 0) {
                    Text(item.title)
                        .font(.woni(.small1))
                        .foregroundColor(Color.Woni.gray80)

                    Text(item.amountText)
                        .font(.woni(.small1))
                        .foregroundColor(item.tone.foregroundColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.Woni.base20)
                .frame(height: 1)
        }
    }
}
