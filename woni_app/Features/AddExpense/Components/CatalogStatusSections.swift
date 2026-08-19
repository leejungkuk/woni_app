import SwiftUI

/// 카탈로그 로딩/오류 상태 섹션. `AddEntryView`가 file_length 한계에 닿아 이 묶음만 분리했다
/// (동작은 인라인 시절과 동일하다).
struct CatalogPlaceholderSection: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray100)
                .padding(.vertical, 12)

            FlowLayout(spacing: 8) {
                ForEach(0 ..< 5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 18)
                        .fill(WoniColor.gray00)
                        .frame(width: index.isMultiple(of: 2) ? 92 : 128, height: 36)
                        .overlay {
                            Capsule().stroke(WoniColor.gray20, lineWidth: 1)
                        }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
    }
}

struct CatalogErrorSection: View {
    let message: String
    let retryTitle: String
    let accent: ChipButton.ChipAccent
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray80)

            Button(action: onRetry) {
                Text(retryTitle)
                    .woniFont(.body3)
                    .foregroundStyle(accent.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(accent.background)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().stroke(accent.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
