import SwiftUI

public struct CategorySection: View {
    let tab: WoniSegmentTabs.Tab
    let selectedExpenseCategory: ExpenseCategory?
    let selectedIncomeCategory: IncomeCategory?
    let palette: AccentPalette
    let onExpenseSelect: (ExpenseCategory) -> Void
    let onIncomeSelect: (IncomeCategory) -> Void

    public init(
        tab: WoniSegmentTabs.Tab,
        selectedExpenseCategory: ExpenseCategory?,
        selectedIncomeCategory: IncomeCategory?,
        palette: AccentPalette,
        onExpenseSelect: @escaping (ExpenseCategory) -> Void,
        onIncomeSelect: @escaping (IncomeCategory) -> Void
    ) {
        self.tab = tab
        self.selectedExpenseCategory = selectedExpenseCategory
        self.selectedIncomeCategory = selectedIncomeCategory
        self.palette = palette
        self.onExpenseSelect = onExpenseSelect
        self.onIncomeSelect = onIncomeSelect
    }

    public var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "CATEGORY", trailingTitle: "Edit", trailingAction: {})

            FlowLayout(spacing: 8) {
                if tab == .expense {
                    ForEach(ExpenseCategory.allCases) { category in
                        ChipButton(
                            label: category.label,
                            isSelected: selectedExpenseCategory == category,
                            palette: palette,
                            action: { onExpenseSelect(category) }
                        )
                    }
                } else {
                    ForEach(IncomeCategory.allCases) { category in
                        ChipButton(
                            label: category.label,
                            isSelected: selectedIncomeCategory == category,
                            palette: palette,
                            action: { onIncomeSelect(category) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    CategorySection(
        tab: .expense,
        selectedExpenseCategory: .foodDining,
        selectedIncomeCategory: .salary,
        palette: .terracotta,
        onExpenseSelect: { _ in },
        onIncomeSelect: { _ in }
    )
    .padding()
}
