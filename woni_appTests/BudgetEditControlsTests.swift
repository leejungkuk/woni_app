//
//  BudgetEditControlsTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 편집 화면의 줄 끝 X · 삭제된 카테고리 칩 · 입력 모두 지우기(UI_GUIDE 2026-10-04 결정) 중 화면 밖에서 볼 수 있는 것 —
/// UI 테스트 고정 응답(`-uiTestBudgetDeletedCategories`)과 새 문구. 화면 동작은 `BudgetEditUITests` 가 본다.
@MainActor
struct BudgetEditControlsTests {
    @Test("BDF.S3-R1 삭제된 카테고리 시나리오 응답은 이번 달·다른 달 모두 계약 검사를 지나고, 삭제된 줄 셋이 ①②③ 모양이다")
    func deletedCategoriesFixtureIsWellFormed() throws {
        let catalog = try CatalogProvider(seedData: SeedLoader().load())
        let catalogIDs = Set(catalog.categories(for: .expense).map(\.id))
        let months = [
            UITestSupport.BudgetScenario.serverMonth,
            ServerMonth(year: 2026, month: 9),
            ServerMonth(year: 2027, month: 10)
        ]
        for month in months {
            let budget = try UITestSupport.BudgetScenario.deletedCategories.fetch(
                year: month.year,
                month: month.month,
                catalog: catalog
            )
            #expect(BudgetTabViewModel.isWellFormed(budget), "\(month)")

            let deleted = budget.categories.filter(\.isDeleted)
            try #require(deleted.count == 3, "\(month)")
            #expect(Set(deleted.map(\.category.id)).count == 3, "\(month)")
            #expect(deleted.allSatisfy { $0.line.budgetAmount != nil }, "\(month)")
            // 응답 순서 ①②③.
            let (spent, unspent, inCatalog) = (deleted[0], deleted[1], deleted[2])
            #expect(!catalogIDs.contains(spent.category.id) && spent.line.actualAmount > 0, "\(month)")
            #expect(!catalogIDs.contains(unspent.category.id) && unspent.line.actualAmount == 0, "\(month)")
            #expect(catalogIDs.contains(inCatalog.category.id) && inCatalog.line.actualAmount > 0, "\(month)")
            // ③ 은 보통 카테고리 줄과 겹치지 않는다 — 겹치면 같은 번호가 보통 줄과 삭제된 줄 둘이 된다.
            let normalIDs = budget.categories.filter { !$0.isDeleted }.map(\.category.id)
            #expect(!normalIDs.isEmpty, "\(month)")
            #expect(!normalIDs.contains(inCatalog.category.id), "\(month)")
        }
    }

    @Test("BDF.S3-R1 짝: 기존 setMonth 응답에는 삭제된 줄이 없다 — 새 줄은 새 시나리오에만 있다")
    func setMonthFixtureHasNoDeletedLines() throws {
        let catalog = try CatalogProvider(seedData: SeedLoader().load())
        let budget = try UITestSupport.BudgetScenario.setMonth.fetch(year: 2026, month: 10, catalog: catalog)
        #expect(budget.categories.count == 2)
        #expect(budget.categories.allSatisfy { !$0.isDeleted })
        #expect(budget.otherCategories?.budgetAmount == 200_000)
        #expect(budget.otherCategories?.actualAmount == 30000)
    }

