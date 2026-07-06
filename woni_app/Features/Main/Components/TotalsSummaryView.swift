import SwiftUI

struct TotalsSummaryView: View {
    let items: [MainSummaryItem]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(items) { item in
                VStack(spacing: 2) {
                    Text(item.title)
                        .woniFont(.small1)
                        .foregroundStyle(WoniColor.gray80)

                    Text(item.amountText)
                        .woniFont(.small1)
                        .foregroundStyle(item.tone.amountTone.foregroundColor)
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
        .frame(maxWidth: .infinity)
        .background(WoniColor.gray00)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WoniColor.base20)
                .frame(height: 1)
        }
    }
}
