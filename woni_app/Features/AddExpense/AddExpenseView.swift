import SwiftUI

struct AddExpenseView: View {
    @State private var viewModel = AddExpenseViewModel()
    @State private var isCurrencySheetPresented = false
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.Woni.base10.ignoresSafeArea()

            VStack(spacing: 0) {
                WoniHeader(
                    date: viewModel.date,
                    palette: viewModel.palette,
                    onClose: onClose,
                    isSaveDisabled: !viewModel.canSave || viewModel.isSaving,
                    saveAction: {
                        Task {
                            await viewModel.save()
                        }
                    }
                )

                WoniSegmentTabs(selectedTab: $viewModel.selectedTab, palette: viewModel.palette)

                saveStatusContent

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

                        catalogContent

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
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var saveStatusContent: some View {
        if viewModel.saveSucceeded {
            Text("저장됨")
                .font(.woni(.body3))
                .foregroundColor(viewModel.palette.primary100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        } else if let saveError = viewModel.saveError {
            Text(saveError)
                .font(.woni(.body3))
                .foregroundColor(Color.Woni.terracotta100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var catalogContent: some View {
        if viewModel.isLoadingCatalog {
            CatalogPlaceholderSection(title: "CATEGORY")
            CatalogPlaceholderSection(title: "PROPERTY")
        } else if let catalogError = viewModel.catalogError {
            CatalogErrorSection(
                message: catalogError,
                palette: viewModel.palette,
                onRetry: {
                    Task {
                        await viewModel.load()
                    }
                }
            )
        } else {
            CategorySection(
                categories: viewModel.visibleCategories,
                selectedCategoryId: viewModel.selectedCategoryId,
                palette: viewModel.palette,
                onSelect: { viewModel.selectCategory($0) }
            )

            PaymentSection(
                assets: viewModel.assets,
                selectedAssetId: viewModel.selectedAssetId,
                palette: viewModel.palette,
                onSelect: { viewModel.selectAsset($0) }
            )
        }
    }
}

#Preview {
    AddExpenseView(onClose: {})
}

private struct CatalogPlaceholderSection: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: title, trailingTitle: nil, trailingAction: nil)

            FlowLayout(spacing: 8) {
                ForEach(0 ..< 5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.Woni.gray00)
                        .frame(width: index.isMultiple(of: 2) ? 92 : 128, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.Woni.gray20, lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
    }
}

private struct CatalogErrorSection: View {
    let message: String
    let palette: AccentPalette
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.woni(.body3))
                .foregroundColor(Color.Woni.gray80)

            Button(action: onRetry) {
                Text("Retry")
                    .font(.woni(.body3))
                    .foregroundColor(palette.primary100)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(palette.bg10)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(palette.border70, lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
