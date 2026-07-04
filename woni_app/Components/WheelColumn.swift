import SwiftUI

/// 네이티브 `Picker(.wheel)`을 나란히 2개 쓰면 각 컬럼마다 시스템이 자체 선택 하이라이트를
/// 그려서 우리가 그린 Base20 박스랑 겹쳐 "선택이 2번씩" 보이는 문제가 있었음.
/// 그래서 네이티브 Picker 대신 ScrollView 기반 커스텀 휠로 교체 — 하이라이트 박스가 정확히 1개만 그려지고
/// 선택된 행의 폰트(Body1/진하게)도 Figma 스펙대로 직접 제어 가능.
struct WheelColumn<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String
    /// Figma Popup_picker 재확인 결과 화면에 5줄(선택 포함 위아래 2개씩)이 보임.
    var visibleRowCount: Int = 5

    private let rowHeight: CGFloat = 44

    /// 선택된 항목에서 몇 칸 떨어져 있는지에 따라 Figma처럼 위아래 끝으로 갈수록 옅어지게(휠 느낌).
    private func opacity(distanceFromSelection distance: Int) -> Double {
        switch distance {
        case 0: return 1
        case 1: return 0.55
        default: return 0.3
        }
    }

    var body: some View {
        let selectedIndex = items.firstIndex(of: selection) ?? 0

        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    let distance = abs(index - selectedIndex)
                    Text(label(item))
                        .woniFont(item == selection ? .body1 : .body2)
                        .foregroundStyle(WoniColor.gray100)
                        .opacity(opacity(distanceFromSelection: distance))
                        .frame(height: rowHeight)
                        .id(item)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: Binding<Item?>(get: { selection }, set: { if let newValue = $0 { selection = newValue } }))
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.vertical, rowHeight * CGFloat(visibleRowCount / 2), for: .scrollContent)
        .frame(height: rowHeight * CGFloat(visibleRowCount))
    }
}
