import SwiftUI

struct MemoField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray100)
                .padding(.vertical, 12)

            // 플레이스홀더 색은 prompt로만 지정할 수 있다(기본 placeholderText는 Figma gray40보다 연하다).
            // label 인자에 같은 문자열을 남겨 빈 필드의 접근성 값이 placeholder로 유지되게 한다.
            TextField(
                placeholder,
                text: $text,
                prompt: Text(placeholder).foregroundStyle(WoniColor.gray40)
            )
            .accessibilityIdentifier("entry.memo")
            .woniFont(.body3)
            .foregroundStyle(WoniColor.gray100)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .padding(.horizontal, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(WoniColor.gray40).frame(height: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
