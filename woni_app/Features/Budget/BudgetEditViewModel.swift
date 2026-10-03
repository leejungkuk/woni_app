//
//  BudgetEditViewModel.swift
//  woni_app
//

import Foundation
import Observation

enum BudgetEditPhase: Equatable {
    /// `‹ ›` 로 옮긴 달을 읽는 중.
    case loading
    case editing
    /// 옮긴 달을 읽지 못했다. 저장·불러오기·삭제를 막는다 — 빈 칸을 보이면 저장이 그 달 예산을 덮어쓴다.
    case loadFailed
}

/// 확인 창 종류. 문구는 화면이 고른다.
enum BudgetEditDialog: Equatable {
    case changeCurrency(CurrencyCode)
    case replaceWithPrevious
    case leave
}

/// 토스트 종류. 문구는 화면이 고른다.
enum BudgetEditToast: Equatable {
    case totalBelowCategorySum
    case amountOverLimit
    case noPreviousBudget
    case previousLoadFailed
    case droppedDeletedCategories(Int)
}

enum BudgetEditOutcome {
    /// 저장하지 않고 닫았다. 예산 탭이 옮겨 갈 달(편집에서 마지막으로 보던 달)이고, 신원 없는 비회원은 nil(탭 그대로).
    case dismissed(ServerMonth?)
}

/// 예산 편집 화면의 상태와 판정 — 열기·달 옮기기·통화 바꾸기·지난 달 불러오기·닫기(스펙 :218-236 · :261-281).
/// 달은 기기 시계로 정하지 않는다 — 탭이 넘긴 서버 기준의 달과 범위 끝만 쓴다.
@MainActor
@Observable
final class BudgetEditViewModel {
    struct Context {
        let month: ServerMonth
        /// 범위 끝(서버의 이번 달 + 12). nil = 신원 없는 비회원 — 달을 고정한다.
        let lastMonth: ServerMonth?
        /// 회원: 탭이 보이던 그 달 응답. 탭이 계약 검사를 지난 것만 보이므로 다시 검사하지 않는다.
        let initialBudget: MonthlyBudget?
    }

    /// 확인 창에서 확인하면 할 일. 창 종류(`dialog`)는 이것으로 정해진다.
    private enum PendingAction {
        case changeCurrency(CurrencyCode)
        case replaceWithPrevious(MonthlyBudget)
        case leaveToMonth(ServerMonth)
        case leaveAndClose
    }

    private static let firstMonth = ServerMonth(year: 2000, month: 1)

    private(set) var phase: BudgetEditPhase
    private(set) var month: ServerMonth
    private(set) var draft: BudgetEditDraft
    /// 화면이 보여 준 뒤 nil 로 돌린다.
    var toast: BudgetEditToast?
    /// 불러오기 칩 켜짐 — 지금 칸이 지난 달 값 그대로다. 칸을 하나라도 고치면 꺼진다.
    private(set) var isPreviousApplied = false

    private let lastMonth: ServerMonth?
    private let chipOrder: () -> [Int]
    private let baseCurrency: CurrencyCode
    private let fetch: (_ year: Int, _ month: Int) async throws -> MonthlyBudget
    private let onFinish: (BudgetEditOutcome) -> Void
    /// 보고 있는 달의 응답. 신원 없는 비회원·읽는 중·읽기 실패는 nil.
    private var monthBudget: MonthlyBudget?
    /// 바뀐 입력을 가늠하는 기준 — 달을 열거나 통화를 바꾼 직후의 초안.
    private var baseline: BudgetEditDraft
    private var pending: PendingAction?
    /// 이번에 전체 칸에 들어와 쳤는가. 치지 않고 벗어나면 합계로 맞추지 않는다.
    private var typedTotal = false
    /// 읽기(달 이동·지난 달 불러오기)를 시작할 때마다 올린다. 응답은 시작 때의 값이 그대로일 때만 받아들인다.
    private var readGeneration = 0

    init(
        context: Context,
        chipOrder: @escaping () -> [Int],
        baseCurrency: CurrencyCode,
        fetch: @escaping (_ year: Int, _ month: Int) async throws -> MonthlyBudget,
        onFinish: @escaping (BudgetEditOutcome) -> Void
    ) {
        let opened = context.initialBudget.map {
            BudgetEditDraft(budget: $0, chipOrder: chipOrder(), baseCurrency: baseCurrency)
        } ?? BudgetEditDraft(emptyWith: baseCurrency)
        month = context.month
        lastMonth = context.lastMonth
        draft = opened
        baseline = opened
        monthBudget = context.initialBudget
        // 회원인데 그 달 응답이 없으면 빈 칸을 보이지 않는다 — 저장이 그 달 예산을 덮어쓴다.
        phase = context.initialBudget == nil && context.lastMonth != nil ? .loadFailed : .editing
        self.chipOrder = chipOrder
        self.baseCurrency = baseCurrency
        self.fetch = fetch
        self.onFinish = onFinish
    }

