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
        let date = try Self.date(year: 2026, month: 5, day: 22)

        #expect(
            WoniDateFormat.fullDate(date, language: .ko, calendar: Self.calendar) == "2026년 5월 22일 (금)"
        )
        #expect(
            WoniDateFormat.fullDate(date, language: .en, calendar: Self.calendar) == "May 22, 2026 (Fri)"
        )
    }

    @Test("전체 날짜의 요일은 일요일 시작 인덱스의 양 끝을 사용한다")
    func fullDateUsesSundayFirstWeekdayBoundaries() throws {
        let sunday = try Self.date(year: 2026, month: 1, day: 25)
        let saturday = try Self.date(year: 2026, month: 1, day: 31)

        #expect(
            WoniDateFormat.fullDate(sunday, language: .ko, calendar: Self.calendar)
                == "2026년 1월 25일 (일)"
        )
        #expect(
            WoniDateFormat.fullDate(saturday, language: .en, calendar: Self.calendar)
                == "Jan 31, 2026 (Sat)"
        )
    }

    @Test("월 이름은 피커용 영문 월명을 반환한다")
    func monthNameUsesEnglishMonthName() {
        #expect(WoniDateFormat.monthName(month: 6, calendar: Self.calendar) == "June")
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
