//
//  DonutChartViewTests.swift
//  woni_appTests
//

import CoreGraphics
import Testing
@testable import woni_app

@MainActor
struct DonutChartViewTests {
    @Test("도넛 주변 % 라벨은 표시 퍼센트 4% 이상인 조각에만 붙는다")
    func percentLabelStartsAtFourPercent() {
        #expect(!DonutChartView.showsPercentLabel(percent: 3))
        #expect(DonutChartView.showsPercentLabel(percent: 4))
    }

    private let center = CGPoint(x: 201, y: 112)
    private let height: CGFloat = 224

    @Test("연속 동률은 라벨을 공유하고 지시선은 조각마다 유지한다")
    func equalPercentsShareLabel() throws {
        let inputs = [input(0, percent: 40, degrees: -30), input(1, percent: 40, degrees: 30),
                      input(2, percent: 20, degrees: 180)]
        let result = layout(inputs)
        #expect(result.labels.count == 2)
        #expect(result.leaders.count == 3)
        let label = try #require(result.labels.first { $0.id == 0 })
        #expect(label.percent == 40)
        #expect(abs(label.edge.y - center.y) < 1e-6)
        #expect(abs(label.edge.x - center.x - 110) < 1e-6)
        let shared = result.leaders.filter { $0.id == 0 || $0.id == 1 }
        #expect(shared.count == 2)
        #expect(shared[0].anchor == shared[1].anchor)
    }

    @Test("3시와 9시 조각은 각각 오른쪽과 왼쪽에 배치한다")
    func separatesSides() throws {
        let result = layout([input(0, percent: 60, degrees: 0), input(1, percent: 40, degrees: 180)])
        let right = try #require(result.labels.first { $0.id == 0 })
        let left = try #require(result.labels.first { $0.id == 1 })
        #expect(right.isRight && right.edge.x > center.x)
        #expect(!left.isRight && left.edge.x < center.x)
    }

    @Test("한쪽에 몰린 라벨은 최소 16pt 간격으로 쌓는다")
    func stacksNearbyLabels() {
        let result = layout(clusteredInputs(count: 3))
        #expect(result.labels.count == 3)
        for (first, second) in zip(result.labels, result.labels.dropFirst()) {
            #expect(second.edge.y - first.edge.y >= 16)
        }
    }

    @Test("세로 이동 후 x를 다시 계산해 반경 110을 유지한다")
    func recalculatesCircleX() {
        let result = layout(clusteredInputs(count: 3))
        #expect(result.labels.count == 3)
        for label in result.labels {
            let dy = label.edge.y - center.y
            if abs(dy) >= 110 {
                #expect(label.edge.x == center.x)
            } else {
                #expect(abs(distance(label.edge, center) - 110) < 1e-6)
            }
        }
    }

    @Test("정원 13개는 경계 안에서 16pt 간격을 유지한다")
    func capacityFitsBounds() {
        let result = layout(clusteredInputs(count: 13))
        #expect(result.labels.count == 13)
        #expect(result.labels.map(\.id) == Array(0 ..< 13))
        for label in result.labels {
            #expect(label.edge.y >= 9 - 1e-6 && label.edge.y <= 215 + 1e-6)
        }
        for (first, second) in zip(result.labels, result.labels.dropFirst()) {
            #expect(abs(second.edge.y - first.edge.y - 16) < 1e-6)
        }
    }

    @Test("정원 초과 20개는 간격을 줄여 경계 안에 배치한다")
    func excessCapacityCompressesSpacing() {
        let result = layout(clusteredInputs(count: 20))
        #expect(result.labels.count == 20)
        for label in result.labels {
            #expect(label.edge.y >= 9 - 1e-6 && label.edge.y <= 215 + 1e-6)
        }
        for (first, second) in zip(result.labels, result.labels.dropFirst()) {
            #expect(second.edge.y > first.edge.y)
            #expect(abs(second.edge.y - first.edge.y - 206.0 / 19) < 1e-6)
        }
    }

    @Test("넓게 퍼진 라벨도 세로 경계와 좌우 위치를 유지한다")
    func wideSpanFitsBoundsWithoutCollapsingToCenter() {
        let inputs = (0 ..< 9).map {
            DonutLabelLayout.Input(
                categoryID: $0,
                percent: $0.isMultiple(of: 2) ? 11 : 12,
                colorRank: $0,
                midAngleFraction: (Double($0) + 0.5) / 9
            )
        }
        let result = layout(inputs)
        #expect(result.labels.count == 9)
        for label in result.labels {
            #expect(label.edge.y >= 9 && label.edge.y <= 215)
            #expect(label.isRight ? label.edge.x > center.x : label.edge.x < center.x)
        }
    }

    @Test("지시선은 반경 90에서 시작해 방사·수평 핸들로 연결한다")
    func leaderGeometry() throws {
        let result = layout([input(0, percent: 60, degrees: 30), input(1, percent: 40, degrees: 180)])
        for leader in result.leaders {
            let label = try #require(result.labels.first { $0.id == leader.id })
            let handle = distance(leader.anchor, leader.start) * 0.35
            #expect(leader.colorRank == leader.id)
            #expect(abs(distance(leader.start, center) - 90) < 1e-6)
            #expect(abs(distance(leader.control1, leader.start) - handle) < 1e-6)
            #expect(abs(leader.control1.x - leader.start.x - (leader.start.x - center.x) / 90 * handle) < 1e-6)
            #expect(abs(leader.control1.y - leader.start.y - (leader.start.y - center.y) / 90 * handle) < 1e-6)
            #expect(leader.anchor.y == label.edge.y)
            #expect(abs(leader.anchor.x - label.edge.x - (label.isRight ? -5 : 5)) < 1e-6)
            #expect(leader.control2.y == leader.anchor.y)
            #expect(abs(leader.control2.x - leader.anchor.x - (label.isRight ? -handle : handle)) < 1e-6)
            #expect(label.isRight ? leader.control2.x < leader.anchor.x : leader.control2.x > leader.anchor.x)
        }
    }

    @Test("50/50 벡터합 퇴화 시 첫 멤버 각도를 사용한다")
    func degenerateGroupUsesFirstAngle() throws {
        let result = layout([input(0, percent: 50, degrees: 180), input(1, percent: 50, degrees: 0)])
        #expect(result.labels.count == 1)
        #expect(result.leaders.count == 2)
        let label = try #require(result.labels.first)
        #expect(label.edge.x.isFinite && label.edge.y.isFinite)
        #expect(!label.isRight)
        #expect(abs(label.edge.x - (center.x - 110)) < 1e-6)
        #expect(abs(label.edge.y - center.y) < 1e-6)
        for leader in result.leaders {
            for point in [leader.start, leader.anchor, leader.control1, leader.control2] {
                #expect(point.x.isFinite && point.y.isFinite)
            }
        }
    }

    private func input(_ id: Int, percent: Int, degrees: Double) -> DonutLabelLayout.Input {
        DonutLabelLayout.Input(
            categoryID: id,
            percent: percent,
            colorRank: id,
            midAngleFraction: (degrees + 90) / 360
        )
    }

    private func clusteredInputs(count: Int) -> [DonutLabelLayout.Input] {
        (0 ..< count).map { input($0, percent: 100 - $0, degrees: 0) }
    }

    private func layout(_ inputs: [DonutLabelLayout.Input]) -> DonutLabelLayout.Result {
        DonutLabelLayout.make(inputs: inputs, center: center, height: height)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
}