    var dialog: BudgetEditDialog? {
        switch pending {
        case let .changeCurrency(currency): .changeCurrency(currency)
        case .replaceWithPrevious: .replaceWithPrevious
        case .leaveToMonth, .leaveAndClose: .leave
        case nil: nil
        }
    }

    /// 바뀐 입력(스펙 :221 V10) — 금액·줄이 기준선과 다르거나 지난 달 값을 불러와 채운 상태. 통화만 바뀐 것은 아니다.
    var hasChanges: Bool {
        isPreviousApplied || draft.hasChanges(from: baseline)
    }

    var showsMonthArrows: Bool {
        lastMonth != nil
    }

    var canGoPrevious: Bool {
        showsMonthArrows && isAfterFirstMonth
    }

    var canGoNext: Bool {
        guard let lastMonth else {
            return false
        }
        return Self.index(of: month) < Self.index(of: lastMonth)
    }

    var showsLoadPrevious: Bool {
        lastMonth != nil
    }

    /// 2000-01 과 불러올 수 없음(읽는 중 포함)에서는 누를 수 없다.
    var canLoadPrevious: Bool {
        showsLoadPrevious && phase == .editing && isAfterFirstMonth
    }

    /// 그 달에 예산이 있을 때만.
    var showsDeleteButton: Bool {
        guard phase == .editing, lastMonth != nil, let monthBudget else {
            return false
        }
        return monthBudget.status != .notSet
    }

    /// `‹ ›`. 범위 밖이거나 신원 없는 비회원이면 아무것도 하지 않는다. 바뀐 입력이 있으면 "나갈까요?"를 먼저 묻는다.
    func go(by offset: Int) async {
        let target = Self.month(at: Self.index(of: month) + offset)
        guard let lastMonth,
              (Self.index(of: Self.firstMonth) ... Self.index(of: lastMonth)).contains(Self.index(of: target))
        else {
            return
        }
        guard !hasChanges else {
            pending = .leaveToMonth(target)
            return
        }
        await move(to: target)
    }

    /// X. 바뀐 입력이 있으면 "나갈까요?"를 먼저 묻는다.
    func requestClose() {
        guard !hasChanges else {
            pending = .leaveAndClose
            return
        }
        finish()
    }

    /// 같은 통화면 아무것도 하지 않는다. 금액이 하나라도 있으면 "통화를 바꿀까요?"를 먼저 묻는다.
    func selectCurrency(_ currency: CurrencyCode) {
        guard currency != draft.currency else {
            return
        }
        guard !hasAnyAmount else {
            pending = .changeCurrency(currency)
            return
        }
        changeCurrency(to: currency)
    }

    /// 직전 달을 누를 때 읽는다. 값이 있고 칸에 금액이 있으면 "바꿀까요?"를 먼저 묻고, 비어 있으면 바로 채운다.
    /// 읽는 사이 다른 확인 창이 떴으면 응답을 버린다(창·초안·토스트 그대로) — 창 종류가 바뀌거나 창 뒤에서 초안을 덮으면
    /// 같은 자리 버튼이 다른 일을 한다. 다시 누르면 된다.
    func loadPrevious() async {
        guard canLoadPrevious else {
            return
        }
        let previous = Self.month(at: Self.index(of: month) - 1)
        let generation = beginRead()
        let budget: MonthlyBudget
        do {
            budget = try await fetch(previous.year, previous.month)
        } catch {
            if generation == readGeneration, pending == nil {
                toast = .previousLoadFailed
            }
            return
        }
        guard generation == readGeneration, pending == nil else {
            return
        }
        guard BudgetTabViewModel.isWellFormed(budget) else {
            toast = .previousLoadFailed
            return
        }
        guard budget.status != .notSet else {
            toast = .noPreviousBudget
            return
        }
        guard !hasAnyAmount else {
            pending = .replaceWithPrevious(budget)
            return
        }
        applyPrevious(budget)
    }

    func confirmDialog() async {
        guard let action = pending else {
            return
        }
        pending = nil
        switch action {
        case let .changeCurrency(currency):
            changeCurrency(to: currency)
        case let .replaceWithPrevious(previous):
            applyPrevious(previous)
        case let .leaveToMonth(target):
            await move(to: target)
        case .leaveAndClose:
            finish()
        }
    }

    func cancelDialog() {
        pending = nil
    }

    /// 전체 칸에 들어옴. 이번에 쳤는지를 새로 센다.
    func beginTotalEditing() {
        typedTotal = false
    }

