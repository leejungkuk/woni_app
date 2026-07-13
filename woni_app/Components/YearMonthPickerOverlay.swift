import SwiftUI

/// Figma 디자인 시스템 "Popup_picker" 재확인(2026-07-04) — 연/월 휠피커.
/// 캘린더 위에 겹치는 중앙 모달, 배경 딤 처리. 실제 컴포넌트를 다시 보니
/// 상단에 현재 값 타이틀 + 휠 뒤에 Base20 선택 하이라이트 바 + 하단 취소/저장 버튼이 있음
/// (예전 텍스트 메모엔 "cancel/save 버튼 없음"이라고 돼 있었는데, Figma 컴포넌트가 그 사이 바뀐 것으로 보임 —
/// 최신 컴포넌트 기준으로 구현). 취소/바깥 탭 시 변경 취소, 저장 눌러야 반영됨.
struct YearMonthPickerOverlay: View {
    let initialYear: Int
    let initialMonth: Int
    let language: AppLanguage
    var onSave: (_ year: Int, _ month: Int) -> Void
    var onCancel: () -> Void

    @State private var year: Int
    @State private var month: Int

    init(
        initialYear: Int,
        initialMonth: Int,
        language: AppLanguage = .ko,
        onSave: @escaping (Int, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialYear = initialYear
        self.initialMonth = initialMonth
        self.language = language
        self.onSave = onSave
        self.onCancel = onCancel
        years = Self.yearRange(including: initialYear)
        _year = State(initialValue: initialYear)
        _month = State(initialValue: initialMonth)
    }

    private let months = Array(1 ... 12)
    private let years: [Int]

    private static let currentYear = Calendar.current.component(.year, from: .now)

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
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
                        .fill(WoniColor.base20)
                        .frame(height: 44)

                    HStack(spacing: 0) {
                        WheelColumn(
                            items: years,
                            selection: $year
                        ) { "\($0)\(WoniStrings.yearSuffix(language))" }
                        WheelColumn(items: months, selection: $month) { monthLabel($0) }
                    }
                }
                .frame(height: 220)
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
                    }
                    .buttonStyle(.plain)

                    Button {
                        onSave(year, month)
                    } label: {
                        Text(WoniStrings.pickerSave(language))
                            .woniFont(.body2)
                            .foregroundStyle(WoniColor.base10)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(WoniColor.terracotta100)
                            .clipShape(Capsule())
                            .woniShadow(.shadow1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .overlay(alignment: .top) {
                    Rectangle().fill(WoniColor.base20).frame(height: 1)
                }
            }
            .padding(.top, 16)
            .frame(width: 328)
            .background(WoniColor.gray00)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .woniShadow(.shadow1)
        }
        .transition(.opacity)
    }
}

private extension YearMonthPickerOverlay {
    static func yearRange(including initialYear: Int) -> [Int] {
        let lowerBound = min(currentYear - 10, initialYear)
        let upperBound = max(currentYear + 10, initialYear)
        return Array(lowerBound ... upperBound)
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
