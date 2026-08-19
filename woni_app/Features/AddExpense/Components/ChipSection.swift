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

/// 소제목 우측 보조 액션(카테고리 `수정 ›`). 식별자는 칩 접두사(`entry.category.`)와 분리해
/// 칩 개수를 세는 조회(`BEGINSWITH`)에 잡히지 않게 한다.
struct ChipSectionTrailingAction {
    let title: String
    let identifier: String
    let action: () -> Void
}

struct ChipSection: View {
    let title: String
    let items: [EntryChipItem]
    var accent: ChipButton.ChipAccent = .terracotta
    /// 칩 접근성 식별자 접두사. 카테고리와 자산은 id가 겹칠 수 있어 섹션별로 분리한다.
    var identifierPrefix = "entry.chip"
    var trailingAction: ChipSectionTrailingAction?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text(title)
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray100)
                    .padding(.vertical, 12)

                Spacer()

                if let trailingAction {
                    Button(action: trailingAction.action) {
                        HStack(spacing: 2) {
                            Text(trailingAction.title)
                                .woniFont(.body3)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(WoniColor.gray60)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(trailingAction.identifier)
                }
            }

            FlowLayout(spacing: 8) {
                ForEach(items) { item in
                    ChipButton(
                        label: item.displayLabel,
                        isSelected: item.isSelected,
                        accent: accent
                    ) {
                        onSelect(item.id)
                    }
                    .accessibilityIdentifier("\(identifierPrefix).\(item.id)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