    /// 전체 칸에서 벗어남. 이번에 쳐서 카테고리 합보다 작으면 합계로 맞추고 토스트(UI_GUIDE "작게 입력하고 끝내면").
    func endTotalEditing() {
        guard typedTotal else {
            return
        }
        typedTotal = false
        if edit({ $0.commitDirectTotal() }) {
            toast = .totalBelowCategorySum
        }
    }

    func setDirectTotal(_ value: Decimal?) {
        typedTotal = true
        edit { $0.setDirectTotal(value) }
    }

    /// 카테고리 합이 상한을 넘으면 거절하고 상한 토스트 — false 면 칸이 글자를 확정하지 않는다.
    @discardableResult
    func setCategoryAmount(_ value: Decimal?, for categoryID: Int) -> Bool {
        let accepted = edit { $0.setCategoryAmount(value, for: categoryID) }
        if !accepted {
            toast = .amountOverLimit
        }
        return accepted
    }

    func setPaymentAmount(_ value: Decimal?, for group: PaymentGroup) {
        edit { $0.setPaymentAmount(value, for: group) }
    }

    func addCategory(_ categoryID: Int) {
        let order = chipOrder()
        edit { $0.addCategory(categoryID, chipOrder: order) }
    }

    /// 접힌 결제수단 섹션을 펼친다. 전체가 비어 있으면 캡슐이 비활성이다.
    func togglePaymentSection() {
        guard draft.isPaymentInputEnabled else {
            return
        }
        draft.isPaymentExpanded = true
    }
}

private extension BudgetEditViewModel {
    /// 달 번호 = 해 × 12 + 달 − 1. `BudgetTabViewModel` 과 같은 식이다 — 기기 달력을 쓰지 않는다.
    static func index(of month: ServerMonth) -> Int {
        month.year * 12 + month.month - 1
    }

    static func month(at index: Int) -> ServerMonth {
        ServerMonth(year: index / 12, month: index % 12 + 1)
    }

    var isAfterFirstMonth: Bool {
        Self.index(of: month) > Self.index(of: Self.firstMonth)
    }

    /// 금액이 하나라도 적혀 있는가. 0 도 금액이다.
    var hasAnyAmount: Bool {
        draft.directTotal != nil
            || draft.categoryLines.contains { $0.amount != nil }
            || !draft.paymentAmounts.isEmpty
    }

    /// 초안을 바꾸고, 금액·줄이 바뀌었으면 불러오기 칩을 끈다.
    func edit<Value>(_ change: (inout BudgetEditDraft) -> Value) -> Value {
        let before = draft
        let result = change(&draft)
        if draft.hasChanges(from: before) {
            isPreviousApplied = false
        }
        return result
    }

    /// 새 초안을 기준선으로 삼는다 — 그 직후에는 바뀐 입력이 없다.
    func replaceDraft(with newDraft: BudgetEditDraft) {
        draft = newDraft
        baseline = newDraft
        isPreviousApplied = false
        typedTotal = false
    }

    /// 금액을 모두 비우고(줄은 남김) 통화를 바꾼다. 통화만 바뀐 상태는 바뀐 입력이 아니다(스펙 :221).
    func changeCurrency(to currency: CurrencyCode) {
        var changed = draft
        changed.clearAmounts()
        changed.currency = currency
        replaceDraft(with: changed)
    }

    func applyPrevious(_ previous: MonthlyBudget) {
        let dropped = draft.applyPrevious(previous, chipOrder: chipOrder())
        isPreviousApplied = true
        if dropped > 0 {
            toast = .droppedDeletedCategories(dropped)
        }
    }

    /// 옮기기를 시작하는 순간 옛 달의 초안·기준선을 버린다 — 읽는 동안과 읽기 실패 뒤에는 바뀐 입력이 없다.
    /// 응답은 탭과 같은 계약 검사를 지나야 쓴다 — 깨진 응답을 기준통화·빈칸으로 메우면 저장이 그 달 예산을 덮어쓴다.
    func move(to target: ServerMonth) async {
        month = target
        phase = .loading
        monthBudget = nil
        replaceDraft(with: BudgetEditDraft(emptyWith: baseCurrency))
        let generation = beginRead()
        do {
            let budget = try await fetch(target.year, target.month)
            guard generation == readGeneration else {
                return
            }
            guard BudgetTabViewModel.isWellFormed(budget) else {
                phase = .loadFailed
                return
            }
            monthBudget = budget
            replaceDraft(with: BudgetEditDraft(budget: budget, chipOrder: chipOrder(), baseCurrency: baseCurrency))
            phase = .editing
        } catch {
            if generation == readGeneration {
                phase = .loadFailed
            }
        }
    }

    func finish() {
        onFinish(.dismissed(lastMonth == nil ? nil : month))
    }

    func beginRead() -> Int {
        readGeneration += 1
        return readGeneration
    }
}
