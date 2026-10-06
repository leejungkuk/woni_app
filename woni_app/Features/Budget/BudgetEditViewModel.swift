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
    case deleteMonth
    case clearAll
}

/// 쓰기 거절 뒤 편집을 닫고 예산 탭이 그 달을 다시 읽는 까닭. 토스트 문구는 탭이 고른다.
enum BudgetEditReloadReason: Equatable {
    /// `CATEGORY_NOT_FOUND` — 카테고리 목록은 닫기 전에 새로 받았다.
    case categoryDeletedReloaded
    /// `BUDGET_MONTH_OUT_OF_RANGE`(방어용).
    case monthNotAllowed
}

/// 금액 줄 이름. `Category` 가 `Equatable` 이 아니라 비교하지 않는다 — `if case` 로 꺼낸다.
enum BudgetEditLineLabel {
    /// "삭제된 카테고리" — 아이콘 없음.
    case deleted
    case category(Category)
}

enum BudgetEditOutcome {
    /// 저장하지 않고 닫았다. 예산 탭이 옮겨 갈 달(편집에서 마지막으로 보던 달)이고, 신원 없는 비회원은 nil(탭 그대로).
    case dismissed(ServerMonth?)
    /// 쓰기 응답. `writeToken` 은 쓰기 직전에 `beginWrite` 가 준 표 그대로다 — 뜻은 탭이 정한다.
    case saved(MonthlyBudget, writeToken: Int)
    case deleted(MonthlyBudget, writeToken: Int)
    case reloadRequired(ServerMonth, BudgetEditReloadReason)
}

/// 예산 편집 화면의 상태와 판정 — 열기·달 옮기기·통화 바꾸기·지난 달 불러오기·닫기·저장·삭제(스펙 :213-245 · :261-281).
/// 달은 기기 시계로 정하지 않는다 — 탭이 넘긴 서버 기준의 달과 범위 끝만 쓴다.
@MainActor
@Observable
final class BudgetEditViewModel {
    struct Context {
        let month: ServerMonth
        /// 범위 끝(서버의 이번 달 + 12). nil = 신원 없는 비회원 — 달을 고정한다.
        let lastMonth: ServerMonth?
        /// 회원: 탭이 보이던 그 달 응답. 탭이 계약 검사를 지난 것만 보이므로 다시 검사하지 않는다 — 달 대조만 한다.
        let initialBudget: MonthlyBudget?
    }

    /// 확인 창에서 확인하면 할 일. 창 종류(`dialog`)는 이것으로 정해진다.
    private enum PendingAction {
        case changeCurrency(CurrencyCode)
        case replaceWithPrevious(MonthlyBudget)
        case leaveToMonth(ServerMonth)
        case leaveAndClose
        case deleteMonth
        case clearAll
    }

    private static let firstMonth = ServerMonth(year: 2000, month: 1)

    private(set) var phase: BudgetEditPhase
    private(set) var month: ServerMonth
    private(set) var draft: BudgetEditDraft
    /// 화면이 보여 준 뒤 nil 로 돌린다.
    var toast: BudgetEditToast?
    /// 불러오기 칩 켜짐 — 지금 칸이 지난 달 값 그대로다. 칸을 하나라도 고치면 꺼진다.
    private(set) var isPreviousApplied = false
    /// 저장·삭제 중(신원 발급·카테고리 올리기 포함). 쓰기는 한 번에 하나다 — 그동안 저장·삭제·불러오기·달 이동·닫기·
    /// 통화 바꾸기·확인 창의 확인·입력은 아무것도 하지 않는다(스펙 :277, 카테고리 추가 화면 `isSaving` 과 같다).
    /// 입력까지 막는 까닭: 요청을 만들기 전에 고친 값은 저장되고 만든 뒤에 고친 값은 화면에만 남아, 같은 입력이 네트워크
    /// 타이밍에 따라 다르게 저장된다.
    private(set) var isWriting = false
    /// 넘는 입력 경고 줄 — 갈래 A 에서 카테고리 합을 전체보다 크게 만드는 키를 막았다. 초안을 바꾸는 다음 입력이나
    /// 카테고리 칸 벗어남(`endCategoryEditing()`)이 끈다. 합이 이미 전체를 넘은 상태면 켜지 않는다(합 초과 경고 줄 자리다).
    private(set) var showsCategoryOverTotalWarning = false
    /// 넘는 입력을 막은 횟수. 경고를 켜지 않을 때도 오른다 — 화면이 바뀔 때마다 VoiceOver 로 같은 문구를 읽는다.
    private(set) var categoryOverTotalRejectionCount = 0

