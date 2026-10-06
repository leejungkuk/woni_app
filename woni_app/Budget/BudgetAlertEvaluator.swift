//
//  BudgetAlertEvaluator.swift
//  woni_app
//

import Foundation

/// 판정을 부른 때. 이번 달 예산이 없다고 확인된 동안 원장 변경은 서버를 부르지 않는다(UI_GUIDE "예산 알림창").
enum BudgetAlertTrigger: Equatable {
    /// 원장 변경(push·pull 뒤).
    case ledgerChange
    /// 앱이 앞으로 옴.
    case foreground
}

/// 예산 편집이 쓰기 직전에 받아 두는 표 — 그때의 사용자 ID 와 세대. 밖에서는 비교만 한다.
struct BudgetAlertSaveToken: Equatable {
    fileprivate let userID: UUID?
    fileprivate let generation: Int
}

/// 예산 알림창을 언제 판정해 띄울 창으로 내놓는지 정한다. 무엇을 띄울지는 `BudgetAlertDecision` 이 정한다(스펙 §5).
/// 판정은 한 번에 하나만 돈다 — 동시에 돌면 같은 기준을 둘이 읽는다.
/// 달은 서버에서만 온다 — 기기 시계를 읽지 않는다.
/// 판정은 기록하지 않는다 — 창이 뜬 순간 `markShown` 이 기록한다(UI_GUIDE "예산 알림창" 기록).
/// 이 기기가 처음 확인한 예산이 이미 넘었으면 창 없이 알린 것으로 남긴다(UI_GUIDE "넘는 걸 본 기기만 띄운다").
@MainActor
@Observable
final class BudgetAlertEvaluator {
    /// 띄울 창. 루트가 띄울 수 있을 때 `markShown` 을 부르고 띄운다(UI_GUIDE "띄우는 때").
    /// 새 판정이 오면 최신 것만 남는다 — 띄울 것이 없는 판정은 비우고, 읽지 못한 판정은 그대로 둔다.
    private(set) var pendingAlert: BudgetAlert?
    /// `reset()`·`clearRecords()` 마다 오른다. 판정은 시작 때의 값이 그대로일 때만 창을 낸다 — purge 는 사용자 ID 가 같다.
    /// 루트가 이 값이 바뀌면 떠 있는 알림창을 닫는다(purge 는 신원 세대를 안 올린다).
    private(set) var resetGeneration = 0

    private let currentUserID: () -> UUID?
    private let probeServerMonth: () async throws -> ServerMonth
    private let fetch: (_ year: Int, _ month: Int) async throws -> MonthlyBudget
    private let records: BudgetAlertRecordStore

    /// `pendingAlert` 를 낸 판정의 계정·세대와 창을 띄우면 기록할 키. `pendingAlert` 와 함께 바뀐다.
    @ObservationIgnored private var pendingRecord: PendingAlertRecord?
    /// 판정에 쓴 응답의 이번 달. 모르면(처음·`reset()` 뒤) nil 이고 서버 시각부터 받는다.
    @ObservationIgnored private var knownMonth: ServerMonth?
    /// 이번 달 예산이 없다고 확인했다. 그동안 원장 변경 판정은 서버를 부르지 않는다 — foreground 판정의 결과·예산이 있는
    /// 저장 응답·`reset()`·`clearRecords()` 가 다시 정한다(UI_GUIDE "이번 달 예산이 없다고 확인되면").
    @ObservationIgnored private var knowsNoBudget = false
    /// 받아들인 저장 응답 수. 판정은 시작 때의 값이 그대로일 때만 결과를 남긴다(가정 — 저장 전에 시작한 판정은 버린다).
    @ObservationIgnored private var savedResponseCount = 0
    @ObservationIgnored private var isRunning = false
    /// 판정 중에 온 요청들. 앞 판정이 끝나면 한 번만 더 돌고 함께 돌려보낸다.
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []
    /// 기다리는 요청 중에 foreground 가 있다. 뒤따르는 판정은 foreground 로 돈다.
    @ObservationIgnored private var waitingForForeground = false