    @Test("BDF.S3-R1 이 응답으로 연 편집(실제 조립 칩 순서) — ③ 은 처음부터 보통 칩에 없고, ①③ 을 빼면 삭제된 칩, ② 를 빼면 어느 칩에도 없다")
    func deletedCategoriesFixtureDrivesChips() throws {
        let dependencies = try AppDependencyFactory.makeSeedDependencies(inMemory: true)
        let budget = try UITestSupport.BudgetScenario.deletedCategories.fetch(
            year: 2026,
            month: 10,
            catalog: dependencies.catalogProvider
        )
        let deleted = budget.categories.filter(\.isDeleted).map(\.category.id)
        try #require(deleted.count == 3)
        let (spentID, unspentID, inCatalogID) = (deleted[0], deleted[1], deleted[2])
        let chipOrder = AppDependencyFactory.budgetEditCategories(dependencies: dependencies).map(\.id)
        #expect(chipOrder.contains(inCatalogID))
        let viewModel = AppDependencyFactory.makeBudgetEditViewModel(
            dependencies: dependencies,
            context: BudgetEditViewModel.Context(
                month: ServerMonth(year: 2026, month: 10),
                lastMonth: ServerMonth(year: 2027, month: 10),
                initialBudget: budget
            ),
            baseCurrency: .krw,
            beginWrite: { 1 },
            onFinish: { _ in }
        )
        #expect(viewModel.draft.categoryLines.filter(\.isDeleted).map(\.categoryID) == deleted)
        #expect(!viewModel.chipCategoryIDs.contains(inCatalogID))
        #expect(viewModel.deletedChipCategoryIDs.isEmpty)

        viewModel.removeCategory(spentID)
        #expect(viewModel.deletedChipCategoryIDs == [spentID])

        viewModel.removeCategory(inCatalogID)
        #expect(viewModel.deletedChipCategoryIDs == [spentID, inCatalogID])
        #expect(!viewModel.chipCategoryIDs.contains(inCatalogID))

        viewModel.removeCategory(unspentID)
        #expect(!viewModel.deletedChipCategoryIDs.contains(unspentID))
        #expect(!viewModel.chipCategoryIDs.contains(unspentID))
        #expect(viewModel.deletedChipCategoryIDs == [spentID, inCatalogID])
    }

    @Test("BDF.S3-R2 입력 모두 지우기 버튼·확인 창 문구는 UI_GUIDE en 표와 같다")
    func clearAllCopyFollowsGuide() {
        #expect(WoniStrings.budgetEditClearAll(.ko) == "입력 모두 지우기")
        #expect(WoniStrings.budgetEditClearAll(.en) == "Clear All Amounts")
        #expect(WoniStrings.budgetEditClearAllTitle(.ko) == "입력한 금액을 모두 지울까요?")
        #expect(WoniStrings.budgetEditClearAllTitle(.en) == "Clear all the amounts you entered?")
        #expect(WoniStrings.budgetEditClear(.ko) == "지우기")
        #expect(WoniStrings.budgetEditClear(.en) == "Clear")
    }

    @Test("BDF.S3-R2 줄 끝 X 의 VoiceOver 라벨은 줄 이름 + 빼기다 — 삭제된 줄은 \"삭제된 카테고리\"가 이름이다")
    func removeLineLabelUsesLineName() {
        #expect(WoniStrings.budgetEditRemoveLine("식비", language: .ko) == "식비 빼기")
        #expect(WoniStrings.budgetEditRemoveLine("교통", language: .ko) == "교통 빼기")
        #expect(WoniStrings.budgetEditRemoveLine("Food", language: .en) == "Remove Food")
        #expect(WoniStrings.budgetEditRemoveLine("Transport", language: .en) == "Remove Transport")
        #expect(
            WoniStrings.budgetEditRemoveLine(WoniStrings.budgetDeletedCategory(.ko), language: .ko) == "삭제된 카테고리 빼기"
        )
        #expect(
            WoniStrings.budgetEditRemoveLine(WoniStrings.budgetDeletedCategory(.en), language: .en)
                == "Remove Deleted category"
        )
    }

    @Test("BDF.S3-R2 짝: 이름이 다르면 라벨이 다르고, 같은 이름도 언어에 따라 다르다 — 고정 문구가 아니다")
    func removeLineLabelVariesWithNameAndLanguage() {
        let remove = WoniStrings.budgetEditRemoveLine
        #expect(remove("식비", .ko) != remove("교통", .ko))
        #expect(remove("Food", .en) != remove("Transport", .en))
        #expect(remove("식비", .ko) != remove("식비", .en))
        #expect(!remove("교통", .ko).contains("식비"))
        #expect(WoniStrings.budgetEditClearAll(.ko) != WoniStrings.budgetEditClear(.ko))
    }
}