    private let lastMonth: ServerMonth?
    private let chipOrder: () -> [Int]
    private let baseCurrency: CurrencyCode
    private let fetch: (_ year: Int, _ month: Int) async throws -> MonthlyBudget
    /// `BudgetWriteError` 를 던진다.
    private let saveBudget: (_ year: Int, _ month: Int, _ request: SaveBudgetRequest) async throws -> MonthlyBudget
    private let deleteBudget: (_ year: Int, _ month: Int) async throws -> MonthlyBudget
    private let hasIdentity: () -> Bool
    /// 실패해도 던지지 않는다 — 부른 뒤 `hasIdentity` 로 다시 본다.
    private let ensureIdentity: () async -> Void
    /// 실패해도 던지지 않고 큐에 남긴다 — 올린 뒤 `resolvedCategoryID` 로 다시 본다.
    private let flushPendingCategories: () async -> Void
    let resolvedCategoryID: (Int) -> Int
    private let refreshCategories: () async -> Void
    private let beginWrite: () -> Int
    private let onFinish: (BudgetEditOutcome) -> Void
    /// 보고 있는 달의 응답. 신원 없는 비회원·읽는 중·읽기 실패는 nil.
    private(set) var monthBudget: MonthlyBudget?
    /// 이 달 칸에 채운 지난 달 응답 — 금액 줄 이름만 읽는다. 달을 옮기면 버린다.
    private var appliedPrevious: MonthlyBudget?
    /// 바뀐 입력을 가늠하는 기준 — 달을 열거나 통화를 바꾼 직후의 초안.
    private var baseline: BudgetEditDraft
    private var pending: PendingAction?
    /// 읽기(달 이동·지난 달 불러오기)와 쓰기를 시작할 때마다 올린다. 응답은 시작 때의 값이 그대로일 때만 받아들인다.
    private var readGeneration = 0
    /// 통화를 바꿀 때마다 올린다. 지난 달 응답은 시작 때의 값이 그대로일 때만 받아들인다 — 늦은 응답이 방금 고른 통화를 되돌린다.
    private var currencyGeneration = 0

    init(
        context: Context,
        chipOrder: @escaping () -> [Int],
        baseCurrency: CurrencyCode,
        fetch: @escaping (_ year: Int, _ month: Int) async throws -> MonthlyBudget,
        save: @escaping (_ year: Int, _ month: Int, _ request: SaveBudgetRequest) async throws -> MonthlyBudget,
        delete: @escaping (_ year: Int, _ month: Int) async throws -> MonthlyBudget,
        hasIdentity: @escaping () -> Bool,
        ensureIdentity: @escaping () async -> Void,
        flushPendingCategories: @escaping () async -> Void,
        resolvedCategoryID: @escaping (Int) -> Int,
        refreshCategories: @escaping () async -> Void,
        beginWrite: @escaping () -> Int,
        onFinish: @escaping (BudgetEditOutcome) -> Void
    ) {
        let initial = context.initialBudget.flatMap {
            BudgetEditViewModel.isResponse($0, for: context.month) ? $0 : nil
        }
        let opened = initial.map {
            BudgetEditDraft(budget: $0, baseCurrency: baseCurrency)
        } ?? BudgetEditDraft(emptyWith: baseCurrency)
        month = context.month
        lastMonth = context.lastMonth
        draft = opened
        baseline = opened
        monthBudget = initial
        // 회원인데 그 달 응답이 없으면 빈 칸을 보이지 않는다 — 저장이 그 달 예산을 덮어쓴다.
        phase = initial == nil && context.lastMonth != nil ? .loadFailed : .editing
        self.chipOrder = chipOrder
        self.baseCurrency = baseCurrency
        self.fetch = fetch
        saveBudget = save
        deleteBudget = delete
        self.hasIdentity = hasIdentity
        self.ensureIdentity = ensureIdentity
        self.flushPendingCategories = flushPendingCategories
        self.resolvedCategoryID = resolvedCategoryID
        self.refreshCategories = refreshCategories
        self.beginWrite = beginWrite
        self.onFinish = onFinish
    }