    init(
        currentUserID: @escaping () -> UUID?,
        probeServerMonth: @escaping () async throws -> ServerMonth,
        fetch: @escaping (_ year: Int, _ month: Int) async throws -> MonthlyBudget,
        records: BudgetAlertRecordStore
    ) {
        self.currentUserID = currentUserID
        self.probeServerMonth = probeServerMonth
        self.fetch = fetch
        self.records = records
    }

    /// 판정을 한 번 요청한다. 돌고 있으면 끝난 뒤 한 번 더 돈다. 돌아올 때는 그 판정(과 뒤따른 판정)이 끝나 있다.
    func evaluate(_ trigger: BudgetAlertTrigger) async {
        guard !isRunning else {
            if trigger == .foreground {
                waitingForForeground = true
            }
            await withCheckedContinuation { waiting.append($0) }
            return
        }
        isRunning = true
        await evaluateOnce(trigger)
        while !waiting.isEmpty {
            let served = waiting
            let next: BudgetAlertTrigger = waitingForForeground ? .foreground : .ledgerChange
            waiting = []
            waitingForForeground = false
            await evaluateOnce(next)
            served.forEach { $0.resume() }
        }
        isRunning = false
    }

    /// 원장 변경 스트림이 끝날 때까지 신호마다 판정한다 — push·pull 이 원장을 바꾼 뒤다(스펙 :369).
    func observeLedgerChanges(_ events: AsyncStream<Void>) async {
        for await _ in events {
            await evaluate(.ledgerChange)
        }
    }

    /// 예산 편집이 쓰기 직전에 받아 두는 표(지금 사용자 ID + 세대).
    func savedBudgetToken() -> BudgetAlertSaveToken {
        BudgetAlertSaveToken(userID: currentUserID(), generation: resetGeneration)
    }

    /// 이 기기의 예산 저장·삭제 응답 — 서버를 부르지 않는 판정이다(UI_GUIDE "이 기기의 예산 저장·삭제 응답도 확인으로
    /// 친다"). 표가 신원 없이 받았거나 지금 사용자·세대와 다르면(편집 중 계정이 바뀜), 응답이 계약에 어긋나거나 응답의
    /// 이번 달이 아니면 아무것도 하지 않는다. 받아들이면 그 전에 시작한 판정의 결과는 버린다(가정).
    func observeSavedBudget(_ budget: MonthlyBudget, token: BudgetAlertSaveToken) {
        guard let userID = token.userID,
              token == savedBudgetToken(),
              BudgetTabViewModel.isWellFormed(budget),
              budget.year == budget.currentYear,
              budget.month == budget.currentMonth
        else {
            return
        }
        savedResponseCount += 1
        judge(budget, userID: userID, generation: token.generation)
    }

    /// 창이 뜬 순간. 지금 `pendingAlert` 와 같고 계정·세대가 판정 때와 같으면 기록하고 비우고 true.
    /// 창이 다르면 아무것도 하지 않고 false. 계정·세대가 바뀌었으면 기록 없이 창을 비우고 false.
    @discardableResult
    func markShown(_ alert: BudgetAlert) -> Bool {
        guard let pendingAlert, pendingAlert == alert, let pendingRecord else {
            return false
        }
        clearPending()
        guard isSameAccount(pendingRecord.userID, pendingRecord.generation) else {
            return false
        }
        records.insert(pendingRecord.keys)
        return true
    }

    /// 로그아웃·purge·계정 전환. 기록과 기다리던 창을 비우고 세대를 올려 진행 중인 판정을 버린다.
    func reset() {
        resetGeneration += 1
        knownMonth = nil
        knowsNoBudget = false
        records.clear()
        clearPending()
    }

    /// purge 가 재개 표식을 지우기 전에 부른다. 세대를 올려 진행 중인 판정이 비운 기록 위에 창을 내지 않게 하고, 기록과
    /// 기다리던 창을 비운다. 아는 달은 그 뒤의 `reset()` 이 맡는다.
    func clearRecords() {
        resetGeneration += 1
        knowsNoBudget = false
        records.clear()
        clearPending()
    }
}

/// 기다리는 창을 낸 판정의 계정·세대와, 창을 띄우면 기록할 키(`BudgetAlertDecision.decide` 의 `record`).
private struct PendingAlertRecord {
    let userID: UUID
    let generation: Int
    let keys: [String]
}

