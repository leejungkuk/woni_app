import SwiftUI

public struct CurrencySelectBox: View {
    let currencyCode: String
    let palette: AccentPalette
    let action: () -> Void

    public init(currencyCode: String, palette: AccentPalette, action: @escaping () -> Void) {
        self.currencyCode = currencyCode
        self.palette = palette
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(currencyCode)
                    .font(.woni(.body1))
                    .foregroundColor(palette.text110)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.text110)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(palette.bg20)
            .clipShape(Capsule())
        }
    }
}

#Preview {
    CurrencySelectBox(currencyCode: "JPY", palette: .terracotta, action: {})
        .padding()
}
