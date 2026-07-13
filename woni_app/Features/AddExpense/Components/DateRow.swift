import SwiftUI

struct DateRow: View {
    let date: Date
    let language: AppLanguage
    var isCalendarExpanded: Bool
    let onDateChange: (Date) -> Void
    let onTapTitle: () -> Void

    private var title: String {
        if isCalendarExpanded {
            WoniDateFormat.monthTitle(for: date, language: language)
        } else {
            WoniDateFormat.fullDate(date, language: language)
        }
    }

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
                Text(title)
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
        guard let newDate = WoniDateFormat.defaultCalendar.date(byAdding: component, value: amount, to: date) else {
            return
        }
        onDateChange(newDate)
    }
}
