import Foundation
import Testing
@testable import woni_app

struct WoniDateFormatTests {
    @Test("월 제목은 언어별 Figma 표기 규칙을 사용한다")
    func monthTitleUsesLanguageSpecificFormat() throws {
        let date = try Self.date(year: 2026, month: 1, day: 31)

        #expect(
            WoniDateFormat.monthTitle(for: date, language: .ko, calendar: Self.calendar) == "2026년 1월"
        )
        #expect(
            WoniDateFormat.monthTitle(for: date, language: .en, calendar: Self.calendar) == "JANUARY 2026"
        )
        #expect(
            WoniDateFormat.monthTitle(year: 2026, month: 1, language: .ko, calendar: Self.calendar)
                == "2026년 1월"
        )
        #expect(
            WoniDateFormat.monthTitle(year: 2026, month: 1, language: .en, calendar: Self.calendar)
                == "JANUARY 2026"
        )
    }

    @Test("전체 날짜는 언어별 Figma 표기 규칙을 사용한다")
    func fullDateUsesLanguageSpecificFormat() throws {
        let date = try Self.date(year: 2026, month: 1, day: 31)

        #expect(
            WoniDateFormat.fullDate(date, language: .ko, calendar: Self.calendar) == "2026년 1월 31일"
        )
        #expect(
            WoniDateFormat.fullDate(date, language: .en, calendar: Self.calendar) == "Jan 31, 2026"
        )
    }
}

private extension WoniDateFormatTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    static func date(year: Int, month: Int, day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )))
    }
}