private extension BudgetAlertEvaluator {
    /// 진행률 받음 → 계정·저장 응답 확인 → 판정(스펙 :358). 기록은 `markShown` 이 한다.
    func evaluateOnce(_ trigger: BudgetAlertTrigger) async {
        // 이번 달 예산이 없다고 확인된 동안 원장 변경은 서버를 부르지 않는다 — 기다리던 창도 그대로다(가정).
        guard trigger == .foreground || !knowsNoBudget else {
            return
        }
        let generation = resetGeneration
        let savedResponses = savedResponseCount
        guard let userID = currentUserID(),
              let budget = await progress(userID, generation),
              isSameAccount(userID, generation),
              savedResponses == savedResponseCount
        else {
            // 읽지 못한 판정·저장 응답보다 먼저 시작한 판정은 아무것도 바꾸지 않는다 — 기다리던 창도 그대로다.
            return
        }
        judge(budget, userID: userID, generation: generation)
    }

    /// 응답의 이번 달 예산 하나로 아는 달·예산 없음 기억·확인 표시·띄울 창을 정한다(UI_GUIDE "넘는 걸 본 기기만 띄운다").
    func judge(_ budget: MonthlyBudget, userID: UUID, generation: Int) {
        knownMonth = ServerMonth(year: budget.currentYear, month: budget.currentMonth)
        knowsNoBudget = budget.status == .notSet
        guard budget.status != .notSet,
              let confirmationKey = BudgetAlertDecision.confirmationKey(userID: userID, budget: budget)
        else {
            // 이번 달 예산 없음·키를 만들 수 없는 응답(통화·전체 금액 없음) — 확인 표시 없이 기다리던 창을 버린다.
            clearPending()
            return
        }
        let key = { BudgetAlertDecision.recordKey(userID: userID, budget: budget, threshold: $0) }
        guard records.contains(confirmationKey) else {
            // 이 기기가 처음 확인한 예산 — 이미 넘은 기준은 창 없이 알린 것으로 남기고 기다리던 창을 버린다.
            let passed = BudgetAlertDecision.decide(budget, isSent: { _ in false })?.record ?? []
            records.insert(passed.compactMap(key) + [confirmationKey])
            clearPending()
            return
        }
        let isRecorded = { key($0).map(self.records.contains) ?? true }
        guard let decision = BudgetAlertDecision.decide(budget, isSent: isRecorded) else {
            // 최신 판정에 띄울 것이 없다(기준 아래·이미 알림) — 기다리던 창을 버린다.
            clearPending()
            return
        }
        pendingAlert = decision.alert
        pendingRecord = PendingAlertRecord(
            userID: userID,
            generation: generation,
            keys: decision.record.compactMap(key)
        )
    }

    func clearPending() {
        pendingAlert = nil
        pendingRecord = nil
    }

    /// 아는 달로 읽고, 응답의 이번 달이 다르면 그 달로 한 번만 더 읽는다(스펙 :366). 첫 응답은 이번 달을 알아내는 데만
    /// 쓴다. 받지 못했거나, 다시 읽어도 달이 다르거나, 계약(`BudgetTabViewModel.isWellFormed`)에 어긋나면 nil.
    func progress(_ userID: UUID, _ generation: Int) async -> MonthlyBudget? {
        let month: ServerMonth
        if let knownMonth {
            month = knownMonth
        } else {
            guard let probed = try? await probeServerMonth(), isSameAccount(userID, generation) else {
                return nil
            }
            month = probed
        }
        guard var budget = try? await fetch(month.year, month.month), isSameAccount(userID, generation) else {
            return nil
        }
        let current = ServerMonth(year: budget.currentYear, month: budget.currentMonth)
        if current != month {
            guard let reread = try? await fetch(current.year, current.month),
                  isSameAccount(userID, generation),
                  reread.currentYear == current.year,
                  reread.currentMonth == current.month
            else {
                return nil
            }
            budget = reread
        }
        return BudgetTabViewModel.isWellFormed(budget) ? budget : nil
    }

    /// 판정을 시작할 때의 계정 그대로인가 — 사용자 ID 와 세대(`reset()`·`clearRecords()`) 둘 다.
    func isSameAccount(_ userID: UUID, _ generation: Int) -> Bool {
        generation == resetGeneration && currentUserID() == userID
    }
}
