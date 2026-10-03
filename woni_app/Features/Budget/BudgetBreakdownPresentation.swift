//
//  BudgetBreakdownPresentation.swift
//  woni_app
//

import Foundation
import SwiftUI

/// 하위 줄(카테고리·그 외 카테고리·결제수단)의 몫. 계약 검사(`BudgetTabViewModel.isWellFormed`)와 카드가 이 한 곳에서
/// 판정한다 — 따로 판정하면 한쪽만 고쳐질 때 검사를 지난 응답의 카드가 말없이 빈다.
enum BudgetShare {
    /// 몫이 없는 줄. 막대 없이 사용액만 보인다.
    case unbudgeted
    case budgeted(amount: Decimal, bar: BudgetBarFill)

    /// 몫이 있는데 막대를 만들 수 없으면(넘었는데 넘은 돈이 없음) 계약이 깨진 것이라 nil.
    init?(line: BudgetLine) {
        guard let amount = line.budgetAmount else {
            self = .unbudgeted
            return
        }
        guard let bar = BudgetBarFill(line: line) else {
            return nil
        }
        self = .budgeted(amount: amount, bar: bar)
    }
}

/// 예산 탭 카테고리·결제수단 카드의 표시 규칙. 금액·상태·넘은 돈은 서버 값 그대로 쓴다.
/// 기기에서 정하는 것은 줄 순서·색 순위·막대 비율뿐이다.
struct BudgetBreakdownPresentation {
    /// 하위 막대 두께. 넘친 구간도 이보다 좁아지지 않는다.
    static let barThickness: CGFloat = 8

    /// 카드 한 줄(카테고리·그 외 카테고리·결제수단 공통).
    struct Row {
        let name: String
        /// 이름 뒤 꼬리표("삭제 대기"). 이름과 글자 크기·색이 달라 따로 둔다.
        let tag: String?
        /// 몫이 있으면 "사용 / 예산", 없으면 사용액만. 통화 글자 없이 예산 통화 자릿수를 따른다.
        let amountText: String
        let amountColor: Color
        /// 몫이 없는 줄은 nil — 막대 없이 사용액만 보인다.
        let bar: BudgetBarFill?
        /// 채움(넘었으면 예산 눈금 왼쪽) 색. 넘친 구간은 늘 `terracotta110` 이다.
        let barColor: Color
        /// 넘은 줄의 "34,726 넘었습니다". 카테고리·그 외 카테고리·결제수단 모두 같다.
        let overText: String?
    }

    struct CategoryRow {
        let categoryID: Int
        /// 예산 탭 안의 쓴 돈 순위(0 부터). 막대 색을 정한다 — 통계 탭의 순위를 가져오지 않는다.
        let colorRank: Int
        let row: Row
    }

    struct CategoryCard {
        /// 예산을 정한 카테고리. 쓴 돈 많은 순, 같으면 카테고리 번호가 작은 쪽이 앞이다.
        let rows: [CategoryRow]
        let otherCategories: Row
    }

    struct PaymentRow {
        let paymentGroup: PaymentGroup
        let row: Row
    }

    private static let paymentOrder: [PaymentGroup] = [.creditCard, .cashAndDebit, .accountAndOther]
    /// 결제수단끼리는 색을 나누지 않는다 — 나누면 색에 없는 뜻이 생긴다.
    private static let paymentBarColor = WoniColor.category03Step70

    let categoryTitle: String
    let paymentTitle: String
    /// 몫을 정한 카테고리가 없는 달은 nil — "그 외 카테고리" 한 줄이 총액 카드와 같은 숫자라 카드를 두지 않는다.
    let categoryCard: CategoryCard?
    /// 몫이 없는 묶음도 포함해 늘 세 줄, 카드 → 현금·체크 → 계좌·기타 순이다.
    let paymentRows: [PaymentRow]

