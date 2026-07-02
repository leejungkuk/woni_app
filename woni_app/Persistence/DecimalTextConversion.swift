//
//  DecimalTextConversion.swift
//  woni_app
//

import Foundation

enum DecimalTextConversion {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func string(from decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }

    static func decimal(from text: String) -> Decimal? {
        Decimal(string: text, locale: locale)
    }
}
