//
//  BudgetTabViewModel.swift
//  woni_app
//

import Foundation
import Observation

/// 읽은 달의 화면 재료. 예산과 같은 달의 기기 안 사정(동기화 전 지출·삭제 대기 카테고리)을 함께 읽어 담는다.
struct BudgetTabContent {
    let budget: MonthlyBudget
    let unsyncedExpenseCount: Int
    let pendingDeletionCategoryIDs: Set<Int>
}

/// 예산 탭에 전달되는 사건. 다시 읽을지는 `BudgetTabViewModel.send(_:)` 한 곳에서 정한다.
enum BudgetTabEvent {
    case tabShown, tabHidden, foreground, ledgerChanged, connectivityRestored, identityChanged
}

/// 예산 탭의 상태·달 이동·다시 읽기 판정. 달은 기기 시계로 정하지 않는다 — 처음엔 서버 시각의 이번 달을
/// 확인하고, 그 뒤로는 받아들인 응답의 `currentYear`·`currentMonth` 가 서버의 이번 달이다(스펙 §3 G5).
@Observable
@MainActor
final class BudgetTabViewModel {
    enum Phase {
        /// 처음 열 때·달을 넘길 때만. 다시 읽기는 보던 상태를 응답이 올 때까지 그대로 둔다.
        case loading
        case loaded(BudgetTabContent)
        /// 불러올 수 없음. 다시 읽기가 실패해도 여기다 — 지금 값인지 모르는 옛 숫자를 남기지 않는다.
        case failed
        /// 신원이 없는 비회원. 서버를 부르지 않는다.
        case noIdentity
    }

    private static let firstMonth = ServerMonth(year: 2000, month: 1)
    private static let monthsAfterServerMonth = 12

    private(set) var phase: Phase = .loading
    /// 서버의 이번 달. 모르면 nil.
    private(set) var serverMonth: ServerMonth?
    /// 보고 있는 달.
    private(set) var month: ServerMonth?

    private let probeServerMonth: () async throws -> ServerMonth
    private let fetch: (_ year: Int, _ month: Int) async throws -> MonthlyBudget
    private let unsyncedExpenseCount: (_ year: Int, _ month: Int) async throws -> Int
    private let pendingDeletionCategoryIDs: () throws -> Set<Int>
    private let hasIdentity: () -> Bool
    private(set) var isVisible = false
    /// 읽기를 시작하거나 상태를 버릴 때마다 올린다. 응답은 시작 때의 값이 그대로일 때만 받아들인다 —
    /// 늦게 온 옛 응답이 새 달·새 계정 화면을 덮지 않게 한다.
    private var readGeneration = 0

    init(
        probeServerMonth: @escaping () async throws -> ServerMonth,
        fetch: @escaping (_ year: Int, _ month: Int) async throws -> MonthlyBudget,
        unsyncedExpenseCount: @escaping (_ year: Int, _ month: Int) async throws -> Int,
        pendingDeletionCategoryIDs: @escaping () throws -> Set<Int>,
        hasIdentity: @escaping () -> Bool
    ) {
        self.probeServerMonth = probeServerMonth
        self.fetch = fetch
        self.unsyncedExpenseCount = unsyncedExpenseCount
        self.pendingDeletionCategoryIDs = pendingDeletionCategoryIDs
        self.hasIdentity = hasIdentity
    }

    /// 달 이름과 `‹ ›` 는 서버의 이번 달을 알 때만 보인다 — 모를 때 기기 시계의 달을 보이지 않는다.
    var showsMonthHeader: Bool {
        serverMonth != nil
    }

    /// 예산이 있는 달을 읽었을 때만. 미설정 달은 카드의 `예산 정하기` 가 길이다.
    var showsEditButton: Bool {
        guard case let .loaded(content) = phase else {
            return false
        }
        return content.budget.status != .notSet
    }

    var canGoPrevious: Bool {
        guard let month, serverMonth != nil else {
            return false
        }
        return Self.index(of: month) > Self.index(of: Self.firstMonth)
    }

    var canGoNext: Bool {
        guard let month, let lastMonth else {
            return false
        }
        return Self.index(of: month) < Self.index(of: lastMonth)
    }

    /// 피커 휠의 해 범위. `‹ ›` 범위와 같다. 서버의 이번 달을 모르면 nil.
    var pickerYears: ClosedRange<Int>? {
        lastMonth.map { Self.firstMonth.year ... $0.year }
    }

