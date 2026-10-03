//
//  BudgetEditDraft.swift
//  woni_app
//

import Foundation

/// 편집 화면의 카테고리 금액 줄 하나.
struct BudgetEditCategoryLine: Equatable {
    /// 아직 서버에 없는 내 카테고리는 음수 임시 번호다.
    let categoryID: Int
    /// 서버가 삭제로 표시한 줄.
    let isDeleted: Bool
    /// nil = 빈칸("예산 없음"), 0 = 0원 몫. 0 과 빈칸은 다르다(스펙 §2.4).
    var amount: Decimal?
}

/// 그 달에 저장된 통화로 서버가 센 사용액(서버 `actualAmount` 그대로). 응답에 있는 줄만 담는다.
struct BudgetEditSpending: Equatable {
    let currency: CurrencyCode
    let total: Decimal
    let categories: [Int: Decimal]
    let payments: [PaymentGroup: Decimal]
}

/// 예산 편집 화면의 금액 계산(스펙 §2.1). T = 직접 입력한 전체, S = 카테고리 몫의 합.
/// 통화가 바뀌어도 기기에서 환산하지 않는다 — 금액을 비울 뿐이다(스펙 §2.5).
struct BudgetEditDraft: Equatable {
    var currency: CurrencyCode
    /// T. 직접 적지 않았으면 nil.
    private(set) var directTotal: Decimal?
    private(set) var categoryLines: [BudgetEditCategoryLine]
    /// 키 없음 = 빈칸.
    private(set) var paymentAmounts: [PaymentGroup: Decimal]
    var isPaymentExpanded: Bool
    /// 이 달 응답의 사용액. 미설정 달·비회원은 nil. 지난 달을 불러와도 바뀌지 않는다(스펙 V5).
    let spending: BudgetEditSpending?

    init(
        currency: CurrencyCode,
        directTotal: Decimal? = nil,
        categoryLines: [BudgetEditCategoryLine] = [],
        paymentAmounts: [PaymentGroup: Decimal] = [:],
        isPaymentExpanded: Bool = false,
        spending: BudgetEditSpending? = nil
    ) {
        self.currency = currency
        self.directTotal = directTotal
        self.categoryLines = categoryLines
        self.paymentAmounts = paymentAmounts
        self.isPaymentExpanded = isPaymentExpanded
        self.spending = spending
    }

    /// S. 빈칸은 빼고 0 은 0 으로 더한다.
    var categorySum: Decimal {
        categoryLines.compactMap(\.amount).reduce(0, +)
    }

    /// T 가 있으면 max(T, S). 없으면 S — 단 S 가 0 이면 없음(몫에 적은 0 이 모르는 사이 "전체 0원"이 되지 않게, M6).
    var total: Decimal? {
        if let directTotal {
            return max(directTotal, categorySum)
        }
        return categorySum > 0 ? categorySum : nil
    }

    /// 안내 "카테고리 합계".
    var isTotalAutomatic: Bool {
        directTotal == nil && categorySum > 0
    }

    /// "그 외 카테고리" = 전체 − S. 전체가 S 보다 클 때만.
    var otherCategoriesAmount: Decimal? {
        guard let total, total > categorySum else {
            return nil
        }
        return total - categorySum
    }

    var paymentSum: Decimal {
        paymentAmounts.values.reduce(0, +)
    }

    /// "나눌 수 있는 금액". 결제수단 합이 전체를 넘으면 nil(경고 줄이 대신한다).
    var paymentRemaining: Decimal? {
        guard let total, paymentSum <= total else {
            return nil
        }
        return total - paymentSum
    }

    /// 결제수단 합이 전체를 넘은 만큼. 경고 줄의 숫자다.
    var paymentExcess: Decimal? {
        guard let total, paymentSum > total else {
            return nil
        }
        return paymentSum - total
    }

    var isPaymentInputEnabled: Bool {
        total != nil
    }

    var isSaveable: Bool {
        total != nil && paymentExcess == nil
    }

    /// 입력 중인 결제수단 칸 아래 "최대 N" = 전체 − 다른 결제수단 합. 0 보다 작으면 0.
    func paymentMaximum(for group: PaymentGroup) -> Decimal? {
        guard let total else {
            return nil
        }
        let others = paymentAmounts.filter { $0.key != group }.values.reduce(0, +)
        return max(0, total - others)
    }

