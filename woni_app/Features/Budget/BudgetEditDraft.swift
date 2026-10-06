//
//  BudgetEditDraft.swift
//  woni_app
//

import Foundation

/// 편집 화면의 카테고리 금액 줄 하나.
struct BudgetEditCategoryLine: Hashable {
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

/// 전체와 카테고리 중 먼저 적은 쪽(UI_GUIDE "먼저 적은 쪽이 기준이다").
enum BudgetEditTotalMode: Equatable {
    /// 빈 화면 — 전체가 비고 카테고리 합 0.
    case empty
    /// 갈래 A — 전체를 먼저 적음. 카테고리 합은 전체 안에서다.
    case direct
    /// 갈래 B — 전체 = 카테고리 합, 잠김.
    case categorySum
}

/// 카테고리 금액 입력 결과.
enum BudgetEditCategoryInput: Equatable {
    case accepted
    /// 합이 99,999,999 를 넘음. 줄이 없을 때도 이것이다.
    case overLimit
    /// 갈래 A 에서 합이 전체를 넘게 됨.
    case overTotal
}

/// 예산 편집 화면의 금액 계산(스펙 §2.1). T = 직접 입력한 전체, S = 카테고리 몫의 합.
/// 통화가 바뀌어도 기기에서 환산하지 않는다 — 금액을 비울 뿐이다(스펙 §2.5).
struct BudgetEditDraft: Equatable {
    var currency: CurrencyCode
    /// T. 직접 적지 않았으면 nil.
    private(set) var directTotal: Decimal?
    /// 갈래 A 에서 T 를 비운 채 아직 전체 칸에 있다 — 벗어날 때(`endTotalEditing()`)까지 A 다.
    private var isClearingDirectTotal = false
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

    /// T 가 있거나 비우는 중이면 A. 아니면 S > 0 이면 B, S 가 0 이면 빈 화면(몫에 적은 0 이 모르는 사이 "전체 0원"이
    /// 되지 않게, M6). 다시 열기·불러오기는 저장된 전체가 S 와 같을 때만 T 를 비워 B 로 연다.
    var totalMode: BudgetEditTotalMode {
        if directTotal != nil || isClearingDirectTotal {
            return .direct
        }
        return categorySum > 0 ? .categorySum : .empty
    }

    /// A 는 T 그대로(비우는 중은 없음) — S 로 늘지 않는다. B 는 S, 빈 화면은 없음.
    var total: Decimal? {
        switch totalMode {
        case .direct: directTotal
        case .categorySum: categorySum
        case .empty: nil
        }
    }

    /// 안내 "카테고리 합계".
    var isTotalAutomatic: Bool {
        totalMode == .categorySum
    }

    /// "그 외 카테고리" = 전체 − S. 전체가 S 보다 클 때만(갈래 A 뿐이다).
    var otherCategoriesAmount: Decimal? {
        guard let total, total > categorySum else {
            return nil
        }
        return total - categorySum
    }

    /// 갈래 A 에서 전체를 S 보다 작게 줄여 S 가 넘은 만큼. 경고 줄의 숫자다.
    var categoryExcess: Decimal? {
        guard let total, categorySum > total else {
            return nil
        }
        return categorySum - total
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
        total != nil && paymentExcess == nil && categoryExcess == nil
    }

    /// 입력 중인 결제수단 칸 아래 "최대 N" = 전체 − 다른 결제수단 합. 0 보다 작으면 0.
    func paymentMaximum(for group: PaymentGroup) -> Decimal? {
        guard let total else {
            return nil
        }
        let others = paymentAmounts.filter { $0.key != group }.values.reduce(0, +)
        return max(0, total - others)
    }

    /// 입력 중인 카테고리 칸 아래 "최대 N" = 전체 − 다른 카테고리 합, 0 보다 작으면 0. 갈래 A 이고 전체가 있을 때만.
    func categoryMaximum(for categoryID: Int) -> Decimal? {
        guard totalMode == .direct, let total else {
            return nil
        }
        let others = categoryLines.filter { $0.categoryID != categoryID }.compactMap(\.amount).reduce(0, +)
        return max(0, total - others)
    }

