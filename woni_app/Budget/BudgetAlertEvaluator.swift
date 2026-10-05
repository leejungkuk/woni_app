//
//  BudgetAlertEvaluator.swift
//  woni_app
//

import Foundation

/// 예산 알림창을 언제 판정해 띄울 창으로 내놓는지 정한다. 무엇을 띄울지는 `BudgetAlertDecision` 이 정한다(스펙 §5).
/// 판정은 한 번에 하나만 돈다 — 동시에 돌면 같은 기준을 둘이 읽는다.
/// 달은 서버에서만 온다 — 기기 시계를 읽지 않는다.
/// 판정은 기록하지 않는다 — 창이 뜬 순간 `markShown` 이 기록한다(UI_GUIDE "예산 알림창" 기록).
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
    @ObservationIgnored private var isRunning = false
    /// 판정 중에 온 요청들. 앞 판정이 끝나면 한 번만 더 돌고 함께 돌려보낸다.
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []

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
    func evaluate() async {
        guard !isRunning else {
            await withCheckedContinuation { waiting.append($0) }
            return
        }
        isRunning = true
        await evaluateOnce()
        while !waiting.isEmpty {
            let served = waiting
            waiting = []
            await evaluateOnce()
            served.forEach { $0.resume() }
        }
        isRunning = false
    }

    /// 원장 변경 스트림이 끝날 때까지 신호마다 판정한다 — push·pull 이 원장을 바꾼 뒤다(스펙 :369).
    func observeLedgerChanges(_ events: AsyncStream<Void>) async {
        for await _ in events {
            await evaluate()
        }
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
        records.clear()
        clearPending()
    }

    /// purge 가 재개 표식을 지우기 전에 부른다. 세대를 올려 진행 중인 판정이 비운 기록 위에 창을 내지 않게 하고, 기록과
    /// 기다리던 창을 비운다. 아는 달은 그 뒤의 `reset()` 이 맡는다.
    func clearRecords() {
        resetGeneration += 1
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
    /// 진행률 받음 → 계정 확인 → 띄울 창을 바꾼다(스펙 :358). 기록은 `markShown` 이 한다.
    func evaluateOnce() async {
        let generation = resetGeneration
        guard let userID = currentUserID(),
              let budget = await progress(userID, generation),
              isSameAccount(userID, generation)
        else {
            // 읽지 못한 판정은 기다리던 창을 그대로 둔다.
            return
        }
        knownMonth = ServerMonth(year: budget.currentYear, month: budget.currentMonth)

        let key = { BudgetAlertDecision.recordKey(userID: userID, budget: budget, threshold: $0) }
        // 키를 만들 수 없는 응답(통화·전체 금액 없음)은 decide 가 먼저 거른다.
        let isRecorded = { key($0).map(self.records.contains) ?? true }
        guard let decision = BudgetAlertDecision.decide(budget, isSent: isRecorded) else {
            // 최신 판정에 띄울 것이 없다(기준 아래·이번 달 예산 없음·이미 알림) — 기다리던 창을 버린다.
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
