import SwiftUI

struct AddExpenseView: View {
    @State private var viewModel = AddExpenseViewModel()
    @State private var isCurrencySheetPresented = false
    let onClose: () -> Void
    let onSave: (ExpenseDraft) -> Void

    init(onClose: @escaping () -> Void, onSave: @escaping (ExpenseDraft) -> Void) {
        self.onClose = onClose
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            Color.Woni.base10.ignoresSafeArea()

            VStack(spacing: 0) {
                WoniHeader(
                    date: viewModel.date,
                    palette: viewModel.palette,
                    onClose: onClose,
                    onSave: { viewModel.save(onSave: onSave) }
                )

                WoniSegmentTabs(selectedTab: $viewModel.selectedTab, palette: viewModel.palette)

                ScrollView {
                    VStack(spacing: 32) {
                        MoneyInputSection(
                            amount: $viewModel.amount,
                            currencyCode: viewModel.selectedCurrency.rawValue,
                            baseCurrency: "KRW",
                            exchangeRate: viewModel.krwToForeignRate,
                            baseAmount: viewModel.convertedBaseAmount,
                            palette: viewModel.palette,
                            onCurrencyTap: {
                                isCurrencySheetPresented = true
                            }
                        )

                        CategorySection(
                            tab: viewModel.selectedTab,
                            selectedExpenseCategory: viewModel.selectedExpenseCategory,
                            selectedIncomeCategory: viewModel.selectedIncomeCategory,
                            palette: viewModel.palette,
                            onExpenseSelect: { viewModel.selectedExpenseCategory = $0 },
                            onIncomeSelect: { viewModel.selectedIncomeCategory = $0 }
                        )

                        PaymentSection(
                            selectedMethod: viewModel.selectedMethod,
                            palette: viewModel.palette,
                            onSelect: { viewModel.selectedMethod = $0 }
                        )

                        MemoSection(memo: $viewModel.memo)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 32)
                }
            }
        }
        .sheet(isPresented: $isCurrencySheetPresented) {
            CurrencySelectionSheet(
                selectedCurrency: viewModel.selectedCurrency,
                palette: viewModel.palette,
                onSelect: { currency in
                    viewModel.updateCurrency(currency)
                    isCurrencySheetPresented = false
                }
            )
            .presentationDetents([.medium])
        }
    }
}

#Preview {
    AddExpenseView(onClose: {}, onSave: { _ in })
}
