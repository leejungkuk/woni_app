import SwiftUI

struct MainCalendarGridView: View {
    let days: [MainCalendarDay]
    let formatAmount: (Decimal) -> String
    let onSelect: (MainCalendarDay) -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.woni(.small1))
                        .foregroundColor(Color.Woni.gray40)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(days) { day in
                    MainCalendarDayCell(
                        day: day,
                        formatAmount: formatAmount,
                        onSelect: {
                            onSelect(day)
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var weekdaySymbols: [String] {
        if Locale.current.language.languageCode?.identifier == "ko" {
            return ["일", "월", "화", "수", "목", "금", "토"]
        }

        return ["S", "M", "T", "W", "T", "F", "S"]
    }
}

private struct MainCalendarDayCell: View {
    let day: MainCalendarDay
    let formatAmount: (Decimal) -> String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                dayNumber

                VStack(spacing: 0) {
                    if let income = day.income {
                        amountText(income, tone: .income)
                    }
                    if let expense = day.expense {
                        amountText(expense, tone: .expense)
                    }
                }
                .frame(height: 28, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62, alignment: .top)
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            .background(day.isSelected ? Color.Woni.base10 : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(day.day == nil ? 0 : 1)
        }
        .buttonStyle(.plain)
        .disabled(day.day == nil)
    }

    @ViewBuilder
    private var dayNumber: some View {
        if let dayValue = day.day {
            Text("\(dayValue)")
                .font(.woni(.body2))
                .foregroundColor(day.isSelected ? Color.Woni.base10 : Color.Woni.gray100)
                .frame(width: 24, height: 24)
                .background {
                    if day.isSelected {
                        Circle()
                            .fill(Color.Woni.terracotta100)
                    }
                }
        } else {
            Text("")
                .frame(width: 24, height: 24)
        }
    }

    private func amountText(_ amount: Decimal, tone: MainAmountTone) -> some View {
        Text(formatAmount(amount))
            .font(.custom(WoniFont.fontName, size: 10))
            .foregroundColor(tone.foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .frame(maxWidth: .infinity)
    }
}
