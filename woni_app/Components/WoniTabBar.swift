//
//  WoniTabBar.swift
//  woni_app
//

import SwiftUI

/// 하단 탭바 — 시안 `nav_bottom`(`ai_01_탭바_가계부` `1942:11922` · `ai_02_탭바_통계` `1942:12418`).
/// 칸 내용은 52, 바탕은 홈 인디케이터 영역까지 채운다.
struct WoniTabBar: View {
    let tabs: [AppTab]
    let selected: AppTab
    let language: AppLanguage
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .frame(height: 52)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WoniColor.base20)
                .frame(height: 1)
        }
        .background(WoniColor.gray00.ignoresSafeArea(edges: .bottom))
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = tab == selected
        return Button {
            onSelect(tab)
        } label: {
            // 홈 인디케이터 34 가 아래 여백 몫을 하므로 가운데가 아니라 위로 붙인다.
            VStack(spacing: 2) {
                Image(decorative: tab.iconName(selected: isSelected))
                    .frame(width: 24, height: 24)
                Text(tab.title(language))
                    .woniFont(.small1)
                    .foregroundStyle(isSelected ? WoniColor.gray100 : WoniColor.gray40)
            }
            .padding(.top, 6.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
