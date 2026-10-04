//
//  BudgetAlertEvaluator.swift
//  woni_app
//

import Foundation
import UserNotifications

/// 예산 알림을 iOS 에 요청하고 지운다.
protocol BudgetAlertScheduling {
    /// iOS 에 알림을 바로 띄우도록 요청한다. 실패하면 던진다.
    func schedule(identifier: String, body: String) async throws
    /// 그 식별자의 대기 중 요청과 알림 센터에 남은 알림을 지운다.
    func remove(identifier: String)
}

/// iOS 알림 센터 중 예산 알림이 쓰는 부분 — 테스트가 요청 내용을 볼 수 있게 받아 쓴다.
protocol BudgetAlertCenterClient {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: BudgetAlertCenterClient {}

/// `UNUserNotificationCenter` 로 예산 알림을 띄운다.
struct SystemBudgetAlertScheduler: BudgetAlertScheduling {
    private let center: any BudgetAlertCenterClient

    init(center: any BudgetAlertCenterClient = UNUserNotificationCenter.current()) {
        self.center = center
    }

    /// trigger 없이 바로 띄운다.
    func schedule(identifier: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        // 임시 #21 — 제목 없이 본문만
        content.body = body
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func remove(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

/// 예산 알림을 언제 판정해 보내는지 정한다. 무엇을 보낼지는 `BudgetAlertDecision` 이 정한다(스펙 §5).
/// 판정은 한 번에 하나만 돈다 — 동시에 돌면 같은 기준을 둘이 읽어 두 번 보낸다.
/// 달은 서버에서만 온다 — 기기 시계를 읽지 않는다.
@MainActor
final class BudgetAlertEvaluator {
    private let isEnabled: () -> Bool
    private let permission: NotificationPermissionProviding
    private let currentUserID: () -> UUID?
    private let probeServerMonth: () async throws -> ServerMonth
    private let fetch: (_ year: Int, _ month: Int) async throws -> MonthlyBudget
    private let scheduler: BudgetAlertScheduling
    private let records: BudgetAlertRecordStore
    private let language: () -> AppLanguage

    /// 판정에 쓴 응답의 이번 달. 모르면(처음·`reset()` 뒤) nil 이고 서버 시각부터 받는다.
    private var knownMonth: ServerMonth?
    /// `reset()`·`clearRecords()` 마다 올린다. 판정은 시작 때의 값이 그대로일 때만 보내고 기록한다 — purge 는 사용자 ID 가 같다.
    private var generation = 0
    private var isRunning = false
    /// 판정 중에 온 요청들. 앞 판정이 끝나면 한 번만 더 돌고 함께 돌려보낸다.
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(
        isEnabled: @escaping () -> Bool,
        permission: NotificationPermissionProviding,
        currentUserID: @escaping () -> UUID?,
        probeServerMonth: @escaping () async throws -> ServerMonth,
        fetch: @escaping (_ year: Int, _ month: Int) async throws -> MonthlyBudget,
        scheduler: BudgetAlertScheduling,
        records: BudgetAlertRecordStore,
        language: @escaping () -> AppLanguage
    ) {
        self.isEnabled = isEnabled
        self.permission = permission
        self.currentUserID = currentUserID
        self.probeServerMonth = probeServerMonth
        self.fetch = fetch
        self.scheduler = scheduler
        self.records = records
        self.language = language
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

    /// 로그아웃·purge·계정 전환. 기록을 비우고 세대를 올려 진행 중인 판정을 버린다.
    func reset() {
        generation += 1
        knownMonth = nil
        records.clear()
    }

    /// purge 가 재개 표식을 지우기 전에 부른다. 세대를 올려 진행 중인 판정이 비운 기록을 다시 쓰지 않게 하고 기록을
    /// 비운다. 아는 달은 그 뒤의 `reset()` 이 맡는다.
    func clearRecords() {
        generation += 1
        records.clear()
    }
}

private extension BudgetAlertEvaluator {
    /// 진행률 받음 → 계정·앱 알림 설정·iOS 권한 확인 → iOS 에 요청 → 계정을 다시 확인하고 기록(스펙 :358).
    func evaluateOnce() async {
        let generation = generation
        let startUserID = currentUserID()
        guard isEnabled(),
              await isAllowed(),
              let userID = startUserID,
              isSameAccount(userID, generation),
              let budget = await progress(userID, generation),
              await isAllowed(),
              isEnabled(),
              isSameAccount(userID, generation)
        else {
            return
        }
        knownMonth = ServerMonth(year: budget.currentYear, month: budget.currentMonth)

        let key = { BudgetAlertDecision.recordKey(userID: userID, budget: budget, threshold: $0) }
        // 키를 만들 수 없는 응답(통화·전체 금액 없음)은 decide 가 먼저 거른다.
        guard let decision = BudgetAlertDecision.decide(budget, isSent: { key($0).map(records.contains) ?? true }),
              let identifier = key(decision.alert.threshold)
        else {
            return
        }
        do {
            let body = BudgetAlertDecision.body(for: decision.alert, language: language())
            try await scheduler.schedule(identifier: identifier, body: body)
        } catch {
            // 기록하지 않는다 — 다음 판정에서 다시 보낸다.
            return
        }
        guard isSameAccount(userID, generation) else {
            // 앞 계정의 알림이 새 계정 화면에 남지 않게 한다.
            scheduler.remove(identifier: identifier)
            return
        }
        records.insert(decision.record.compactMap(key))
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

    func isAllowed() async -> Bool {
        await permission.authorization() == .allowed
    }

    /// 판정을 시작할 때의 계정 그대로인가 — 사용자 ID 와 세대(`reset()`·`clearRecords()`) 둘 다.
    func isSameAccount(_ userID: UUID, _ generation: Int) -> Bool {
        generation == self.generation && currentUserID() == userID
    }
}
