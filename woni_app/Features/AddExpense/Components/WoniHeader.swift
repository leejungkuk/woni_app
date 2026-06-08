import SwiftUI

public struct WoniHeader: View {
    let date: Date
    let palette: AccentPalette
    let onClose: () -> Void
    let onSave: () -> Void

    public init(date: Date, palette: AccentPalette, onClose: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.date = date
        self.palette = palette
        self.onClose = onClose
        self.onSave = onSave
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    public var body: some View {
        ZStack {
            // Center title
            HStack(spacing: 4) {
                Text(formattedDate)
                    .font(.woni(.body1))
                    .foregroundColor(Color.Woni.gray100)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.Woni.gray100)
            }

            // Buttons
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color.Woni.gray100)
                        .padding(10)
                        .background(Color.Woni.gray00)
                        .clipShape(Capsule())
                        .shadow(color: Color.Woni.olive20.opacity(0.6), radius: 8, x: 0, y: 0)
                }

                Spacer()

                Button(action: onSave) {
                    Text("Save")
                        .font(.woni(.body2))
                        .foregroundColor(Color.Woni.base10)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(palette.primary100)
                        .clipShape(Capsule())
                        .shadow(color: Color.Woni.olive20.opacity(0.6), radius: 8, x: 0, y: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

#Preview {
    WoniHeader(date: Date(), palette: .terracotta, onClose: {}, onSave: {})
}