    /// 입력 중에는 S 로 맞추지 않는다 — 맞추기는 `commitDirectTotal()` 이 한다.
    mutating func setDirectTotal(_ value: Decimal?) {
        directTotal = value
    }

    /// 전체 칸에서 벗어날 때 부른다. T < S 면 T 를 S 로 맞추고 true(토스트 "카테고리 합계보다 작게 정할 수 없습니다.").
    mutating func commitDirectTotal() -> Bool {
        guard let directTotal, directTotal < categorySum else {
            return false
        }
        self.directTotal = categorySum
        return true
    }

    /// 바꾼 뒤의 S 가 상한을 넘으면 거절하고 아무것도 바꾸지 않는다(false — 상한 토스트, M2).
    /// 그 카테고리의 줄이 없어도 false 다.
    mutating func setCategoryAmount(_ value: Decimal?, for categoryID: Int) -> Bool {
        guard let index = categoryLines.firstIndex(where: { $0.categoryID == categoryID }) else {
            return false
        }
        let newSum = categorySum - (categoryLines[index].amount ?? 0) + (value ?? 0)
        guard newSum <= AddExpenseViewModel.maximumAmount else {
            return false
        }
        categoryLines[index].amount = value
        return true
    }

    /// nil 이면 빈칸("예산 없음")으로 돌린다.
    mutating func setPaymentAmount(_ value: Decimal?, for group: PaymentGroup) {
        paymentAmounts[group] = value
    }

    /// 칩을 누르면 빈 줄을 칩 순서 자리에 넣는다. `chipOrder` 에 없는 줄(삭제된 카테고리 등)은 그 뒤에 원래 순서대로 둔다.
    /// 이미 줄이 있으면 무시한다. 삭제된 카테고리 칩은 `isDeleted` 줄 그대로 다시 넣는다.
    mutating func addCategory(_ categoryID: Int, isDeleted: Bool = false, chipOrder: [Int]) {
        guard !categoryLines.contains(where: { $0.categoryID == categoryID }) else {
            return
        }
        let lines = categoryLines + [BudgetEditCategoryLine(categoryID: categoryID, isDeleted: isDeleted, amount: nil)]
        categoryLines = Self.orderedByChips(lines, chipOrder: chipOrder)
    }

    /// 금액 줄 끝 X — 확인 없이 줄을 뺀다(금액이 있어도). 칩은 줄이 없는 카테고리라 저절로 돌아온다. 없으면 무시한다.
    mutating func removeCategory(_ categoryID: Int) {
        categoryLines.removeAll { $0.categoryID == categoryID }
    }

    /// 줄을 칩 순서로 세운다. `chipOrder` 에 없는 줄은 그 뒤에 원래 순서대로 둔다.
    static func orderedByChips(_ lines: [BudgetEditCategoryLine], chipOrder: [Int]) -> [BudgetEditCategoryLine] {
        let ordered = chipOrder.compactMap { id in lines.first { $0.categoryID == id } }
        let rest = lines.filter { !chipOrder.contains($0.categoryID) }
        return ordered + rest
    }

    /// 칩 묶음 = 칩 순서에서 줄이 있는 카테고리를 뺀 것.
    func chipCategoryIDs(chipOrder: [Int]) -> [Int] {
        let lineIDs = Set(categoryLines.map(\.categoryID))
        return chipOrder.filter { !lineIDs.contains($0) }
    }

    /// 통화 변경 확인 뒤: T·모든 몫을 비우고 카테고리 줄은 남긴다(스펙 §2.5).
    mutating func clearAmounts() {
        directTotal = nil
        for index in categoryLines.indices {
            categoryLines[index].amount = nil
        }
        paymentAmounts = [:]
    }

    /// `입력 모두 지우기` 확인 뒤: T·결제수단 몫을 비우고 카테고리 줄은 모두 뺀다(칩으로 돌아간다).
    mutating func clearAll() {
        directTotal = nil
        categoryLines = []
        paymentAmounts = [:]
    }

    /// 새 카테고리를 서버에 올린 뒤 임시(음수) 번호를 서버 번호로 바꾼다. 여러 번 불러도 같다.
    mutating func remapCategoryIDs(_ resolve: (Int) -> Int) {
        categoryLines = categoryLines.map {
            BudgetEditCategoryLine(categoryID: resolve($0.categoryID), isDeleted: $0.isDeleted, amount: $0.amount)
        }
    }
}
