import SwiftUI

struct MainFloatingAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .regular))
                .foregroundColor(Color.Woni.base10)
                .frame(width: 52, height: 52)
                .background(Color.Woni.terracotta100)
                .clipShape(Circle())
                .shadow(color: Color.Woni.olive20.opacity(0.6), radius: 8, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
    }
}
