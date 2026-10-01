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

/// 그리드 끝 보조 칩(`+ 추가`). 식별자 분리 이유는 ChipSectionTrailingAction과 같다.
struct ChipSectionTrailingChip {
    let label: String
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
    var trailingChip: ChipSectionTrailingChip?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text(title)
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray100)
                    .padding(.vertical, 12)

                Spacer()
            }
            // 버튼은 터치 타깃 44를 채우지만 소제목 줄(약 43.6)은 제목만 정한다 — 줄 안에 두면
            // 줄이 44로 늘어 칩이 내려간다. 겹쳐 올려 레이아웃은 그대로 둔다.
            .overlay(alignment: .trailing) {
                if let trailingAction {
                    Button {
                        hideKeyboard()
                        trailingAction.action()
                    } label: {
                        HStack(spacing: 2) {
                            Text(trailingAction.title)
                                .woniFont(.body3)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(WoniColor.gray60)
                        .padding(.leading, 12)
                        // 글자 폭은 언어·글꼴마다 달라 여백만으로는 44에 못 미칠 수 있다("수정 ›" 31+12).
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
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
                        hideKeyboard()
                        onSelect(item.id)
                    }
                    .accessibilityIdentifier("\(identifierPrefix).\(item.id)")
                }

                if let trailingChip {
                    ChipButton(
                        label: trailingChip.label,
                        isSelected: false,
                        accent: accent
                    ) {
                        hideKeyboard()
                        trailingChip.action()
                    }
                    .accessibilityIdentifier(trailingChip.identifier)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
