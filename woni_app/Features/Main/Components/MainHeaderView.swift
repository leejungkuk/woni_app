import SwiftUI

struct MainHeaderView: View {
    let monthTitle: String

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                Text(monthTitle)
                    .font(.custom(WoniFont.fontName, size: 24))
                    .foregroundColor(Color.Woni.gray100)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.Woni.gray80)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {}, label: {
                VStack(spacing: 4) {
                    Capsule()
                        .frame(width: 16, height: 2)
                    Capsule()
                        .frame(width: 16, height: 2)
                    Capsule()
                        .frame(width: 16, height: 2)
                }
                .foregroundColor(Color.Woni.gray80)
                .frame(width: 24, height: 24)
                .padding(10)
                .background(Color.Woni.gray00)
                .clipShape(Circle())
                .shadow(color: Color.Woni.olive20.opacity(0.6), radius: 8, x: 0, y: 0)
            })
            .buttonStyle(.plain)
            .accessibilityLabel("Menu")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}
