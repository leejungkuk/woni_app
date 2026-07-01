import SwiftUI

struct CategorySection: View {
    let categories: [Category]
    let selectedCategoryId: Int?
    let palette: AccentPalette
    let onSelect: (Category) -> Void

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "CATEGORY", trailingTitle: "Edit", trailingAction: {})

            FlowLayout(spacing: 8) {
                ForEach(categories) { category in
                    ChipButton(
                        category: category,
                        selectedId: selectedCategoryId,
                        palette: palette,
                        action: onSelect
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let categories = [
        Category(
            id: 10,
            code: "FOOD",
            displayNameKo: "식비",
            displayNameEn: "Food",
            icon: "🍽️",
            sortOrder: 1
        ),
        Category(
            id: 11,
            code: "TRAVEL",
            displayNameKo: "여행",
            displayNameEn: "Travel",
            icon: "✈️",
            sortOrder: 2
        )
    ]

    CategorySection(
        categories: categories,
        selectedCategoryId: 10,
        palette: .terracotta,
        onSelect: { _ in }
    )
    .padding()
}
