//
//  EntryTypeTabBar.swift
//  woni_app
//

import SwiftUI

/// 지출/수입 전환 탭. 관리·추가 화면이 같은 UI를 공유한다(2026-08-19 결정 — 진입 탭 고정 폐지).
struct EntryTypeTabBar: View {
    @Environment(AppLanguageStore.self) private var languageStore

    let selected: EntryType
    let identifierPrefix: String
    let isEnabled: Bool
    let onSelect: (EntryType) -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(
                .expense,
                title: WoniStrings.tabExpense(languageStore.language),
                activeColor: WoniColor.terracotta100
            )
            tabButton(
                .income,
                title: WoniStrings.tabIncome(languageStore.language),
                activeColor: WoniColor.olive100
            )
        }
        .background(WoniColor.gray00)
    }

    private func tabButton(_ tab: EntryType, title: String, activeColor: Color) -> some View {
        let isActive = selected == tab
        return Button {
            onSelect(tab)
        } label: {
            Text(title)
                .woniFont(.body2)
                .foregroundStyle(isActive ? activeColor : WoniColor.gray40)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? activeColor : WoniColor.base20)
                        .frame(height: isActive ? 2 : 1)
                }
                // 투명 여백은 히트 테스트에서 빠져 텍스트를 정확히 눌러야만 전환됐다.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(identifierPrefix).tab.\(tab == .expense ? "expense" : "income")")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .disabled(!isEnabled)
    }
}
