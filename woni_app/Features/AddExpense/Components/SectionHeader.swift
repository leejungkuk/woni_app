import SwiftUI

public struct SectionHeader: View {
    let title: String
    let trailingAction: (() -> Void)?
    let trailingTitle: String?

    public init(title: String, trailingTitle: String? = nil, trailingAction: (() -> Void)? = nil) {
        self.title = title
        self.trailingTitle = trailingTitle
        self.trailingAction = trailingAction
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(.woni(.body3))
                .foregroundColor(Color.Woni.gray80)

            Spacer()

            if let trailingTitle = trailingTitle, let trailingAction = trailingAction {
                Button(action: trailingAction) {
                    HStack(spacing: 4) {
                        Text(trailingTitle)
                            .font(.woni(.body3))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color.Woni.gray60)
                }
            }
        }
    }
}

#Preview {
    SectionHeader(title: "CATEGORY", trailingTitle: "Edit", trailingAction: {})
        .padding()
}
