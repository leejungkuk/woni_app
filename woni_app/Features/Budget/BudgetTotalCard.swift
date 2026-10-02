//
//  BudgetTotalCard.swift
//  woni_app
//

import SwiftUI

/// 예산 탭 총액 카드. 무엇을 보일지는 `BudgetTotalPresentation` 이 정하고 여기서는 그리기만 한다.
struct BudgetTotalCard: View {
    let presentation: BudgetTotalPresentation

    /// (i) 말풍선. 누를 때만 열린다 — "처음 한 번" 띄우기는 기기마다 달라진다.
    @State private var isInfoOpen = false
    @State private var heroLabelWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroLabelRow
                // 말풍선이 아래 숫자·막대 위에 그려지게 한다.
                .zIndex(1)
            heroAmountRow
            HStack {
                Text(presentation.usedOverBudgetText)
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray80)
                Spacer()
                Text(presentation.statusText)
                    .woniFont(.body3)
                    .foregroundStyle(presentation.statusColor)
                    .accessibilityIdentifier("budget.status")
            }
            BudgetTotalBar(presentation: presentation)
            if let dailyText = presentation.dailyText {
                Text(dailyText)
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray80)
                    .accessibilityIdentifier("budget.daily")
            }
            ForEach(presentation.missingLines, id: \.self) { line in
                Text(line)
                    .woniFont(.small1)
                    .foregroundStyle(WoniColor.gray60)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(WoniColor.gray00)
                .woniShadow(.shadow1)
        }
        // 말풍선이 열려 있으면 카드 어디를 눌러도 닫힌다. 닫혀 있을 때는 이 제스처를 끈다.
        .gesture(TapGesture().onEnded { isInfoOpen = false }, including: isInfoOpen ? .all : .subviews)
        .onChange(of: presentation.showsInfo) { _, showsInfo in
            if !showsInfo {
                isInfoOpen = false
            }
        }
        .onDisappear { isInfoOpen = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budget.totalCard")
    }

    private var heroLabelRow: some View {
        HStack(spacing: 4) {
            Text(presentation.heroLabel)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray60)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { heroLabelWidth = $0 }
            if presentation.showsInfo {
                Button {
                    isInfoOpen.toggle()
                } label: {
                    BudgetInfoIcon()
                }
                .buttonStyle(.plain)
                // 아이콘은 16 이지만 누르는 자리는 44×44 다.
                .contentShape(Rectangle().inset(by: -14))
                .accessibilityLabel(presentation.infoText)
                .accessibilityIdentifier("budget.info")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottomLeading) {
            if isInfoOpen, presentation.showsInfo {
                BudgetInfoBubble(text: presentation.infoText, tailCenterX: heroLabelWidth + 4 + BudgetInfoIcon.size / 2)
                    // 말풍선 위쪽을 줄 아래쪽에 맞춘다.
                    .alignmentGuide(.bottom) { $0[.top] }
                    .onTapGesture { isInfoOpen = false }
            }
        }
    }

    private var heroAmountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(presentation.heroText)
                .woniFont(.h2)
                .foregroundStyle(presentation.heroColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityIdentifier("budget.hero")
            Text(presentation.currencyCode)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray80)
        }
    }
}

/// 전체 막대(두께 14). 넘으면 예산 눈금에 폭 2 의 틈을 두고 오른쪽을 넘친 색으로 칠한다.
/// 이번 달이면 오늘 자리에 틈과 위쪽 포인터를 둔다. VoiceOver 는 읽지 않는다 — 같은 정보는 문구가 전한다.
private struct BudgetTotalBar: View {
    let presentation: BudgetTotalPresentation

    private static let gapWidth: CGFloat = 2
    private static let pointerGap: CGFloat = 4

    var body: some View {
        let thickness = BudgetTotalPresentation.barThickness
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(WoniColor.gray10)
                    if let tickX = presentation.bar.tickX(width: width, thickness: thickness) {
                        Rectangle()
                            .fill(WoniColor.terracotta100)
                            .frame(width: tickX)
                        Rectangle()
                            .fill(WoniColor.terracotta110)
                            .frame(width: width - tickX)
                            .offset(x: tickX)
                        if tickX > 0 {
                            gap(at: tickX)
                        }
                    } else {
                        Capsule()
                            .fill(WoniColor.terracotta100)
                            .frame(width: width * presentation.bar.ratio)
                    }
                    if let markerX = presentation.todayMarkerX(barWidth: width) {
                        gap(at: markerX)
                    }
                }
                .frame(height: thickness)
                .clipShape(Capsule())

                if let markerX = presentation.todayMarkerX(barWidth: width) {
                    TodayPointer()
                        .fill(WoniColor.gray80)
                        .frame(width: TodayPointer.size.width, height: TodayPointer.size.height)
                        .offset(
                            x: markerX - TodayPointer.size.width / 2,
                            y: -(Self.pointerGap + TodayPointer.size.height)
                        )
                }
            }
        }
        .frame(height: thickness)
        .accessibilityHidden(true)
    }

    private func gap(at x: CGFloat) -> some View {
        Rectangle()
            .fill(WoniColor.gray00)
            .frame(width: Self.gapWidth)
            .offset(x: x - Self.gapWidth / 2)
    }
}

/// 막대 위 오늘 자리 포인터 — 아래를 가리키는 둥근 삼각형 8×5.
private struct TodayPointer: Shape {
    static let size = CGSize(width: 8, height: 5)

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 1
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addArc(tangent1End: topRight, tangent2End: tip, radius: radius)
        path.addArc(tangent1End: tip, tangent2End: topLeft, radius: radius)
        path.addArc(tangent1End: topLeft, tangent2End: topRight, radius: radius)
        path.closeSubpath()
        return path
    }
}

/// (i) — 시안 부품 `ai_infoIcon`(`2061:12193`): 16×16, 원 테두리 선 1.5, 가운데 i, `gray80`.
private struct BudgetInfoIcon: View {
    static let size: CGFloat = 16
    private static let lineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            Circle()
                .inset(by: Self.lineWidth / 2)
                .stroke(lineWidth: Self.lineWidth)
            VStack(spacing: 1.5) {
                Circle()
                    .frame(width: Self.lineWidth, height: Self.lineWidth)
                Capsule()
                    .frame(width: Self.lineWidth, height: 5)
            }
        }
        .foregroundStyle(WoniColor.gray80)
        .frame(width: Self.size, height: Self.size)
    }
}

/// (i) 아래 말풍선. 바탕·글자색·그림자는 토스트(`WoniToast`)와 같고 모서리는 24 다.
/// 폭은 카드 안쪽이고 꼬리(12×6)는 (i) 가운데를 가리킨다.
private struct BudgetInfoBubble: View {
    let text: String
    let tailCenterX: CGFloat

    private static let tailSize = CGSize(width: 12, height: 6)
    private static let background = WoniColor.gray100.opacity(0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BubbleTail()
                .fill(Self.background)
                .frame(width: Self.tailSize.width, height: Self.tailSize.height)
                .offset(x: tailCenterX - Self.tailSize.width / 2)
            Text(text)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.base10)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Self.background, in: RoundedRectangle(cornerRadius: 24))
        }
        // 줄 높이만큼만 제안받아도 글자 높이대로 아래로 펼친다.
        .fixedSize(horizontal: false, vertical: true)
        .woniShadow(.shadow1)
    }
}

/// 말풍선 꼬리 — 위를 가리키는 삼각형.
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
