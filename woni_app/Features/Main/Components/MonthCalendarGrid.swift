import SwiftUI

/// 요일 헤더와 날짜 셀이 같은 열 위에 놓여야 한다. 두 타입의 공통 사양이라 파일 스코프에 둔다.
private let calendarColumns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: 7)

struct MonthCalendarGrid: View {
    static let dayCellHeight: CGFloat = 62
    static let dayRowSpacing: CGFloat = 2

    let days: [MainCalendarDay]
    let language: AppLanguage
    let formatAmount: (Decimal) -> String
    let onSelect: (MainCalendarDay) -> Void

    /// 날짜 그리드만의 높이다. `makeCalendarDays`가 후행 빈칸을 7의 배수까지 채우므로
    /// `dayCount`는 항상 7의 배수이고, 그보다 작으면 그릴 행이 없다.
    static func dayGridHeight(dayCount: Int) -> CGFloat {
        guard dayCount >= 7 else {
            return 0
        }

        let rows = dayCount / 7
        return CGFloat(rows) * dayCellHeight + CGFloat(rows - 1) * dayRowSpacing
    }

    var body: some View {
        LazyVGrid(columns: calendarColumns, spacing: Self.dayRowSpacing) {
            ForEach(days) { day in
                dayCell(day)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: MainCalendarDay) -> some View {
        if day.day == nil {
            Color.clear
                .frame(height: Self.dayCellHeight)
        } else {
            let cell = Button {
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
                .frame(maxWidth: .infinity, minHeight: Self.dayCellHeight, alignment: .top)
                .background {
                    if day.isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(WoniColor.base15)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("main.calendar.day.\(day.day ?? 0)")
            .accessibilityAddTraits(day.isSelected ? .isSelected : [])

            // 오늘 표식은 원 배경으로만 그려져 접근성 트리에 없다. 오늘인 셀에만 값을 붙인다.
            if day.isToday {
                cell.accessibilityValue(Text(WoniStrings.today(language)))
            } else {
                cell
            }
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

/// 요일 헤더를 고정한 채 날짜 그리드만 갈아끼울 수 있게 슬롯으로 받는다. 월 전환 슬라이드는
/// 이 슬롯 안에서 일어나고, `main.calendar` 식별자와 스와이프 제스처는 요일 행을 포함한
/// 이 컨테이너에 남는다 — UI 테스트가 요일 헤더 띠를 드래그 시작점으로 계산한다.
struct MonthCalendarContainer<DayGrid: View>: View {
    let language: AppLanguage
    let handleSwipe: (_ horizontal: Double, _ vertical: Double) -> Void
    let dayGrid: DayGrid

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: calendarColumns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .woniFont(.small1)
                        .foregroundStyle(WoniColor.gray40)
                        .frame(maxWidth: .infinity)
                        .padding(2)
                }
            }

            dayGrid
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(WoniColor.gray00)
        .contentShape(Rectangle())
        .accessibilityIdentifier("main.calendar")
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
}
