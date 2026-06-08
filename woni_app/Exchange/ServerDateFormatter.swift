//
//  ServerDateFormatter.swift
//  woni_app
//

import Foundation

/// 백엔드 `LocalDate`("yyyy-MM-dd") 변환용 포맷터. 시간대는 백엔드 Jackson과 동일한 Asia/Seoul.
enum ServerDateFormatter {
    static let localDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
