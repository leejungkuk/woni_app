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

    private static let canvasHeight: CGFloat = 224
    private let chartDiameter: CGFloat = 176

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: Self.canvasHeight / 2)
            let layout = DonutLabelLayout.make(inputs: labelInputs, center: center, height: Self.canvasHeight)
            ZStack {
                ForEach(slices, id: \.categoryID) { slice in
                    DonutRingSegment(start: slice.start, end: slice.end, thickness: 28)
                        .fill(WoniColor.chartColor(forRank: item(for: slice).colorRank))
                        .frame(width: chartDiameter, height: chartDiameter)
                        .position(center)
                }
                ForEach(layout.leaders) { leader in
                    Path { path in
                        path.move(to: leader.start)
                        path.addCurve(to: leader.anchor, control1: leader.control1, control2: leader.control2)
                    }
                    .stroke(WoniColor.chartColor(forRank: leader.colorRank),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                ForEach(layout.labels) { label in
                    Text("\(label.percent)%")
                        .woniFont(.small2)
                        .foregroundStyle(WoniColor.gray80)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 28, alignment: label.isRight ? .leading : .trailing)
                        .position(x: label.edge.x + (label.isRight ? 14 : -14), y: label.edge.y)
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
                .position(center)
            }
        }
        .frame(height: Self.canvasHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("report.donut")
    }

    /// 세로 스택이 라벨 겹침을 막는다. 임계는 너무 작아 무의미한 조각만 제외한다.
    static func showsPercentLabel(percent: Int) -> Bool {
        percent >= 4
    }

    private var labelInputs: [DonutLabelLayout.Input] {
        slices.filter { Self.showsPercentLabel(percent: item(for: $0).percent) }.map { slice in
            let category = item(for: slice)
            return DonutLabelLayout.Input(
                categoryID: category.categoryID,
                percent: category.percent,
                colorRank: category.colorRank,
                midAngleFraction: slice.midAngleFraction
            )
        }
    }

    private func item(for slice: ReportDonutSlice) -> ReportCategoryItem {
        guard let item = items.first(where: { $0.categoryID == slice.categoryID }) else {
            preconditionFailure("A donut slice must have a matching category item")
        }
        return item
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
