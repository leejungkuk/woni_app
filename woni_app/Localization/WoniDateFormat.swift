import Foundation

enum WoniDateFormat {
    static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    static func monthTitle(
        year: Int,
        month: Int,
        language: AppLanguage,
        calendar: Calendar = defaultCalendar
    ) -> String {
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: 1
        )) else {
            return "\(year)"
        }

        return monthTitle(for: date, language: language, calendar: calendar)
    }

    static func monthTitle(
        for date: Date,
        language: AppLanguage,
        calendar: Calendar = defaultCalendar
    ) -> String {
        switch language {
        case .ko:
            let components = calendar.dateComponents([.year, .month], from: date)
            return "\(components.year ?? 1970)년 \(components.month ?? 1)월"
        case .en:
            let formatter = makeFormatter(calendar: calendar)
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: date).uppercased(with: Locale(identifier: "en_US_POSIX"))
        }
    }

    static func fullDate(
        _ date: Date,
        language: AppLanguage,
        calendar: Calendar = defaultCalendar
    ) -> String {
        switch language {
        case .ko:
            let formatter = makeFormatter(calendar: calendar)
            formatter.dateFormat = "yyyy년 M월 d일"
            return formatter.string(from: date)
        case .en:
            let formatter = makeFormatter(calendar: calendar)
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
    }

    static func monthName(
        month: Int,
        calendar: Calendar = defaultCalendar
    ) -> String {
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: month,
            day: 1
        )) else {
            return "\(month)"
        }

        let formatter = makeFormatter(calendar: calendar)
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }
}

private extension WoniDateFormat {
    static func makeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter
    }
}
