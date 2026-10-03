//
//  BudgetEditDraftConversion.swift
//  woni_app
//

import Foundation

/// 서버 응답 → 편집 초안, 편집 초안 → 저장 요청. 여는 응답은 계약 검사(`BudgetTabViewModel.isWellFormed`)를 지난 것이다.
/// 삭제 여부·사용액은 서버 값만 쓴다 — 기기의 카테고리 목록으로 판정하거나 기기에서 세지 않는다.
extension BudgetEditDraft {
    /// 그 달 응답으로 연다. 미설정이면 baseCurrency·빈칸.
    init(budget: MonthlyBudget, chipOrder: [Int], baseCurrency: CurrencyCode) {
        guard let currency = budget.currency, let total = budget.total, let savedTotal = total.budgetAmount else {
            self.init(emptyWith: baseCurrency)
            return
        }
        self.init(
            currency: currency,
            savedTotal: savedTotal,
            categories: budget.categories,
            paymentGroups: budget.paymentGroups,
            chipOrder: chipOrder,
            spending: BudgetEditSpending(
                currency: currency,
                total: total.actualAmount,
                categories: budget.categories.reduce(into: [:]) { $0[$1.category.id] = $1.line.actualAmount },
                payments: budget.paymentGroups.reduce(into: [:]) { $0[$1.paymentGroup] = $1.line.actualAmount }
            )
        )
    }

    /// 신원 없는 비회원 — 서버 응답 없이 빈 초안(미설정과 같다).
    init(emptyWith currency: CurrencyCode) {
        self.init(currency: currency)
    }

    /// 몫 있는 줄만 금액 줄·결제수단 몫이 된다. 결제수단 몫이 있으면 펼친다.
    /// 저장된 전체가 S 와 같으면 자동(T 없음), 아니면 T — S 가 0 이면 늘 T(스펙 M1).
    private init(
        currency: CurrencyCode,
        savedTotal: Decimal,
        categories: [BudgetCategoryLine],
        paymentGroups: [BudgetPaymentGroupLine],
        chipOrder: [Int],
        spending: BudgetEditSpending?
    ) {
        let lines = categories.compactMap { category in
            category.line.budgetAmount.map {
                BudgetEditCategoryLine(categoryID: category.category.id, isDeleted: category.isDeleted, amount: $0)
            }
        }
        let sum = lines.compactMap(\.amount).reduce(0, +)
        let payments = paymentGroups.reduce(into: [PaymentGroup: Decimal]()) {
            $0[$1.paymentGroup] = $1.line.budgetAmount
        }
        self.init(
            currency: currency,
            directTotal: sum > 0 && savedTotal == sum ? nil : savedTotal,
            categoryLines: Self.orderedByChips(lines, chipOrder: chipOrder),
            paymentAmounts: payments,
            isPaymentExpanded: !payments.isEmpty,
            spending: spending
        )
    }

    /// 지난 달 값으로 덮는다. 돌려주는 값 = 빼고 불러온 삭제된 카테고리 수(몫이 있던 것만).
    /// 통화·전체·결제수단은 지난 달 값이고, M1 판정은 삭제된 몫을 뺀 S 로 한다(스펙 :234). 사용액은 이 달 값 그대로다.
    /// 지난 달이 미설정이면 칸을 그대로 둔다 — 토스트는 화면이 응답 상태로 고른다.
    mutating func applyPrevious(_ previous: MonthlyBudget, chipOrder: [Int]) -> Int {
        guard let currency = previous.currency, let savedTotal = previous.total?.budgetAmount else {
            return 0
        }
        let wasExpanded = isPaymentExpanded
        self = BudgetEditDraft(
            currency: currency,
            savedTotal: savedTotal,
            categories: previous.categories.filter { !$0.isDeleted },
            paymentGroups: previous.paymentGroups,
            chipOrder: chipOrder,
            spending: spending
        )
        isPaymentExpanded = isPaymentExpanded || wasExpanded
        return previous.categories.filter { $0.isDeleted && $0.line.budgetAmount != nil }.count
    }

    /// 금액·줄이 기준과 다른가(통화·펼침은 보지 않는다 — 통화만 바뀌어 비워진 상태는 바뀐 입력이 아니다, 스펙 V10).
    func hasChanges(from baseline: BudgetEditDraft) -> Bool {
        directTotal != baseline.directTotal
            || categoryLines != baseline.categoryLines
            || paymentAmounts != baseline.paymentAmounts
    }

    /// "저장하지 않고 나갈까요?" 판정 — 전체는 직접 친 값이 아니라 실제 전체로 본다. 자동 합계 1,000 인 달에 1,000 을
    /// 직접 쳐도 바뀐 입력이 아니다(UI_GUIDE 2026-10-04). 불러오기 칩은 `hasChanges(from:)` 그대로다.
    func hasUnsavedChanges(from baseline: BudgetEditDraft) -> Bool {
        total != baseline.total
            || categoryLines != baseline.categoryLines
            || paymentAmounts != baseline.paymentAmounts
    }

    /// 전체가 없으면 nil. 빈칸 줄·빈칸 결제수단은 보내지 않고 0 은 보낸다(0원 몫).
    func saveRequest(resolvingCategoryID resolve: (Int) -> Int) -> SaveBudgetRequest? {
        guard let total else {
            return nil
        }
        let groups: [PaymentGroup] = [.creditCard, .cashAndDebit, .accountAndOther]
        return SaveBudgetRequest(
            currency: currency,
            totalAmount: total,
            paymentGroupAmounts: groups.compactMap { group in
                paymentAmounts[group].map { PaymentGroupAmountRequest(paymentGroup: group, amount: $0) }
            },
            categoryAmounts: categoryLines.compactMap { line in
                line.amount.map { CategoryAmountRequest(categoryId: resolve(line.categoryID), amount: $0) }
            }
        )
    }

    // MARK: 사용액 줄 — 편집 중 통화가 저장된 통화와 다르면 모두 nil(스펙 §2.5 V2, 서버는 저장된 통화로만 센다)

    var spentTotal: Decimal? {
        visibleSpending?.total
    }

    /// 응답에 없는 카테고리(편집 중 새로 넣은 줄)는 nil.
    func spent(forCategory id: Int) -> Decimal? {
        visibleSpending?.categories[id]
    }

    func spent(forPayment group: PaymentGroup) -> Decimal? {
        visibleSpending?.payments[group]
    }

    private var visibleSpending: BudgetEditSpending? {
        spending?.currency == currency ? spending : nil
    }
}
