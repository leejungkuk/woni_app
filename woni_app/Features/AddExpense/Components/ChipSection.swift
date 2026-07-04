import SwiftUI

struct EntryChipItem: Identifiable {
    let id: Int
    let label: String
    let icon: String?
    let isSelected: Bool

    var displayLabel: String {
        icon.map { "\($0) \(label)" } ?? label
    }
}

struct ChipSection: View {
    let title: String
    let items: [EntryChipItem]
    var accent: ChipButton.ChipAccent = .terracotta
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray100)
                .padding(.vertical, 12)

            FlowLayout(spacing: 8) {
                ForEach(items) { item in
                    ChipButton(
                        label: item.displayLabel,
                        isSelected: item.isSelected,
                        accent: accent
                    ) {
                        onSelect(item.id)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
