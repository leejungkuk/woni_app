import SwiftUI

struct PaymentSection: View {
    let assets: [Asset]
    let selectedAssetId: Int?
    let palette: AccentPalette
    let onSelect: (Asset) -> Void

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "PROPERTY", trailingTitle: "Edit", trailingAction: {})

            FlowLayout(spacing: 8) {
                ForEach(assets) { asset in
                    ChipButton(
                        asset: asset,
                        selectedId: selectedAssetId,
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
    PaymentSection(
        assets: [
            Asset(id: 20, code: "CASH", displayNameKo: "현금", displayNameEn: "Cash", sortOrder: 1),
            Asset(id: 21, code: "CARD", displayNameKo: "카드", displayNameEn: "Card", sortOrder: 2)
        ],
        selectedAssetId: 20,
        palette: .terracotta,
        onSelect: { _ in }
    )
    .padding()
}
