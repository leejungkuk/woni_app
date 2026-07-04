import SwiftUI

struct LegalTextView: View {
    let title: String
    let clauses: [LegalClause]
    var pendingNote: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: title) {
                dismiss()
            }
            .zIndex(1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let pendingNote {
                        Text(pendingNote)
                            .woniFont(.body3)
                            .foregroundStyle(WoniColor.gray60)
                    }

                    ForEach(clauses) { clause in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(clause.title)
                                .woniFont(.body1)
                                .foregroundStyle(WoniColor.gray100)
                            Text(clause.body)
                                .woniFont(.body3)
                                .foregroundStyle(WoniColor.gray100)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(WoniColor.gray00)
        .toolbar(.hidden, for: .navigationBar)
    }
}
