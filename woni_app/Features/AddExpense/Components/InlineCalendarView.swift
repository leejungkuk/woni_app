import SwiftUI

struct InlineCalendarView: View {
    let selectedDate: Date
    let language: AppLanguage
    let accentColor: Color
    let onSelectDate: (Date) -> Void
    let onSelect: () -> Void

    private let calendar = WoniDateFormat.defaultCalendar
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    private var weekdaySymbols: [String] {
        WoniStrings.weekdaysShort(language)
    }

    private var year: Int {
        calendar.component(.year, from: selectedDate)
    }

    private var month: Int {
        calendar.component(.month, from: selectedDate)
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: selectedDate)?.count ?? 30
    }

    private var leadingBlankCount: Int {
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: 1
        )) else {
            return 0
        }
        return calendar.component(.weekday, from: date) - 1
    }

    private enum GridCell: Hashable {
        case blank(Int)
        case day(Int)
    }

    private var gridCells: [GridCell] {
        (0 ..< leadingBlankCount).map { GridCell.blank($0) } + (1 ... daysInMonth).map { GridCell.day($0) }
    }

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .woniFont(.small1)
                        .foregroundStyle(WoniColor.gray40)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(gridCells, id: \.self) { cell in
                    switch cell {
                    case .blank:
                        Color.clear.frame(width: 48, height: 48)
                    case let .day(day):
                        dayButton(day)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(WoniColor.base10)
    }
}

private extension InlineCalendarView {
    func dayButton(_ day: Int) -> some View {
        let isSelected = calendar.component(.day, from: selectedDate) == day

        return Button {
            if let newDate = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )) {
                onSelectDate(newDate)
            }
            onSelect()
        } label: {
            Text("\(day)")
                .woniFont(.body2)
                .foregroundStyle(isSelected ? WoniColor.base10 : WoniColor.gray100)
                .frame(width: 22, height: 22)
                .background {
                    if isSelected {
                        Circle().fill(accentColor)
                    }
                }
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
    }
}
