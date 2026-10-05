//
//  BudgetEditKeyboardScroll.swift
//  woni_app
//

import SwiftUI

/// 결제수단 칸·카테고리 칸(갈래 A) 입력 중 스크롤 맞춤(UI_GUIDE "결제수단 칸에 입력 중이면 …" · "카테고리 칸에 입력 중이면
/// (갈래 A) …"). 좌표는 스크롤 내용 기준, 높이는 보이는 영역(헤더 아래~키보드 위).
enum BudgetEditKeyboardScroll {
    enum Alignment: Equatable {
        /// 맞출 범위 끝(결제수단 섹션 끝 · "그 외 카테고리" 자리 끝)을 보이는 영역 아래 끝에.
        case sectionBottom
        /// 입력 중인 칸 줄 꼭대기를 보이는 영역 위 끝에.
        case fieldTop
    }

    /// 화면이 맞춤 대상에 다는 id — 결제수단 줄과 섹션 끝(섹션 아래 여백 12 까지) · 카테고리 줄과 "그 외 카테고리" 자리의
    /// 아래 끝(자리가 없으면 마지막 카테고리 줄의 아래 끝). 카테고리 쪽은 칩 묶음이 길어 섹션 끝이 아니라 자리 끝까지다.
    enum ScrollID: Hashable {
        case paymentRow(PaymentGroup)
        case paymentSectionEnd
        case categoryRow(Int)
        case categorySlotEnd
    }

    /// 맞춤 대상의 프레임을 재는 좌표 공간 — 편집 본문(스크롤 내용). 스크롤해도 값이 바뀌지 않는다.
    nonisolated static let contentSpace = "budgetEdit.scrollContent"

    /// 보이는 높이 = 스크롤 영역 위 끝 ~ (스크롤 영역 아래 끝과 키보드 위 끝 중 위쪽). 둘 다 window 좌표 — 이 앱은 iPhone 전체
    /// 화면이라 알림의 키보드 프레임(화면 좌표)과 같다. SwiftUI 가 스크롤 영역을 키보드만큼 줄이기 전이든 뒤든 같은 값이라,
    /// 그 갱신이 알림보다 늦는 기기에서도 판단이 같다.
    static func visibleHeight(scrollFrame: CGRect, keyboardFrame: CGRect) -> CGFloat {
        max(0, min(scrollFrame.maxY, keyboardFrame.minY) - scrollFrame.minY)
    }

    /// 저장할 키보드 프레임 — 알림의 끝 프레임이 화면 안이면 그 프레임, 화면 밖(내려간 키보드)이거나 없으면 nil.
    /// `keyboardWillShow`·`keyboardWillChangeFrame` 둘 다 이 값으로 저장해, 떠 있는 키보드의 높이가 바뀌어도 낡지 않고
    /// 내려갈 때 `willChangeFrame`·`willHide` 가 어느 순서로 와도 nil 이다.
    static func keyboardFrame(endFrame: CGRect?, screenBounds: CGRect) -> CGRect? {
        guard let endFrame, endFrame.minY < screenBounds.maxY else {
            return nil
        }
        return endFrame
    }

    /// 스크롤 영역이 키보드만큼 줄어 있는가 — 아래 끝이 키보드 위 끝 이하(반올림 여유 1pt). 끌어서 키보드를 내리는 동안에는
    /// 영역이 키보드를 따라 늘어나는데 키보드 프레임은 손을 뗄 때까지 그대로라 false 다(`keyboardWillChangeFrame` 도 끄는 동안
    /// 오지 않고 손을 뗀 뒤에만 온다 — 2026-10-04 시뮬레이터 실측) — 그동안 맞추면 내용이 손가락 대신 키보드 위 끝을 따라간다.
    static func isAvoidanceApplied(scrollFrame: CGRect, keyboardFrame: CGRect) -> Bool {
        scrollFrame.maxY <= keyboardFrame.minY + 1
    }

    /// 포커스·갈래 → (입력 중인 칸 id, 맞출 범위 끝 id). 맞추지 않으면 nil — 전체 칸·포커스 없음, 그리고 갈래 B·빈 화면의
    /// 카테고리 칸(그 아래 "최대"·경고 줄이 없다)은 iOS 기본 동작 그대로다.
    static func targets(focus: BudgetEditField?, mode: BudgetEditTotalMode) -> (field: ScrollID, end: ScrollID)? {
        switch focus {
        case let .payment(group)?: (field: .paymentRow(group), end: .paymentSectionEnd)
        case let .category(categoryID)? where mode == .direct: (field: .categoryRow(categoryID), end: .categorySlotEnd)
        default: nil
        }
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

    /// "그 외 카테고리" 자리 끝 표지 — `isActive` 면 이 뷰 아래 끝에 높이 0 표지를 두고 `.categorySlotEnd` 를 단다.
    /// 카테고리 섹션 스택에 자식을 끼우지 않아 자리가 없을 때도 간격이 그대로다. 이 뷰의 id 와 겹치지 않게 표지에 단다.
    func budgetEditCategorySlotEnd(
        _ isActive: Bool,
        onFrame: @escaping (BudgetEditKeyboardScroll.ScrollID, CGRect) -> Void
    ) -> some View {
        background(alignment: .bottom) {
            if isActive {
                Color.clear
                    .frame(height: 0)
                    .budgetEditScrollTarget(.categorySlotEnd, onFrame: onFrame)
            }
        }
    }
}
