import SwiftUI

struct MonthHeaderView: View {
    let monthTitle: String
    let onOpenMonthPicker: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpenMonthPicker) {
                HStack(spacing: 0) {
                    Text(monthTitle)
                        .woniFont(.h4)
                        .foregroundStyle(WoniColor.gray100)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WoniColor.gray100)
                        .frame(width: 24, height: 24)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("main.monthTitle")

            Spacer(minLength: 0)
        }
        // 오른쪽 칸은 비어 있다(시안 `ai_01_탭바_가계부` — 설정은 탭바로 옮겼다).
        // 그 칸의 버튼 높이 44 를 남겨 달 제목 자리가 움직이지 않게 한다.
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(WoniColor.gray00)
    }
}
