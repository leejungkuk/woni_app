import CoreGraphics

enum DonutLabelLayout {
    struct Input: Equatable {
        let categoryID: Int
        let percent: Int
        let colorRank: Int
        let midAngleFraction: Double
    }

    struct Label: Equatable, Identifiable {
        let id: Int
        let percent: Int
        let isRight: Bool
        let edge: CGPoint
    }

    struct Leader: Equatable, Identifiable {
        let id: Int
        let colorRank: Int
        let start: CGPoint
        let anchor: CGPoint
        let control1: CGPoint
        let control2: CGPoint
    }

    struct Result: Equatable {
        let labels: [Label]
        let leaders: [Leader]
    }

    private static let labelRadius: CGFloat = 110
    private static let leaderStartRadius: CGFloat = 90
    private static let minSpacing: CGFloat = 16
    private static let labelGap: CGFloat = 5
    private static let verticalMargin: CGFloat = 9
    private static let handleRatio: CGFloat = 0.35

    static func make(inputs: [Input], center: CGPoint, height: CGFloat) -> Result {
        var groups: [[Input]] = []
        for input in inputs {
            if groups.last?.first?.percent == input.percent {
                groups[groups.count - 1].append(input)
            } else {
                groups.append([input])
            }
        }
        let initialLabels = groups.compactMap { members -> Label? in
            guard let first = members.first else { return nil }
            let sumCos = members.reduce(0.0) { $0 + cos(angle($1)) }
            let sumSin = members.reduce(0.0) { $0 + sin(angle($1)) }
            let groupAngle = hypot(sumCos, sumSin) < 1e-9 ? angle(first) : atan2(sumSin, sumCos)
            return Label(
                id: first.categoryID,
                percent: first.percent,
                isRight: cos(groupAngle) >= 0,
                edge: CGPoint(x: center.x, y: center.y + CGFloat(sin(groupAngle)) * labelRadius)
            )
        }
        let labels = [true, false].flatMap { isRight in
            stack(initialLabels.filter { $0.isRight == isRight }, center: center, height: height)
        }
        let leaders = groups.flatMap { members -> [Leader] in
            guard let label = labels.first(where: { $0.id == members.first?.categoryID }) else { return [] }
            return members.map { leader(for: $0, label: label, center: center) }
        }
        return Result(labels: labels, leaders: leaders)
    }

    private static func angle(_ input: Input) -> Double {
        input.midAngleFraction * 2 * .pi - .pi / 2
    }

    private static func stack(_ labels: [Label], center: CGPoint, height: CGFloat) -> [Label] {
        let sorted = labels.enumerated().sorted {
            if $0.element.edge.y == $1.element.edge.y { return $0.offset < $1.offset }
            return $0.element.edge.y < $1.element.edge.y
        }.map(\.element)
        let spacing = sorted.count <= 1 ? minSpacing
            : min(minSpacing, (height - 2 * verticalMargin) / CGFloat(sorted.count - 1))
        var positions = sorted.map { min(max($0.edge.y, verticalMargin), height - verticalMargin) }
        for index in positions.indices.dropFirst() {
            positions[index] = max(positions[index], positions[index - 1] + spacing)
        }
        if let last = positions.last {
            positions[positions.count - 1] = min(last, height - verticalMargin)
        }
        for index in stride(from: positions.count - 2, through: 0, by: -1) {
            positions[index] = min(positions[index], positions[index + 1] - spacing)
        }
        return zip(sorted, positions).map { label, y in
            let dy = y - center.y
            let dx = abs(dy) >= labelRadius ? 0 : sqrt(labelRadius * labelRadius - dy * dy)
            return Label(
                id: label.id,
                percent: label.percent,
                isRight: label.isRight,
                edge: CGPoint(x: center.x + (label.isRight ? dx : -dx), y: y)
            )
        }
    }

    private static func leader(for input: Input, label: Label, center: CGPoint) -> Leader {
        let cosine = CGFloat(cos(angle(input)))
        let sine = CGFloat(sin(angle(input)))
        let start = CGPoint(x: center.x + cosine * leaderStartRadius, y: center.y + sine * leaderStartRadius)
        let anchor = CGPoint(x: label.edge.x + (label.isRight ? -labelGap : labelGap), y: label.edge.y)
        let handle = hypot(anchor.x - start.x, anchor.y - start.y) * handleRatio
        return Leader(
            id: input.categoryID,
            colorRank: input.colorRank,
            start: start,
            anchor: anchor,
            control1: CGPoint(x: start.x + cosine * handle, y: start.y + sine * handle),
            control2: CGPoint(x: anchor.x + (label.isRight ? -handle : handle), y: anchor.y)
        )
    }
}
