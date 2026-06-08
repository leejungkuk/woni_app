import SwiftUI

public struct WoniSegmentTabs: View {
    public enum Tab {
        case expense
        case income
    }

    @Binding var selectedTab: Tab
    let palette: AccentPalette

    public init(selectedTab: Binding<Tab>, palette: AccentPalette) {
        _selectedTab = selectedTab
        self.palette = palette
    }

    public var body: some View {
        HStack(spacing: 0) {
            TabButton(
                title: "Expense",
                isSelected: selectedTab == .expense,
                activeColor: AccentPalette.terracotta.primary100
            ) {
                selectedTab = .expense
            }

            TabButton(
                title: "Income",
                isSelected: selectedTab == .income,
                activeColor: AccentPalette.olive.primary100
            ) {
                selectedTab = .income
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.Woni.base20),
            alignment: .bottom
        )
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.woni(.body2))
                .foregroundColor(isSelected ? activeColor : Color.Woni.gray40)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .overlay(
                    Rectangle()
                        .frame(height: isSelected ? 2 : 0)
                        .foregroundColor(isSelected ? activeColor : .clear),
                    alignment: .bottom
                )
        }
    }
}

#Preview {
    WoniSegmentTabs(selectedTab: .constant(.expense), palette: .terracotta)
}