    /// 갈래 B 면 잠겨 있어 아무것도 바꾸지 않고 false. 그 밖에는 T 를 넣고 갈래 A 다 — 비워도 칸을 벗어날 때까지 A 다.
    /// S 보다 작아도 맞추지 않는다.
    @discardableResult
    mutating func setDirectTotal(_ value: Decimal?) -> Bool {
        guard totalMode != .categorySum else {
            return false
        }
        directTotal = value
        isClearingDirectTotal = value == nil
        return true
    }

    /// 전체 칸에서 벗어날 때 부른다. 갈래 A 에서 T 를 비웠으면 S > 0 이면 B, 아니면 빈 화면이다. T 가 있으면 그대로다.
    mutating func endTotalEditing() {
        isClearingDirectTotal = false
    }

    /// 갈래 A 에서 그 줄을 늘려 S 가 전체를 넘게 되면 `.overTotal`(상한보다 먼저 본다 — 전체는 상한 이하다). 줄이거나
    /// 같은 값은 S 가 이미 전체를 넘었어도 받는다. 바꾼 뒤의 S 가 상한을 넘으면 `.overLimit`(M2) — 그 카테고리의 줄이
    /// 없어도 이것이다. 거절하면 아무것도 바꾸지 않는다. 빈 화면에서 S 가 0 보다 커지면 B 가 된다.
    mutating func setCategoryAmount(_ value: Decimal?, for categoryID: Int) -> BudgetEditCategoryInput {
        guard let index = categoryLines.firstIndex(where: { $0.categoryID == categoryID }) else {
            return .overLimit
        }
        let current = categoryLines[index].amount ?? 0
        let newSum = categorySum - current + (value ?? 0)
        if totalMode == .direct, let total, (value ?? 0) > current, newSum > total {
            return .overTotal
        }
        guard newSum <= AddExpenseViewModel.maximumAmount else {
            return .overLimit
        }
        categoryLines[index].amount = value
        return .accepted
    }

    /// nil 이면 빈칸("예산 없음")으로 돌린다.
    mutating func setPaymentAmount(_ value: Decimal?, for group: PaymentGroup) {
        paymentAmounts[group] = value
    }

    /// 칩을 누르면 빈 줄을 맨 뒤에 붙인다 — 줄은 누른 순서로 쌓인다(UI_GUIDE 2026-10-04). 칩 순서 자리에 끼우지 않는다 —
    /// 칩 순서는 기기 목록이라 기기마다 줄 자리가 갈린다. 이미 줄이 있으면 무시한다. 삭제된 카테고리 칩은 `isDeleted` 줄
    /// 그대로 다시 넣는다(역시 맨 뒤).
    mutating func addCategory(_ categoryID: Int, isDeleted: Bool = false) {
        guard !categoryLines.contains(where: { $0.categoryID == categoryID }) else {
            return
        }
        categoryLines.append(BudgetEditCategoryLine(categoryID: categoryID, isDeleted: isDeleted, amount: nil))
    }

    /// 금액 줄 끝 X — 확인 없이 줄을 뺀다(금액이 있어도). 칩은 줄이 없는 카테고리라 저절로 돌아온다. 없으면 무시한다.
    mutating func removeCategory(_ categoryID: Int) {
        categoryLines.removeAll { $0.categoryID == categoryID }
    }

    /// 칩 묶음 = 칩 순서에서 줄이 있는 카테고리를 뺀 것.
    func chipCategoryIDs(chipOrder: [Int]) -> [Int] {
        let lineIDs = Set(categoryLines.map(\.categoryID))
        return chipOrder.filter { !lineIDs.contains($0) }
    }

    /// 통화 변경 확인 뒤: T·모든 몫을 비우고 카테고리 줄은 남긴다(스펙 §2.5). 빈 화면으로 돌아간다.
    mutating func clearAmounts() {
        directTotal = nil
        isClearingDirectTotal = false
        for index in categoryLines.indices {
            categoryLines[index].amount = nil
        }
        paymentAmounts = [:]
    }

    /// `입력 모두 지우기` 확인 뒤: T·결제수단 몫을 비우고 카테고리 줄은 모두 뺀다(칩으로 돌아간다). 빈 화면으로 돌아간다.
    mutating func clearAll() {
        directTotal = nil
        isClearingDirectTotal = false
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