    func pickerMonths(inYear year: Int) -> ClosedRange<Int> {
        guard let lastMonth, year == lastMonth.year else {
            return 1 ... 12
        }
        return 1 ... lastMonth.month
    }

    /// 탭 전환을 사건으로 바꾼다. 예산으로 오면 표시, 예산에서 떠나면 숨김이다.
    nonisolated static func event(fromTab oldTab: AppTab, toTab newTab: AppTab) -> BudgetTabEvent? {
        switch (oldTab, newTab) {
        case (_, .budget): .tabShown
        case (.budget, _): .tabHidden
        default: nil
        }
    }

    func handle(_ event: BudgetTabEvent) async {
        await send(event).value
    }

    /// 사건을 받은 순서대로 상태(보임·숨김·신원 리셋)를 바로 바꾸고, 다시 읽기가 필요하면 시작해 그 작업을 돌려준다.
    /// 따로 만든 작업은 만든 순서대로 돈다는 보장이 없어(SE-0306) 상태를 작업 안에서 바꾸면 늦은 숨김이 표시를 덮는다.
    @discardableResult
    func send(_ event: BudgetTabEvent) -> Task<Void, Never> {
        switch event {
        case .tabShown:
            isVisible = true
        case .tabHidden:
            isVisible = false
        case .identityChanged:
            reset()
        case .foreground, .ledgerChanged, .connectivityRestored:
            break
        }
        return Task { await reloadIfNeeded(after: event) }
    }

    /// 원장 변경 스트림이 끝날 때까지 신호마다 `.ledgerChanged` 를 보낸다(선례 `MainViewModel.observeLedgerChanges`).
    /// 다시 읽기를 기다리지 않는다 — 구독이 취소돼도 시작한 읽기는 끝까지 간다.
    func observeLedgerChanges(_ events: AsyncStream<Void>) async {
        for await _ in events {
            send(.ledgerChanged)
        }
    }

    /// 연결 스트림이 끝날 때까지 `true` 가 올 때마다 `.connectivityRestored` 를 보낸다.
    func observeConnectivity(_ changes: AsyncStream<Bool>) async {
        for await isOnline in changes where isOnline {
            send(.connectivityRestored)
        }
    }

    /// `‹ ›`. 범위 밖이면 아무것도 하지 않는다.
    func go(by offset: Int) async {
        guard let month else {
            return
        }
        await show(Self.month(at: Self.index(of: month) + offset))
    }

    /// 피커 저장. 범위 밖이거나 1~12 밖의 달이면 아무것도 하지 않는다.
    func select(year: Int, month: Int) async {
        guard (1 ... 12).contains(month) else {
            return
        }
        await show(ServerMonth(year: year, month: month))
    }
}

extension BudgetTabViewModel {
    /// 계약(인계 2026-09-29 `BudgetAxisResponse`·`BudgetLine`)상 금액이 있는 달은 통화·전체 줄이 있다.
    /// v2(2026-10-01) :51·:53 상 결제수단은 세 묶음이 하나씩이고 그 외 카테고리 줄이 있다. 줄마다 카드를 그릴 수
    /// 있어야 한다 — 판정은 카드와 같은 `BudgetTotalLine`·`BudgetShare` 다. 하루 권장은 초과일 때만 금액이 없다
    /// (인계 :96). 미설정 달은 v2 :49-55 상 통화·전체·그 외 카테고리·하루 권장이 없고 결제수단이 [] 다. 카테고리도
    /// [] 다(백엔드 `MonthlyBudgetResponse.notSet`). 남은 일수 검사는 미설정 달에도 건다(v2 :46 — 예산이 없어도 준다).
    /// 깨진 응답을 화면이 기본값으로 메우지 않게 실패로 둔다.
    static func isWellFormed(_ budget: MonthlyBudget) -> Bool {
        guard budget.status != .notSet else {
            return budget.currency == nil
                && budget.total == nil
                && budget.paymentGroups.isEmpty
                && budget.categories.isEmpty
                && budget.otherCategories == nil
                && budget.dailyAllowance == nil
                && hasWellFormedRemainingDays(budget)
        }
        guard budget.currency != nil,
              let total = budget.total,
              BudgetTotalLine(total) != nil,
              let otherCategories = budget.otherCategories
        else {
            return false
        }
        let groups = budget.paymentGroups.map(\.paymentGroup)
        guard groups.count == 3, Set(groups) == [.creditCard, .cashAndDebit, .accountAndOther] else {
            return false
        }
        let shareLines = [otherCategories] + budget.categories.map(\.line) + budget.paymentGroups.map(\.line)
        guard shareLines.allSatisfy({ BudgetShare(line: $0) != nil }) else {
            return false
        }
        if let daily = budget.dailyAllowance, (daily.amount == nil) != daily.isExceeded {
            return false
        }
        return hasWellFormedRemainingDays(budget)
    }
}

