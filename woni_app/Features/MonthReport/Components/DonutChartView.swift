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

                Text("\(item(for: slice).percent)%")
                    .woniFont(.small2)
                    .foregroundStyle(WoniColor.gray80)
                    .position(labelPosition(for: slice))
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
            x: chartCenter.x + cos(angle) * labelRadius,
            y: chartCenter.y + sin(angle) * labelRadius
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
