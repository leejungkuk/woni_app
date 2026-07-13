import SwiftUI

struct MonthCalendarGrid: View {
    let days: [MainCalendarDay]
    let language: AppLanguage
    let formatAmount: (Decimal) -> String
    let onSelect: (MainCalendarDay) -> Void
    let handleSwipe: (_ horizontal: Double, _ vertical: Double) -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .woniFont(.small1)
                        .foregroundStyle(WoniColor.gray40)
                        .frame(maxWidth: .infinity)
                        .padding(2)
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(days) { day in
                    dayCell(day)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(WoniColor.gray00)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    handleSwipe(value.translation.width, value.translation.height)
                }
        )
    }

    private var weekdaySymbols: [String] {
        WoniStrings.weekdaysShort(language)
    }

    @ViewBuilder
    private func dayCell(_ day: MainCalendarDay) -> some View {
        if day.day == nil {
            Color.clear
                .frame(height: 62)
        } else {
            Button {
                onSelect(day)
            } label: {
                VStack(spacing: 4) {
                    dayNumber(day)

                    VStack(spacing: 0) {
                        if let expense = day.expense {
                            amountText(expense, tone: .expense)
                        }
                        if let income = day.income {
                            amountText(income, tone: .income)
                        }
                    }
                    .frame(height: 28, alignment: .top)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .top)
                .background {
                    if day.isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(WoniColor.base10)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func dayNumber(_ day: MainCalendarDay) -> some View {
        Text("\(day.day ?? 0)")
            .woniFont(.body2)
            .foregroundStyle(day.isToday ? WoniColor.base10 : WoniColor.gray100)
            .frame(width: 22, height: 22)
            .background {
                if day.isToday {
                    Circle()
                        .fill(WoniColor.terracotta100)
                }
            }
    }

    private func amountText(_ amount: Decimal, tone: MainAmountTone) -> some View {
        Text(formatAmount(amount))
            .woniFont(.small2)
            .foregroundStyle(tone.amountTone.foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .frame(maxWidth: .infinity)
    }
}
