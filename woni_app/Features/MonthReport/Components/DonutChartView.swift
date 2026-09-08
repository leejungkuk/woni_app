//
//  DonutChartView.swift
//  woni_app
//

import SwiftUI

struct DonutChartView: View {
    let slices: [ReportDonutSlice]
    let items: [ReportCategoryItem]
    let modeTitle: String
    let modeTitleColor: Color
    let amountText: String
    let accessibilitySummary: String

    private let canvasSize = CGSize(width: 204, height: 188)
    private let chartDiameter: CGFloat = 148
    private let labelRadius: CGFloat = 88

    var body: some View {
        ZStack {
            ForEach(slices, id: \.categoryID) { slice in
                DonutRingSegment(start: slice.start, end: slice.end, thickness: 29)
                    .fill(WoniColor.chartColor(forRank: item(for: slice).colorRank))
                    .frame(width: chartDiameter, height: chartDiameter)
                    .position(chartCenter)

                if Self.showsPercentLabel(percent: item(for: slice).percent) {
                    Text("\(item(for: slice).percent)%")
                        .woniFont(.small2)
                        .foregroundStyle(WoniColor.gray80)
                        .position(labelPosition(for: slice))
                }
            }

            VStack(spacing: 0) {
                Text(modeTitle)
                    .woniFont(.small1)
                    .foregroundStyle(modeTitleColor)
                Text(amountText)
                    .woniFont(.body1)
                    .foregroundStyle(WoniColor.gray100)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(width: 84)
            .position(chartCenter)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("report.donut")
    }

    /// 표시 퍼센트 4% 미만 조각은 주변 % 라벨을 생략한다(정확한 값은 목록 행이 보여준다).
    /// 4%면 실제 비율 ≥ 3.5%라 인접 라벨 중심 간격이 반경 88 기준 19.3pt로,
    /// 10pt 폰트 한 자리 라벨의 글리프 상자(≈11.5×10pt, 투명 패딩 제외) 대각선 15.2pt보다 커서 어느 각도에서도 겹치지 않는다.
    static func showsPercentLabel(percent: Int) -> Bool {
        percent >= 4
    }

    private var chartCenter: CGPoint {
        CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    }

    private func item(for slice: ReportDonutSlice) -> ReportCategoryItem {
        guard let item = items.first(where: { $0.categoryID == slice.categoryID }) else {
            preconditionFailure("A donut slice must have a matching category item")
        }
        return item
    }

    private func labelPosition(for slice: ReportDonutSlice) -> CGPoint {
        let angle = slice.midAngleFraction * 2 * Double.pi - Double.pi / 2
        return CGPoint(
            x: chartCenter.x + CGFloat(cos(angle)) * labelRadius,
            y: chartCenter.y + CGFloat(sin(angle)) * labelRadius
        )
    }
}

private struct DonutRingSegment: Shape {
    let start: Double
    let end: Double
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius - thickness
        let startAngle = Angle.radians(start * 2 * Double.pi - Double.pi / 2)
        let endAngle = Angle.radians(end * 2 * Double.pi - Double.pi / 2)
        var path = Path()

        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}