    var dialog: BudgetEditDialog? {
        switch pending {
        case let .changeCurrency(currency): .changeCurrency(currency)
        case .replaceWithPrevious: .replaceWithPrevious
        case .leaveToMonth, .leaveAndClose: .leave
        case .deleteMonth: .deleteMonth
        case .clearAll: .clearAll
        case nil: nil
        }
    }

    /// 저장 캡슐. 꺼지면 `gray20`.
    var canSave: Bool {
        phase == .editing && draft.isSaveable && !isWriting
    }

    /// 바뀐 입력(스펙 :221 V10) — 금액·줄이 기준선과 다르거나 지난 달 값을 불러와 채운 상태. 통화만 바뀐 것은 아니다.
    /// 전체는 실제 전체로 본다 — 처음 연 전체와 같은 값을 직접 쳐도 바뀐 입력이 아니다(UI_GUIDE 2026-10-04).
    /// 카테고리 줄은 순서를 보지 않는다 — 순서만 바뀐 것은 바뀐 입력이 아니다(UI_GUIDE 2026-10-04).
    var hasChanges: Bool {
        isPreviousApplied || draft.hasUnsavedChanges(from: baseline)
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

    /// `‹ ›`. 범위 밖이거나 신원 없는 비회원이거나 쓰는 중이면 아무것도 하지 않는다. 바뀐 입력이 있으면 "나갈까요?"를 먼저 묻는다.
    func go(by offset: Int) async {
        let target = Self.month(at: Self.index(of: month) + offset)
        guard !isWriting,
              let lastMonth,
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

    /// X. 쓰는 중이면 아무것도 하지 않는다. 바뀐 입력이 있으면 "나갈까요?"를 먼저 묻는다.
    func requestClose() {
        guard !isWriting else {
            return
        }
        guard !hasChanges else {
            pending = .leaveAndClose
            return
        }
        finish()
    }

    /// 같은 통화거나 쓰는 중이면 아무것도 하지 않는다. 금액이 하나라도 있으면 "통화를 바꿀까요?"를 먼저 묻는다.
    func selectCurrency(_ currency: CurrencyCode) {
        guard !isWriting, currency != draft.currency else {
            return
        }
        guard !hasAnyAmount else {
            pending = .changeCurrency(currency)
            return
        }
        changeCurrency(to: currency)
    }

    /// 직전 달을 누를 때 읽는다. 값이 있고 칸에 금액이 있으면 "바꿀까요?"를 먼저 묻고, 비어 있으면 바로 채운다.
    /// 읽는 사이 달을 옮겼거나 통화를 바꿨거나 다른 확인 창이 떴으면 응답을 버린다(창·초안·토스트 그대로) — 창 종류가
    /// 바뀌거나 창 뒤에서 초안을 덮으면 같은 자리 버튼이 다른 일을 하고, 방금 고른 통화가 지난 달 통화로 되돌아간다. 다시 누르면 된다.
    func loadPrevious() async {
        guard canLoadPrevious, !isWriting else {
            return
        }
        let previous = Self.month(at: Self.index(of: month) - 1)
        let generation = beginRead()
        let currencyAtStart = currencyGeneration
        let budget: MonthlyBudget
        do {
            budget = try await fetch(previous.year, previous.month)
        } catch {
            if generation == readGeneration, currencyAtStart == currencyGeneration, pending == nil {
                toast = .previousLoadFailed
            }
            return
        }
        guard generation == readGeneration, currencyAtStart == currencyGeneration, pending == nil else {
            return
        }
        guard BudgetTabViewModel.isWellFormed(budget), Self.isResponse(budget, for: previous) else {
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

    /// 쓰는 중이면 아무것도 하지 않는다 — 창 뒤에서 초안을 덮거나 닫으면 쓰기가 실패해 남는 입력이 사용자의 입력이 아니다.
    func confirmDialog() async {
        guard !isWriting, let action = pending else {
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
        case .deleteMonth:
            await deleteMonth()
        case .clearAll:
            edit { $0.clearAll() }
        }
    }

    func cancelDialog() {
        pending = nil
    }

    /// 전체 칸에서 벗어남. 비운 채 벗어나면 카테고리 합이 있으면 갈래 B, 없으면 빈 화면이다. 카테고리 합보다 작은 값도
    /// 맞추지 않는다 — 경고 줄과 꺼진 저장 캡슐이 알린다(UI_GUIDE "먼저 적은 쪽이 기준이다").
    func endTotalEditing() {
        guard !isWriting else {
            return
        }
        edit { $0.endTotalEditing() }
    }

    /// 갈래 B 면 잠겨 있어 바꾸지 않고 토스트 — false 면 칸이 글자를 확정하지 않는다.
    /// 쓰는 중에는 바꾸지 않고 true 다(카테고리 칸과 같다).
    @discardableResult
    func setDirectTotal(_ value: Decimal?) -> Bool {
        guard !isWriting else {
            return true
        }
        guard edit({ $0.setDirectTotal(value) }) else {
            toast = .totalLocked
            return false
        }
        return true
    }

    /// 잠긴 전체 칸(갈래 B)을 누름. B 가 아니거나 쓰는 중이면 아무것도 하지 않는다.
    func tapLockedTotal() {
        guard !isWriting, draft.totalMode == .categorySum else {
            return
        }
        toast = .totalLocked
    }

    /// 카테고리 합이 상한을 넘으면 거절하고 상한 토스트. 갈래 A 에서 합이 전체를 넘게 되면 토스트 없이 거절하고 넘는
    /// 입력 경고(`showsCategoryOverTotalWarning`)를 켠다. false 면 칸이 글자를 확정하지 않는다.
    /// 쓰는 중에는 바꾸지 않고 true 다 — 경고·토스트도 없다.
    @discardableResult
    func setCategoryAmount(_ value: Decimal?, for categoryID: Int) -> Bool {
        guard !isWriting else {
            return true
        }
        switch edit({ $0.setCategoryAmount(value, for: categoryID) }) {
        case .accepted:
            return true
        case .overLimit:
            toast = .amountOverLimit
            return false
        case .overTotal:
            categoryOverTotalRejectionCount += 1
            showsCategoryOverTotalWarning = draft.categoryExcess == nil
            return false
        }
    }

    /// 카테고리 칸에서 벗어남 — 넘는 입력 경고를 끈다. 막은 횟수는 그대로다.
    func endCategoryEditing() {
        showsCategoryOverTotalWarning = false
    }

    func setPaymentAmount(_ value: Decimal?, for group: PaymentGroup) {
        guard !isWriting else {
            return
        }
        edit { $0.setPaymentAmount(value, for: group) }
    }

    /// 칩 묶음 = 칩 순서에서 줄이 있는 카테고리를 뺀 것. 양쪽을 서버 번호로 바꿔 비교한다 — 올리기가 목록 번호를 바꾼 뒤
    /// `categoriesDidChange()` 전까지는 줄이 임시 번호·칩이 서버 번호라, 원번호로 비교하면 같은 카테고리가 칩에 다시 보인다.
    /// 이 달 응답이 삭제로 표시한 카테고리도 뺀다(기기 목록에 있어도) — 삭제는 서버 표시로만 판정한다. 기기 목록을 보면
    /// 삭제가 안 도착한 기기에서만 같은 카테고리가 보통 칩과 삭제된 칩 두 곳에 보인다.
    var chipCategoryIDs: [Int] {
        let hiddenIDs = resolvedLineCategoryIDs.union(serverDeletedCategoryIDs)
        return chipOrder().filter { !hiddenIDs.contains(resolvedCategoryID($0)) }
    }

    /// 이미 줄이 있는 카테고리(서버 번호로 비교)면 아무것도 하지 않는다 — 같은 카테고리가 두 줄이 되면 저장이 거절된다.
    func addCategory(_ categoryID: Int) {
        guard !isWriting, !resolvedLineCategoryIDs.contains(resolvedCategoryID(categoryID)) else {
            return
        }
        edit { $0.addCategory(categoryID) }
    }

    /// 접힌 결제수단 섹션을 펼친다. 전체가 비어 있으면 캡슐이 비활성이다.
    func togglePaymentSection() {
        guard !isWriting, draft.isPaymentInputEnabled else {
            return
        }
        draft.isPaymentExpanded = true
    }
}

// MARK: 줄 빼기·삭제된 카테고리 칩·입력 모두 지우기(UI_GUIDE 2026-10-04) — 판정은 `BudgetEditViewModel+Lines.swift`

extension BudgetEditViewModel {
    /// 금액 줄 끝 X. 확인 없이 뺀다(금액이 있어도). 쓰는 중이면 아무것도 하지 않는다.
    func removeCategory(_ categoryID: Int) {
        guard !isWriting else {
            return
        }
        edit { $0.removeCategory(categoryID) }
    }

    /// 삭제된 칩을 누르면 삭제된 줄 그대로 다시 넣는다. 삭제된 칩에 없는 번호면 아무것도 하지 않는다.
    func addDeletedCategory(_ categoryID: Int) {
        guard !isWriting, deletedChipCategoryIDs.contains(categoryID) else {
            return
        }
        edit { $0.addCategory(categoryID, isDeleted: true) }
    }

    /// "입력한 금액을 모두 지울까요?"를 먼저 묻는다.
    func requestClearAll() {
        guard canClearAll else {
            return
        }
        pending = .clearAll
    }
}

// MARK: 저장·삭제

extension BudgetEditViewModel {
    /// 순서: 신원 발급(없을 때) → 새 카테고리 올리기 → 저장(스펙 :263 · :213-215). 실패하면 입력을 남기고 토스트.
    /// 저장 캡슐이 켜졌을 때만 보낸다 — 전체를 카테고리 합보다 작게 줄였으면 맞추지 않고 꺼져 있다.
    func save() async {
        guard canSave else {
            return
        }
        startWriting()
        defer { isWriting = false }
        if !hasIdentity() {
            await ensureIdentity()
            guard hasIdentity() else {
                toast = .saveFailed
                return
            }
        }
        await flushPendingCategories()
        // 올리기가 바꾼 번호를 PUT 앞에서 옮긴다 — 저장이 실패해 입력이 남을 때 초안이 임시 번호 그대로면 같은 카테고리가
        // 줄(임시 번호)과 칩(서버 번호)에 함께 보이고, 칩을 다시 누르면 요청에 같은 번호가 두 번 들어간다.
        remapCategoryIDs()
        guard let request = draft.saveRequest(resolvingCategoryID: resolvedCategoryID) else {
            return
        }
        // 임시 번호를 보내면 `CATEGORY_NOT_FOUND` 가 되어 "삭제된 카테고리"로 잘못 안내된다(스펙 :215).
        guard request.categoryAmounts.allSatisfy({ $0.categoryId >= 0 }) else {
            toast = .categoryUploadFailed
            return
        }
        let token = beginWrite()
        do {
            let saved = try await saveBudget(month.year, month.month, request)
            onFinish(.saved(saved, writeToken: token))
        } catch {
            await handleWriteFailure(error, otherFailure: .saveFailed)
        }
    }

    /// `이 달 예산 삭제`. 그 달에 예산이 있을 때만이고, "5월 예산을 삭제할까요?"를 먼저 묻는다.
    func requestDelete() {
        guard showsDeleteButton, !isWriting else {
            return
        }
        pending = .deleteMonth
    }

    /// 카테고리 목록이 바뀌었을 수 있다(화면이 부른다). 백그라운드 동기화가 편집 중에 새 카테고리를 올리면 줄은 임시 번호·
    /// 칩은 서버 번호로 같은 카테고리가 둘 보인다 — 초안·기준선의 임시 번호를 서버 번호로 바꾼다. 여러 번 불러도 같다.
    func categoriesDidChange() {
        remapCategoryIDs()
    }

    /// 금액 줄 이름(스펙 :233). 삭제는 서버 표시로만 판정한다 — 기기 목록을 먼저 보면 삭제가 도착한 기기와 안 도착한
    /// 기기의 이름이 갈린다. 다음은 지금 목록(올리기가 바꾼 번호로도) → 이 달·불러온 지난 달 응답의 서버 이름(로컬 삭제
    /// 대기라 목록에 없는 카테고리) 순이다. 어디에도 없으면 "삭제된 카테고리"다 — 줄을 숨기면 보이지 않는 금액이 저장된다.
    /// 저장은 서버의 `CATEGORY_NOT_FOUND` 다시 불러오기에 맡긴다(임시 가정 2026-10-03 #17).
    func lineLabel(_ line: BudgetEditCategoryLine, in categories: [Category]) -> BudgetEditLineLabel {
        guard !line.isDeleted else {
            return .deleted
        }
        let id = resolvedCategoryID(line.categoryID)
        if let category = categories.first(where: { resolvedCategoryID($0.id) == id }) {
            return .category(category)
        }
        let serverLines = (monthBudget?.categories ?? []) + (appliedPrevious?.categories ?? [])
        if let serverLine = serverLines.first(where: { $0.category.id == id }) {
            return .category(serverLine.category)
        }
        return .deleted
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

    /// 요청한 달의 응답인가(계약 v2 :44 "`year`·`month` | 요청한 달"). 아니면 읽기 실패와 같다 —
    /// 다른 달 금액을 이 달 칸에 열면 저장이 이 달 예산을 덮어쓴다.
    static func isResponse(_ budget: MonthlyBudget, for month: ServerMonth) -> Bool {
        budget.year == month.year && budget.month == month.month
    }

    var isAfterFirstMonth: Bool {
        Self.index(of: month) > Self.index(of: Self.firstMonth)
    }

    /// 초안을 바꾸고, 금액·줄이 바뀌었으면 불러오기 칩과 넘는 입력 경고를 끈다.
    func edit<Value>(_ change: (inout BudgetEditDraft) -> Value) -> Value {
        let before = draft
        let result = change(&draft)
        if draft.hasChanges(from: before) {
            isPreviousApplied = false
            showsCategoryOverTotalWarning = false
        }
        return result
    }

    /// 새 초안을 기준선으로 삼는다 — 그 직후에는 바뀐 입력이 없다.
    func replaceDraft(with newDraft: BudgetEditDraft) {
        draft = newDraft
        baseline = newDraft
        isPreviousApplied = false
        showsCategoryOverTotalWarning = false
    }

    /// 금액을 모두 비우고(줄은 남김) 통화를 바꾼다. 통화만 바뀐 상태는 바뀐 입력이 아니다(스펙 :221).
    /// 읽는 중인 지난 달 응답은 버린다.
    func changeCurrency(to currency: CurrencyCode) {
        currencyGeneration += 1
        var changed = draft
        changed.clearAmounts()
        changed.currency = currency
        replaceDraft(with: changed)
    }

    func applyPrevious(_ previous: MonthlyBudget) {
        let dropped = draft.applyPrevious(previous)
        appliedPrevious = previous
        isPreviousApplied = true
        showsCategoryOverTotalWarning = false
        if dropped > 0 {
            toast = .droppedDeletedCategories(dropped)
        }
    }

    /// 옮기기를 시작하는 순간 옛 달의 초안·기준선을 버린다 — 읽는 동안과 읽기 실패 뒤에는 바뀐 입력이 없다.
    /// 응답은 탭과 같은 계약 검사와 달 대조를 지나야 쓴다 — 깨진 응답을 기준통화·빈칸으로 메우면 저장이 그 달 예산을 덮어쓴다.
    func move(to target: ServerMonth) async {
        month = target
        phase = .loading
        monthBudget = nil
        appliedPrevious = nil
        replaceDraft(with: BudgetEditDraft(emptyWith: baseCurrency))
        let generation = beginRead()
        do {
            let budget = try await fetch(target.year, target.month)
            guard generation == readGeneration else {
                return
            }
            guard BudgetTabViewModel.isWellFormed(budget), Self.isResponse(budget, for: target) else {
                phase = .loadFailed
                return
            }
            monthBudget = budget
            replaceDraft(with: BudgetEditDraft(budget: budget, baseCurrency: baseCurrency))
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

    /// 번호만 바뀐 것은 바뀐 입력이 아니다 — 기준선도 같이 바꾸고 불러오기 칩은 그대로 둔다.
    func remapCategoryIDs() {
        draft.remapCategoryIDs(resolvedCategoryID)
        baseline.remapCategoryIDs(resolvedCategoryID)
    }

    /// 쓰기를 시작한다. 진행 중인 읽기(지난 달 불러오기)의 응답은 성공·실패 모두 버린다 — 쓰기 전 값을 읽었을 수 있다(스펙 :278).
    func startWriting() {
        isWriting = true
        readGeneration += 1
    }

    func deleteMonth() async {
        startWriting()
        defer { isWriting = false }
        let token = beginWrite()
        do {
            let deleted = try await deleteBudget(month.year, month.month)
            onFinish(.deleted(deleted, writeToken: token))
        } catch {
            await handleWriteFailure(error, otherFailure: .deleteFailed)
        }
    }

    /// 저장·삭제 거절(UI_GUIDE "저장·삭제 거절" — 한 표다). 두 예외만 편집을 닫고 탭이 그 달을 다시 읽게 하고,
    /// 나머지는 입력을 남기고 토스트 — 실패를 성공처럼 닫거나 미설정으로 바꾸지 않는다(스펙 :241).
    /// "그 밖·연결 실패"만 쓰기마다 문구가 달라 `otherFailure` 로 받는다.
    func handleWriteFailure(_ error: any Error, otherFailure: BudgetEditToast) async {
        switch error as? BudgetWriteError {
        case .invalidAmount:
            toast = .amountOverLimit
        case .categoryNotFound:
            // 새로 받지 않으면 지워진 카테고리가 칩에 남아 같은 실패가 되풀이된다(스펙 :245).
            await refreshCategories()
            onFinish(.reloadRequired(month, .categoryDeletedReloaded))
        case .monthOutOfRange:
            onFinish(.reloadRequired(month, .monthNotAllowed))
        case .totalRequired:
            toast = .totalRequired
        case .allocationExceedsTotal:
            toast = .allocationExceedsTotal
        case .other, nil:
            toast = otherFailure
        }
    }

    func beginRead() -> Int {
        readGeneration += 1
        return readGeneration
    }
}
