import SwiftUI

struct MemoField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray100)
                .padding(.vertical, 12)

            TextField("어디에 사용했는지 적어주세요.", text: $text)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray100)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(WoniColor.gray40).frame(height: 1)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
