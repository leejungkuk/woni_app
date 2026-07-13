import Foundation

struct MainMonth: Equatable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month], from: date)
        year = components.year ?? 1970
        month = components.month ?? 1
    }

    var ledgerMonth: LedgerMonth {
        LedgerMonth(year: year, month: month)
    }

    func addingMonths(_ value: Int, calendar: Calendar) -> MainMonth {
        guard let firstDay = date(day: 1, calendar: calendar),
              let next = calendar.date(byAdding: .month, value: value, to: firstDay)
        else {
            return self
        }

        return MainMonth(date: next, calendar: calendar)
    }

    func date(day: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))
    }
}

enum MainAmountTone: Equatable {
    case income
    case expense
}

extension MainAmountTone {
    var amountTone: AmountTone {
        switch self {
        case .income:
            .income
        case .expense:
            .expense
        }
    }

    init(amountTone: AmountTone) {
        switch amountTone {
        case .income:
            self = .income
        case .expense:
            self = .expense
        }
    }
}

extension AmountTone {
    init(mainAmountTone: MainAmountTone) {
        self = mainAmountTone.amountTone
    }
}

struct MainMonthlySummary: Equatable {
    var income: Decimal
    var expense: Decimal
    var total: Decimal

    static let empty = MainMonthlySummary(income: 0, expense: 0, total: 0)

    var totalTone: MainAmountTone {
        total < 0 ? .expense : .income
    }
}

struct MainDailySummary: Equatable {
    var income: Decimal = 0
    var expense: Decimal = 0
}

struct MainCalendarDay: Identifiable, Equatable {
    let id: String
    let day: Int?
    let dateString: String?
    let isSelected: Bool
    let isToday: Bool
    let income: Decimal?
    let expense: Decimal?
}

struct MainSummaryItem: Identifiable, Equatable {
    enum Kind: String {
        case expense
        case income
        case total
    }

    let kind: Kind
    let title: String
    let amountText: String
    let tone: MainAmountTone

    var id: Kind {
        kind
    }
}

struct MainHistoryRow: Identifiable, Equatable {
    let id: String
    let title: String
    let categoryAssetText: String
    let exchangeInfoText: String?
    let amountText: String
    let secondaryAmountText: String?
    let tone: MainAmountTone
}
