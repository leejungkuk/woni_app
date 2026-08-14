import SwiftUI

/// 요일 헤더와 날짜 셀이 같은 열 위에 놓여야 한다. 두 타입의 공통 사양이라 파일 스코프에 둔다.
private let calendarColumns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: 7)

struct MonthCalendarGrid: View {
    static let dayCellHeight: CGFloat = 62
    static let dayRowSpacing: CGFloat = 2

    let days: [MainCalendarDay]
    let language: AppLanguage
    /// 표시 월이 아닌 슬롯(페이저 이웃·정착 중 그리드)의 셀은 접근성에서 빠지고 식별자도 내지
    /// 않는다 — `main.calendar.day.N` 유일성이 깨지면 UI 테스트의 단일 조회가 전부 실패한다.
    /// `accessibilityHidden`만으로는 XCUITest 조회에서 사라지지 않는 것을 실측으로 확인했다.
    var isDecorative = false
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
            .accessibilityIdentifier(isDecorative ? "" : "main.calendar.day.\(day.day ?? 0)")
            .accessibilityAddTraits(day.isSelected ? .isSelected : [])
            .accessibilityHidden(isDecorative)

            // 오늘 표식은 원 배경으로만 그려져 접근성 트리에 없다. 오늘인 셀에만 값을 붙인다.
            if day.isToday, !isDecorative {
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

/// 스와이프 판정은 기하만으로 결정된다. View 밖에 두어 유닛 테스트로 고정한다.
enum MonthPagingRule {
    enum Axis {
        case horizontal
        case vertical
    }

    enum Commit: Equatable {
        case cancel
        /// 이동할 월 수(+1 다음 달, -1 이전 달).
        case move(Int)
    }

    static let verticalThreshold: CGFloat = 40

    /// 동률은 가로 우선 — 대각 드래그를 월 이동으로 삼키지 않던 종전 규칙을 유지한다.
    static func axis(translation: CGSize) -> Axis {
        abs(translation.width) >= abs(translation.height) ? .horizontal : .vertical
    }

    /// 놓는 순간의 위치와 투영 종점으로 판정하는 네이티브 페이징 규칙.
    static func horizontalCommit(translation: CGFloat, predictedEnd: CGFloat, width: CGFloat) -> Commit {
        // 끌고 가다 반대로 되튕겨 놓으면(부호 불일치) 사용자 의도는 취소다.
        // 폭을 모르는 프레임에서는 반 폭 판정 자체가 성립하지 않으므로 역시 취소한다.
        guard width > 0, translation * predictedEnd > 0 else {
            return .cancel
        }
        guard max(abs(translation), abs(predictedEnd)) >= width / 2 else {
            return .cancel
        }

        return .move(translation < 0 ? 1 : -1)
    }

    static func verticalCommit(translation: CGFloat) -> Commit {
        guard abs(translation) >= verticalThreshold else {
            return .cancel
        }

        return .move(translation < 0 ? 1 : -1)
    }

    /// `interpolatingSpring`의 초기 속도는 "남은 거리 대비 초당 비율"이다. 정착 목표는 항상 0이라
    /// 부호 있는 남은 거리 `0 - remaining`으로 나눠 목표 방향이 양수가 되게 정규화한다.
    static func settleVelocity(velocity: CGFloat, remaining: CGFloat) -> Double {
        guard remaining != 0 else {
            return 0
        }

        return Double(-velocity / remaining)
    }
}

/// 요일 헤더를 고정한 채 날짜 그리드만 갈아끼울 수 있게 슬롯으로 받는다. 월 전환 페이징은
/// 이 슬롯 안에서 일어나고, `main.calendar` 식별자와 드래그 영역은 요일 행을 포함한
/// 이 컨테이너에 남는다 — UI 테스트가 요일 헤더 띠를 드래그 시작점으로 계산한다.
/// 제스처 자체는 추종·정착 상태를 가진 MainView가 부착한다.
struct MonthCalendarContainer<DayGrid: View>: View {
    let language: AppLanguage
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
    }

    private var weekdaySymbols: [String] {
        WoniStrings.weekdaysShort(language)
    }
}
