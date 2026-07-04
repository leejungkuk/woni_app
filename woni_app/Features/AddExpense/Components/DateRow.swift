import SwiftUI

struct DateRow: View {
    let date: Date
    var isCalendarExpanded: Bool
    let onDateChange: (Date) -> Void
    let onTapTitle: () -> Void

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            Button {
                move(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(WoniColor.gray80)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: onTapTitle) {
                Text(isCalendarExpanded ? Self.monthFormatter.string(from: date) : Self.fullFormatter
                    .string(from: date))
                    .woniFont(.body1)
                    .foregroundStyle(WoniColor.gray100)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                move(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(WoniColor.gray80)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }
}

private extension DateRow {
    func move(by amount: Int) {
        let component: Calendar.Component = isCalendarExpanded ? .month : .day
        guard let newDate = Calendar.current.date(byAdding: component, value: amount, to: date) else {
            return
        }
        onDateChange(newDate)
    }
}
