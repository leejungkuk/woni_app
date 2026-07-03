import SwiftUI

struct MainConversionWarningView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.woni(.small1))
            .foregroundColor(Color.Woni.terracotta110)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.Woni.terracotta10)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