private extension BudgetTabViewModel {
    /// 범위 끝(서버의 이번 달 + 12개월). 서버의 이번 달을 모르면 nil.
    var lastMonth: ServerMonth? {
        serverMonth.map { Self.month(at: Self.index(of: $0) + Self.monthsAfterServerMonth) }
    }

    static func index(of month: ServerMonth) -> Int {
        month.year * 12 + month.month - 1
    }

    static func month(at index: Int) -> ServerMonth {
        ServerMonth(year: index / 12, month: index % 12 + 1)
    }

    /// 남은 일수는 요청한 달이 응답의 이번 달일 때만 있고(v2 :46), 있으면 1 ... 그 달 일수다.
    /// 그 달 일수는 서울 gregorian 으로 센다 — 기기 달력을 쓰지 않는다.
    static func hasWellFormedRemainingDays(_ budget: MonthlyBudget) -> Bool {
        let isCurrentMonth = budget.year == budget.currentYear && budget.month == budget.currentMonth
        guard let days = budget.remainingDaysIncludingToday else {
            return !isCurrentMonth
        }
        let calendar = WoniDateFormat.defaultCalendar
        guard isCurrentMonth,
              let firstDay = calendar.date(from: DateComponents(year: budget.year, month: budget.month, day: 1)),
              let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)?.count
        else {
            return false
        }
        return (1 ... daysInMonth).contains(days)
    }

    /// 작업이 돌 때의 상태로 판정한다 — 그 사이 숨겨졌으면 표시의 작업도 읽지 않는다.
    func reloadIfNeeded(after event: BudgetTabEvent) async {
        switch event {
        case .tabHidden:
            return
        case .tabShown, .foreground, .ledgerChanged, .identityChanged:
            guard isVisible else {
                return
            }
        case .connectivityRestored:
            guard isVisible, case .failed = phase else {
                return
            }
        }
        await reload()
    }

    /// 옛 계정의 상태와 진행 중인 읽기를 버린다. 다음 시작(보이는 중이면 바로, 숨겨져 있으면 다음에 보일 때)은
    /// 서버 시각 확인부터다(스펙 §4.3).
    func reset() {
        readGeneration += 1
        serverMonth = nil
        month = nil
        phase = .loading
    }

    /// 처음이면 서버의 이번 달부터 확인하고, 알면 보던 달을 다시 읽는다. 보던 상태는 응답이 올 때까지 그대로다.
    func reload() async {
        guard hasIdentity() else {
            reset()
            phase = .noIdentity
            return
        }
        if let month {
            await read(month)
            return
        }
        if case .noIdentity = phase {
            phase = .loading
        }
        let generation = beginRead()
        let current: ServerMonth
        do {
            current = try await probeServerMonth()
        } catch {
            if generation == readGeneration {
                phase = .failed
            }
            return
        }
        guard generation == readGeneration else {
            return
        }
        serverMonth = current
        month = current
        await read(current)
    }

    func show(_ target: ServerMonth) async {
        guard let lastMonth,
              (Self.index(of: Self.firstMonth) ... Self.index(of: lastMonth)).contains(Self.index(of: target))
        else {
            return
        }
        month = target
        phase = .loading
        await read(target)
    }

    /// 마지막에 시작한 읽기의 응답만 받아들이고, 받아들인 응답의 이번 달을 서버의 이번 달로 삼는다.
    func read(_ target: ServerMonth) async {
        let generation = beginRead()
        do {
            let budget = try await fetch(target.year, target.month)
            let unsyncedCount = try await unsyncedExpenseCount(target.year, target.month)
            let pendingIDs = try pendingDeletionCategoryIDs()
            guard generation == readGeneration else {
                return
            }
            guard Self.isWellFormed(budget) else {
                phase = .failed
                return
            }
            serverMonth = ServerMonth(year: budget.currentYear, month: budget.currentMonth)
            phase = .loaded(BudgetTabContent(
                budget: budget,
                unsyncedExpenseCount: unsyncedCount,
                pendingDeletionCategoryIDs: pendingIDs
            ))
        } catch {
            if generation == readGeneration {
                phase = .failed
            }
        }
    }

    func beginRead() -> Int {
        readGeneration += 1
        return readGeneration
    }
}