    /// 미설정 달이거나 계약상 있어야 할 값(통화·그 외 카테고리 줄·결제수단 세 묶음·넘은 돈)이 없으면 nil —
    /// 빈 값을 기본값으로 메워 카드를 그리지 않는다.
    init?(content: BudgetTabContent, language: AppLanguage) {
        let budget = content.budget
        guard let currency = budget.currency, let otherLine = budget.otherCategories else {
            return nil
        }
        let factory = RowFactory(currencyCode: currency.rawValue, language: language)

        let sortedLines = budget.categories.sorted { lhs, rhs in
            lhs.line.actualAmount != rhs.line.actualAmount
                ? lhs.line.actualAmount > rhs.line.actualAmount
                : lhs.category.id < rhs.category.id
        }
        let pendingIDs = content.pendingDeletionCategoryIDs
        var categoryRows: [CategoryRow] = []
        for (rank, categoryLine) in sortedLines.enumerated() {
            let label = Self.categoryLabel(categoryLine, pendingIDs: pendingIDs, language: language)
            guard let row = factory.row(
                categoryLine.line,
                name: label.name,
                tag: label.tag,
                barColor: WoniColor.budgetCategoryBarColor(rank: rank)
            ) else {
                return nil
            }
            categoryRows.append(CategoryRow(categoryID: categoryLine.category.id, colorRank: rank, row: row))
        }
        guard let otherRow = factory.row(
            otherLine,
            name: WoniStrings.budgetOtherCategories(language),
            tag: nil,
            barColor: WoniColor.gray40
        ) else {
            return nil
        }

        var paymentRows: [PaymentRow] = []
        for group in Self.paymentOrder {
            guard let groupLine = budget.paymentGroups.first(where: { $0.paymentGroup == group }),
                  let row = factory.row(
                      groupLine.line,
                      name: WoniStrings.budgetPaymentGroupName(group, language: language),
                      tag: nil,
                      barColor: Self.paymentBarColor
                  )
            else {
                return nil
            }
            paymentRows.append(PaymentRow(paymentGroup: group, row: row))
        }

        categoryTitle = WoniStrings.budgetCategoryCardTitle(language)
        paymentTitle = WoniStrings.budgetPaymentCardTitle(language)
        categoryCard = categoryRows.isEmpty ? nil : CategoryCard(rows: categoryRows, otherCategories: otherRow)
        self.paymentRows = paymentRows
    }
}

private extension BudgetBreakdownPresentation {
    /// 서버가 삭제로 표시한 줄은 아이콘 없이 "삭제된 카테고리"이고 삭제 대기 꼬리표보다 앞선다.
    /// 그 밖은 가계부 내역과 같은 이름(아이콘 + 이름)이다.
    static func categoryLabel(
        _ categoryLine: BudgetCategoryLine,
        pendingIDs: Set<Int>,
        language: AppLanguage
    ) -> (name: String, tag: String?) {
        if categoryLine.isDeleted {
            return (WoniStrings.budgetDeletedCategory(language), nil)
        }
        let name = CategoryDisplayNameResolver.localizedDisplayName(for: categoryLine.category, language: language)
        let tag = pendingIDs.contains(categoryLine.category.id) ? WoniStrings.budgetPendingDeletion(language) : nil
        return (name, tag)
    }

    struct RowFactory {
        let currencyCode: String
        let language: AppLanguage

        /// 몫이 있는데 막대를 만들 수 없으면(`BudgetShare` 가 nil) 계약이 깨진 것이라 nil.
        func row(_ line: BudgetLine, name: String, tag: String?, barColor: Color) -> Row? {
            guard let share = BudgetShare(line: line) else {
                return nil
            }
            let actualText = CurrencyFormat.string(line.actualAmount, currencyCode: currencyCode)
            guard case let .budgeted(budgetAmount, bar) = share else {
                return Row(
                    name: name,
                    tag: tag,
                    amountText: actualText,
                    amountColor: WoniColor.gray60,
                    bar: nil,
                    barColor: barColor,
                    overText: nil
                )
            }
            let overText = bar.isOver
                ? line.overAmount.map {
                    WoniStrings.budgetOverAmount(
                        CurrencyFormat.string($0, currencyCode: currencyCode),
                        language: language
                    )
                }
                : nil
            return Row(
                name: name,
                tag: tag,
                amountText: actualText + " / " + CurrencyFormat.string(budgetAmount, currencyCode: currencyCode),
                amountColor: WoniColor.gray80,
                bar: bar,
                barColor: barColor,
                overText: overText
            )
        }
    }
}
