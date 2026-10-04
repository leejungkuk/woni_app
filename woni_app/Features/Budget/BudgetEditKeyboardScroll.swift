//
//  BudgetEditKeyboardScroll.swift
//  woni_app
//

import SwiftUI

/// 결제수단 칸 입력 중 스크롤 맞춤(UI_GUIDE "결제수단 칸에 입력 중이면 …"). 좌표는 스크롤 내용 기준, 높이는 보이는 영역(헤더 아래~키보드 위).
enum BudgetEditKeyboardScroll {
    enum Alignment: Equatable {
        /// 결제수단 섹션 끝을 보이는 영역 아래 끝에.
        case sectionBottom
        /// 입력 중인 칸 줄 꼭대기를 보이는 영역 위 끝에.
        case fieldTop
    }

    /// 화면이 맞춤 대상에 다는 id — 결제수단 줄과 섹션 끝(섹션 아래 여백 12 까지).
    enum ScrollID: Hashable {
        case paymentRow(PaymentGroup)
        case paymentSectionEnd
    }

    /// 맞춤 대상의 프레임을 재는 좌표 공간 — 편집 본문(스크롤 내용). 스크롤해도 값이 바뀌지 않는다.
    nonisolated static let contentSpace = "budgetEdit.scrollContent"

    /// 보이는 높이 = 스크롤 영역 위 끝 ~ (스크롤 영역 아래 끝과 키보드 위 끝 중 위쪽). 둘 다 window 좌표 — 이 앱은 iPhone 전체
    /// 화면이라 알림의 키보드 프레임(화면 좌표)과 같다. SwiftUI 가 스크롤 영역을 키보드만큼 줄이기 전이든 뒤든 같은 값이라,
    /// 그 갱신이 알림보다 늦는 기기에서도 판단이 같다.
    static func visibleHeight(scrollFrame: CGRect, keyboardFrame: CGRect) -> CGFloat {
        max(0, min(scrollFrame.maxY, keyboardFrame.minY) - scrollFrame.minY)
    }

    /// 칸 줄 꼭대기 ~ 섹션 끝이 보이는 높이에 들어가면(같을 때 포함) .sectionBottom, 아니면 .fieldTop.
    static func alignment(fieldTop: CGFloat, sectionBottom: CGFloat, visibleHeight: CGFloat) -> Alignment {
        sectionBottom - fieldTop <= visibleHeight ? .sectionBottom : .fieldTop
    }

    /// 맞출 대상과 기준 — .sectionBottom → (섹션 끝, .bottom) · .fieldTop → (입력 중인 칸 줄, .top).
    static func target<ID: Hashable>(
        for alignment: Alignment,
        field: ID,
        sectionEnd: ID
    ) -> (id: ID, anchor: UnitPoint) {
        switch alignment {
        case .sectionBottom: (sectionEnd, .bottom)
        case .fieldTop: (field, .top)
        }
    }
}

extension View {
    /// 스크롤 맞춤 대상 — id 를 달고 편집 본문 기준 프레임을 알린다.
    func budgetEditScrollTarget(
        _ scrollID: BudgetEditKeyboardScroll.ScrollID,
        onFrame: @escaping (BudgetEditKeyboardScroll.ScrollID, CGRect) -> Void
    ) -> some View {
        id(scrollID)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(BudgetEditKeyboardScroll.contentSpace))
            } action: { frame in
                onFrame(scrollID, frame)
            }
    }
}
