//
//  BudgetBreakdownCards.swift
//  woni_app
//

import SwiftUI

/// 총액 카드 아래 카테고리·결제수단 카드. 무엇을 보일지는 `BudgetBreakdownPresentation` 이 정하고
/// 여기서는 그리기만 한다. 카드 규격(배경·radius·그림자·여백·간격)은 총액 카드와 같다.
struct BudgetBreakdownCards: View {
    let presentation: BudgetBreakdownPresentation

    var body: some View {
        VStack(spacing: 12) {
            if let categoryCard = presentation.categoryCard {
                BudgetBreakdownCard(title: presentation.categoryTitle) {
                    ForEach(categoryCard.rows, id: \.categoryID) { categoryRow in
                        BudgetBreakdownRowView(row: categoryRow.row)
                            .accessibilityIdentifier("budget.categoryRow.\(categoryRow.categoryID)")
                    }
                    BudgetBreakdownRowView(row: categoryCard.otherCategories)
                        .accessibilityIdentifier("budget.otherCategoriesRow")
                }
                .accessibilityIdentifier("budget.categoryCard")
            }
            BudgetBreakdownCard(title: presentation.paymentTitle) {
                ForEach(presentation.paymentRows, id: \.paymentGroup) { paymentRow in
                    BudgetBreakdownRowView(row: paymentRow.row)
                        .accessibilityIdentifier("budget.paymentRow.\(paymentRow.paymentGroup.rawValue)")
                }
            }
            .accessibilityIdentifier("budget.paymentCard")
        }
    }
}

/// 제목(14pt `gray60`)과 줄들. 줄 사이 12.
private struct BudgetBreakdownCard<Rows: View>: View {
    let title: String
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray60)
            rows
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(WoniColor.gray00)
                .woniShadow(.shadow1)
        }
        .accessibilityElement(children: .contain)
    }
}

/// 한 줄 = 이름·금액 줄(22) + 간격 8 + 막대(8). 넘은 줄(카테고리·결제수단)은 막대 아래 8 띄워 넘은 돈 문구.
/// VoiceOver 는 이름·금액·문구를 한 번에 읽는다. 막대는 읽지 않는다 — 같은 정보를 금액 글자가 전한다.
private struct BudgetBreakdownRowView: View {
    let row: BudgetBreakdownPresentation.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(row.name)
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.gray100)
                if let tag = row.tag {
                    Text(tag)
                        .woniFont(.small1)
                        .foregroundStyle(WoniColor.gray60)
                }
                Spacer(minLength: 8)
                Text(row.amountText)
                    .woniFont(.body3)
                    .foregroundStyle(row.amountColor)
                    // 긴 이름은 줄을 바꾸고 금액은 자르지 않는다.
                    .fixedSize()
                    .layoutPriority(1)
            }
            if let bar = row.bar {
                BudgetSubBar(bar: bar, color: row.barColor)
            }
            if let overText = row.overText {
                Text(overText)
                    .woniFont(.small1)
                    .foregroundStyle(WoniColor.terracotta100)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 하위 막대(두께 8, 트랙 `gray10`). 넘으면 예산 눈금에 폭 2 의 틈을 두고 오른쪽을 `terracotta110` 으로 칠한다.
/// 오늘 표시선은 두지 않는다 — 몰아 쓰는 항목에서 거짓 경고가 된다.
private struct BudgetSubBar: View {
    let bar: BudgetBarFill
    let color: Color

    private static let gapWidth: CGFloat = 2

    var body: some View {
        let thickness = BudgetBreakdownPresentation.barThickness
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(WoniColor.gray10)
                if let tickX = bar.tickX(width: width, thickness: thickness) {
                    Rectangle()
                        .fill(color)
                        .frame(width: tickX)
                    Rectangle()
                        .fill(WoniColor.terracotta110)
                        .frame(width: width - tickX)
                        .offset(x: tickX)
                    if tickX > 0 {
                        Rectangle()
                            .fill(WoniColor.gray00)
                            .frame(width: Self.gapWidth)
                            .offset(x: tickX - Self.gapWidth / 2)
                    }
                } else {
                    Capsule()
                        .fill(color)
                        .frame(width: width * bar.ratio)
                }
            }
            .frame(height: thickness)
            .clipShape(Capsule())
        }
        .frame(height: thickness)
        .accessibilityHidden(true)
    }
}
