import SwiftUI

/// Figma 디자인 시스템 "Popup_picker" 재확인(2026-07-04) — 연/월 휠피커.
/// 캘린더 위에 겹치는 중앙 모달, 배경 딤 처리. 실제 컴포넌트를 다시 보니
/// 상단에 현재 값 타이틀 + 휠 뒤에 Base15 선택 하이라이트 바 + 하단 취소/저장 버튼이 있음
/// (예전 텍스트 메모엔 "cancel/save 버튼 없음"이라고 돼 있었는데, Figma 컴포넌트가 그 사이 바뀐 것으로 보임 —
/// 최신 컴포넌트 기준으로 구현). 취소/바깥 탭 시 변경 취소, 저장 눌러야 반영됨.
struct YearMonthPickerOverlay: View {
    let initialYear: Int
    let initialMonth: Int
    let years: ClosedRange<Int>
    /// 해마다 고를 수 있는 달. 예산 탭은 끝 해에서 범위 밖 달을 휠에 넣지 않는다 — `저장` 에 비활성 상태가 없다.
    let months: (_ year: Int) -> ClosedRange<Int>
    let saveColor: Color
    let language: AppLanguage
    var onSave: (_ year: Int, _ month: Int) -> Void
    var onCancel: () -> Void

    @State private var year: Int
    @State private var month: Int

    init(
        initialYear: Int,
        initialMonth: Int,
        years: ClosedRange<Int>,
        saveColor: Color,
        language: AppLanguage = .ko,
        months: @escaping (_ year: Int) -> ClosedRange<Int> = { _ in 1 ... 12 },
        onSave: @escaping (Int, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialYear = initialYear
        self.initialMonth = initialMonth
        self.years = years
        self.months = months
        self.saveColor = saveColor
        self.language = language
        self.onSave = onSave
        self.onCancel = onCancel
        _year = State(initialValue: initialYear)
        _month = State(initialValue: initialMonth)
    }

    /// 휠 한 줄 높이(DS `Popup_picker` 444:5221). 휠은 5줄이라 가운데 줄 위·아래가 각 2줄이다.
    private let rowHeight: CGFloat = 52

    /// 올해(서울 gregorian) ±10 년. 처음 해가 그 밖이면 그 해까지 넓힌다.
    static func defaultYears(including initialYear: Int, now: Date = .now) -> ClosedRange<Int> {
        let currentYear = WoniDateFormat.defaultCalendar.component(.year, from: now)
        return min(currentYear - 10, initialYear) ... max(currentYear + 10, initialYear)
    }

    /// 해를 바꿔 고른 달이 새 범위 밖이면 범위 안의 가장 가까운 달.
    nonisolated static func clampedMonth(_ month: Int, in range: ClosedRange<Int>) -> Int {
        min(max(month, range.lowerBound), range.upperBound)
    }

    func monthItems(inYear year: Int) -> [Int] {
        Array(months(year))
    }

    var body: some View {
        ZStack {
            WoniColor.gray100.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                Text(verbatim: WoniDateFormat.monthTitle(year: year, month: month, language: language))
                    .woniFont(.body1)
                    .foregroundStyle(WoniColor.gray100)
                    .padding(.bottom, 16)

                ZStack {
                    // Figma: 선택 하이라이트는 각진 사각형(radius 없음).
                    Rectangle()
                        .fill(WoniColor.base15)
                        .frame(height: rowHeight)

                    HStack(spacing: 0) {
                        WheelColumn(
                            items: Array(years),
                            selection: $year
                        ) { "\($0)\(WoniStrings.yearSuffix(language))" }
                        WheelColumn(items: monthItems(inYear: year), selection: $month) { monthLabel($0) }
                    }
                    .onChange(of: year) { _, newYear in
                        month = Self.clampedMonth(month, in: months(newYear))
                    }

                    wheelFade
                }
                .frame(height: rowHeight * 5)
                .clipped()

                HStack(spacing: 8) {
                    Button(action: onCancel) {
                        Text(WoniStrings.pickerCancel(language))
                            .woniFont(.body3)
                            .foregroundStyle(WoniColor.gray80)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay {
                                Capsule().stroke(WoniColor.base20, lineWidth: 1)
                            }
                            // 안이 비어 테두리·글자만 눌렸다(`.plain` 은 칠한 곳만 받는다). 캡슐 전체를 누름 영역으로 둔다.
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("yearMonthPicker.cancel")

                    Button {
                        onSave(year, month)
                    } label: {
                        Text(WoniStrings.pickerSave(language))
                            .woniFont(.body2)
                            .foregroundStyle(WoniColor.base10)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(saveColor)
                            .clipShape(Capsule())
                            .woniShadow(.shadow1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("yearMonthPicker.save")
                }
                .padding(16)
                .overlay(alignment: .top) {
                    Rectangle().fill(WoniColor.base20).frame(height: 1)
                }
            }
            .padding(.top, 16)
            .frame(maxWidth: 360)
            .background {
                // 카드에 걸면 휠이 화면 밖에 미리 그린 행까지 프레임에 합쳐진다(실측 높이 528).
                // 자식 없는 바탕에 걸어 식별자 프레임이 카드와 같게 한다.
                WoniColor.gray00
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("yearMonthPicker")
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .woniShadow(.shadow1)
            .padding(.horizontal, 16)
        }
        // 딤 배경은 터치만 막는다. 이 트레이트가 없으면 VoiceOver로는 뒤 화면을 그대로 조작할 수
        // 있어, 같은 피커가 접근성 사용 여부에 따라 다르게 동작한다(WoniConfirmDialog 와 같다).
        // 컨테이너로 먼저 묶는다 — 묶지 않으면 트레이트가 자식마다 붙어 `yearMonthPicker` 바탕 요소가 트리에서 사라진다(실측).
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .transition(.opacity)
    }
}

private extension YearMonthPickerOverlay {
    /// 휠 위·아래 2줄(각 104)을 흰색에서 가운데 쪽으로 투명하게 덮는다. 휠 드래그·행 탭은 통과시킨다.
    var wheelFade: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [WoniColor.gray00, WoniColor.gray00.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: rowHeight * 2)
            Spacer(minLength: rowHeight)
            LinearGradient(
                colors: [WoniColor.gray00.opacity(0), WoniColor.gray00],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: rowHeight * 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    func monthLabel(_ month: Int) -> String {
        switch language {
        case .ko:
            return "\(month)\(WoniStrings.monthSuffix(language))"
        case .en:
            return WoniDateFormat.monthName(month: month, calendar: WoniDateFormat.defaultCalendar)
        }
    }
}
