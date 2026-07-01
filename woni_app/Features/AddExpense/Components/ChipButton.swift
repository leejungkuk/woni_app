import SwiftUI

struct ChipButton: View {
    let label: String
    let isSelected: Bool
    let palette: AccentPalette
    let action: () -> Void

    init(category: Category, selectedId: Int?, palette: AccentPalette, action: @escaping (Category) -> Void) {
        label = category.chipLabel
        isSelected = selectedId == category.id
        self.palette = palette
        self.action = { action(category) }
    }

    init(asset: Asset, selectedId: Int?, palette: AccentPalette, action: @escaping (Asset) -> Void) {
        label = asset.displayNameEn
        isSelected = selectedId == asset.id
        self.palette = palette
        self.action = { action(asset) }
    }

    private init(label: String, isSelected: Bool, palette: AccentPalette, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.palette = palette
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.woni(.body3))
                .foregroundColor(isSelected ? palette.primary100 : Color.Woni.gray80)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? palette.bg10 : Color.Woni.base10)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? palette.border70 : Color.Woni.gray20, lineWidth: 1)
                )
        }
    }
}

private extension Category {
    var chipLabel: String {
        guard let icon, !icon.isEmpty else {
            return displayNameEn
        }
        return "\(icon) \(displayNameEn)"
    }
}

#Preview {
    let food = Category(
        id: 10,
        code: "FOOD",
        displayNameKo: "식비",
        displayNameEn: "Food",
        icon: "🍽️",
        sortOrder: 1
    )
    let transport = Category(
        id: 11,
        code: "TRANSPORT",
        displayNameKo: "교통",
        displayNameEn: "Transport",
        icon: nil,
        sortOrder: 2
    )

    HStack {
        ChipButton(category: food, selectedId: food.id, palette: .terracotta, action: { _ in })
        ChipButton(category: transport, selectedId: food.id, palette: .terracotta, action: { _ in })
    }
    .padding()
}
