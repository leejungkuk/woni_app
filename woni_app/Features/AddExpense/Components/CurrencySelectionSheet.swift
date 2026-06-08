import SwiftUI

public struct CurrencySelectionSheet: View {
    let selectedCurrency: SelectableCurrency
    let palette: AccentPalette
    let onSelect: (SelectableCurrency) -> Void

    public init(
        selectedCurrency: SelectableCurrency,
        palette: AccentPalette,
        onSelect: @escaping (SelectableCurrency) -> Void
    ) {
        self.selectedCurrency = selectedCurrency
        self.palette = palette
        self.onSelect = onSelect
    }

    public var body: some View {
        ZStack {
            Color.Woni.base10.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("통화 선택")
                    .font(.woni(.body1))
                    .foregroundColor(Color.Woni.gray100)
                    .padding(.top, 24)
                    .padding(.bottom, 24)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(SelectableCurrency.allCases) { currency in
                            Button(
                                action: { onSelect(currency) },
                                label: {
                                    HStack(spacing: 12) {
                                        Text(currency.flag)
                                            .font(.system(size: 24))

                                        Text(currency.rawValue)
                                            .font(.woni(.body2))
                                            .foregroundColor(Color.Woni.gray100)

                                        Text(currency.displayName)
                                            .font(.woni(.body3))
                                            .foregroundColor(Color.Woni.gray60)

                                        Spacer()

                                        if currency == selectedCurrency {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(palette.primary100)
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 16)
                                    .contentShape(Rectangle())
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
