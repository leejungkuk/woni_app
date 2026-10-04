//
//  BudgetEditRemoveLabelTests.swift
//  woni_appTests
//

import Testing
@testable import woni_app

/// 금액 줄 끝 X 의 VoiceOver 라벨은 아이콘(이모지) 없이 이름만 쓴다(UI_GUIDE "금액 줄 끝 X", 2026-10-04 사용자 결정).
/// 줄 왼쪽에 보이는 이름은 아이콘을 붙인 그대로다. 화면 연결은 `BudgetEditUITests` 가 본다.
@MainActor
struct BudgetEditRemoveLabelTests {
    private let food = Category(
        id: 1,
        code: "FOOD",
        displayNameKo: "식비",
        displayNameEn: "Food",
        icon: "\u{1F37D}\u{FE0F}",
        sortOrder: 1
    )
    private let plain = Category(
        id: 2,
        code: "PLAIN",
        displayNameKo: "모임",
        displayNameEn: "Meetup",
        icon: nil,
        sortOrder: 2
    )

    @Test("BDF.S8-R1 localizedName 은 아이콘 없이 언어별 이름만 돌려준다 — 아이콘 없는 카테고리는 이름 그대로")
    func localizedNameDropsIcon() {
        #expect(CategoryDisplayNameResolver.localizedName(for: food, language: .ko) == "식비")
        #expect(CategoryDisplayNameResolver.localizedName(for: food, language: .en) == "Food")
        #expect(CategoryDisplayNameResolver.localizedName(for: plain, language: .ko) == "모임")
        #expect(CategoryDisplayNameResolver.localizedName(for: plain, language: .en) == "Meetup")
    }

    @Test("BDF.S8-R1 짝: 같은 카테고리의 localizedDisplayName 은 여전히 아이콘을 앞에 붙인다 — 보이는 이름은 그대로")
    func localizedDisplayNameKeepsIcon() {
        #expect(CategoryDisplayNameResolver.localizedDisplayName(for: food, language: .ko) == "\u{1F37D}\u{FE0F} 식비")
        #expect(CategoryDisplayNameResolver.localizedDisplayName(for: food, language: .en) == "\u{1F37D}\u{FE0F} Food")
        #expect(CategoryDisplayNameResolver.localizedDisplayName(for: plain, language: .ko) == "모임")
        #expect(
            CategoryDisplayNameResolver.localizedDisplayName(for: food, language: .ko)
                != CategoryDisplayNameResolver.localizedName(for: food, language: .ko)
        )
    }

    @Test("BDF.S8-R2 줄 라벨의 bareName — 카테고리 줄은 아이콘 없는 이름, 삭제된 줄은 \"삭제된 카테고리\"")
    func bareNameFollowsLineLabel() {
        #expect(BudgetEditLineLabel.category(food).bareName(.ko) == "식비")
        #expect(BudgetEditLineLabel.category(food).bareName(.en) == "Food")
        #expect(BudgetEditLineLabel.category(plain).bareName(.ko) == "모임")
        #expect(BudgetEditLineLabel.deleted.bareName(.ko) == "삭제된 카테고리")
        #expect(BudgetEditLineLabel.deleted.bareName(.en) == "Deleted category")
    }

    @Test("BDF.S8-R2 짝: bareName 으로 만든 X 라벨에는 아이콘 글자(U+1F37D)가 없다 — \"식비 빼기\" · \"Remove Food\"")
    func removeLabelFromBareNameHasNoIcon() {
        let icon: Character = "\u{1F37D}\u{FE0F}"
        let ko = WoniStrings.budgetEditRemoveLine(BudgetEditLineLabel.category(food).bareName(.ko), language: .ko)
        let en = WoniStrings.budgetEditRemoveLine(BudgetEditLineLabel.category(food).bareName(.en), language: .en)
        #expect(ko == "식비 빼기")
        #expect(en == "Remove Food")
        #expect(!ko.unicodeScalars.contains("\u{1F37D}"))
        #expect(!en.unicodeScalars.contains("\u{1F37D}"))
        #expect(!ko.contains(icon))
    }
}
