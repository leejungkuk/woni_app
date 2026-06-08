import SwiftUI

public struct MemoSection: View {
    @Binding var memo: String

    public init(memo: Binding<String>) {
        _memo = memo
    }

    public var body: some View {
        VStack(spacing: 8) {
            SectionHeader(title: "MEMO")

            TextField("Write down where you used it.", text: $memo)
                .font(.woni(.body3))
                .foregroundColor(Color.Woni.gray100)
                .padding(.vertical, 8)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.Woni.gray40),
                    alignment: .bottom
                )
        }
    }
}

#Preview {
    MemoSection(memo: .constant(""))
        .padding()
}
