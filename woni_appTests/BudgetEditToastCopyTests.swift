//
//  BudgetEditToastCopyTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 편집 토스트 문구와 삭제 실패 판정(2026-10-04 사용자 결정 — 삭제 실패 문구 나눔 · en 나눌 금액 · en 긴 토스트 줄임).
/// 서버 쓰기는 늘 실패하는 가짜다. 회원이 2026-10(전체 500,000)을 연 편집 화면에서 저장·삭제한다.
@MainActor
struct BudgetEditToastCopyTests {
    /// 표에 없는 코드·연결 실패 — `BudgetWriteError.other` 와 그 밖의 에러.
    private static let otherFailures: [any Error] = [
        BudgetWriteError.other(ToastCopyTestError.offline),
        ToastCopyTestError.offline
    ]

    @Test("BDF.S1-R1 삭제의 그 밖·연결 실패는 삭제 실패 토스트 — 같은 에러로 저장하면 저장 실패 토스트")
    func deleteOtherFailureShowsDeleteToast() async {
        for failure in Self.otherFailures {
            let deleting = ToastCopyFakes(writeError: failure)
            let viewModel = deleting.makeViewModel()
            viewModel.requestDelete()
            await viewModel.confirmDialog()

            #expect(viewModel.toast == .deleteFailed, "\(failure)")
            #expect(deleting.outcomes.isEmpty, "\(failure)")
            #expect(viewModel.showsDeleteButton, "\(failure)")

            // 짝: 같은 에러로 저장 — 저장 경로는 저장 실패 그대로다.
            let saving = ToastCopyFakes(writeError: failure)
            let saveViewModel = saving.makeViewModel()
            await saveViewModel.save()

            #expect(saveViewModel.toast == .saveFailed, "\(failure)")
            #expect(saving.outcomes.isEmpty, "\(failure)")
        }
    }

    @Test("BDF.S1-R1 삭제가 삭제된 카테고리·범위 밖 달로 거절되면 지금처럼 닫고 다시 불러온다 — 토스트 없음")
    func deleteReloadRejectionsStillReload() async {
        let cases: [(error: BudgetWriteError, reason: BudgetEditReloadReason)] = [
            (.categoryNotFound, .categoryDeletedReloaded),
            (.monthOutOfRange, .monthNotAllowed)
        ]
        for (error, reason) in cases {
            let fakes = ToastCopyFakes(writeError: error)
            let viewModel = fakes.makeViewModel()
            viewModel.requestDelete()
            await viewModel.confirmDialog()

            #expect(viewModel.toast == nil, "\(error)")
            #expect(fakes.reloads == [ToastCopyFakes.Reload(month: fakes.month, reason: reason)], "\(error)")
        }
    }

    @Test("BDF.S1-R2 삭제 실패 문구는 삭제를 말하고 저장 실패 문구와 다르다")
    func deleteFailedCopy() {
        #expect(BudgetEditToast.deleteFailed.message(.ko) == "예산을 삭제하지 못했습니다. 연결을 확인해 주세요.")
        #expect(BudgetEditToast.deleteFailed.message(.en) == "Couldn't delete your budget. Check your connection.")

        // 짝: 저장 실패는 저장 문구다.
        #expect(BudgetEditToast.saveFailed.message(.ko) == "예산을 저장하지 못했습니다. 연결을 확인해 주세요.")
        #expect(BudgetEditToast.saveFailed.message(.en) != BudgetEditToast.deleteFailed.message(.en))
    }

    @Test("BDF.S1-R3 en 저장 실패·새 카테고리 올리기 실패 토스트는 줄인 문구 — ko 는 그대로")
    func shortenedEnglishToasts() {
        #expect(BudgetEditToast.saveFailed.message(.en) == "Couldn't save your budget. Check your connection.")
        #expect(
            BudgetEditToast.categoryUploadFailed.message(.en) == "Couldn't upload the new category. Budget not saved."
        )

        // 짝: ko 두 문구는 바뀌지 않는다.
        #expect(BudgetEditToast.saveFailed.message(.ko) == "예산을 저장하지 못했습니다. 연결을 확인해 주세요.")
        #expect(BudgetEditToast.categoryUploadFailed.message(.ko) == "새 카테고리를 못 올려 예산도 저장하지 못했습니다.")
    }

    @Test("BDF.S1-R4 en 나눌 수 있는 금액은 ko 처럼 라벨 왼쪽·금액 오른쪽으로 나눈다")
    func paymentRemainingSplitsLabelAndAmount() {
        for amountText in ["100,000", "2,500", "0"] {
            let en = WoniStrings.budgetEditPaymentRemaining(amountText, language: .en)
            #expect(en.label == "Left to split", "\(amountText)")
            #expect(en.amount == amountText)

            // 짝: ko 는 ko 라벨에 같은 금액이다.
            let ko = WoniStrings.budgetEditPaymentRemaining(amountText, language: .ko)
            #expect(ko.label == "나눌 수 있는 금액", "\(amountText)")
            #expect(ko.amount == amountText)
        }
    }

    @Test("BDF.S1-R5 나머지 편집 토스트의 ko 문구는 옮기기 전과 같고 서로 다르다")
    func remainingToastsKeepCopy() {
        let cases: [(toast: BudgetEditToast, ko: String)] = [
            (.amountOverLimit, "99,999,999를 넘는 금액은 입력할 수 없습니다."),
            (.noPreviousBudget, "지난 달에 정한 예산이 없습니다."),
            (.previousLoadFailed, "지난 달 예산을 불러오지 못했습니다."),
            (.droppedDeletedCategories(1), "삭제된 카테고리 1개는 빼고 불러왔습니다."),
            (.droppedDeletedCategories(2), "삭제된 카테고리 2개는 빼고 불러왔습니다."),
            (.totalRequired, "전체 예산을 먼저 정해 주세요."),
            (.allocationExceedsTotal, "나눈 금액이 전체보다 많아 저장하지 못했습니다.")
        ]
        for (toast, ko) in cases {
            #expect(toast.message(.ko) == ko, "\(toast)")
        }

        // 짝: 모든 경우가 제 문구를 갖는다 — 여러 경우를 한 문구로 몰면 세는 수가 준다.
        let all = cases.map(\.toast) + [.saveFailed, .deleteFailed, .categoryUploadFailed, .totalLocked]
        #expect(Set(all.map { $0.message(.ko) }).count == all.count)
        #expect(Set(all.map { $0.message(.en) }).count == all.count)
    }
}

extension BudgetEditToastCopyTests {
    @Test("BETR.S0-R8 잠긴 전체 칸 토스트는 UI_GUIDE en 표 2026-10-05 줄과 글자까지 같다")
    func totalLockedCopy() {
        #expect(BudgetEditToast.totalLocked.message(.ko) == "전체는 카테고리 합계입니다. 직접 정하려면 카테고리 금액을 비우세요.")
        #expect(
            BudgetEditToast.totalLocked.message(.en)
                == "Your total is the sum of your categories. Clear the category amounts to set it yourself."
        )
    }
}

private enum ToastCopyTestError: Error {
    case offline
}

/// 저장·삭제가 늘 `writeError` 로 실패하는 편집 화면 조립. 읽기는 부르지 않는다.
@MainActor
private final class ToastCopyFakes {
    struct Reload: Equatable {
        let month: ServerMonth
        let reason: BudgetEditReloadReason
    }

    let month = ServerMonth(year: 2026, month: 10)
    let writeError: any Error
    private(set) var outcomes: [BudgetEditOutcome] = []

    init(writeError: any Error) {
        self.writeError = writeError
    }

    var reloads: [Reload] {
        outcomes.compactMap { outcome in
            guard case let .reloadRequired(month, reason) = outcome else {
                return nil
            }
            return Reload(month: month, reason: reason)
        }
    }

    func makeViewModel() -> BudgetEditViewModel {
        BudgetEditViewModel(
            context: BudgetEditViewModel.Context(
                month: month,
                lastMonth: ServerMonth(year: 2027, month: 10),
                initialBudget: makeBudget(month)
            ),
            chipOrder: { [1] },
            baseCurrency: .krw,
            fetch: { _, _ in throw ToastCopyTestError.offline },
            save: { _, _, _ in throw self.writeError },
            delete: { _, _ in throw self.writeError },
            hasIdentity: { true },
            ensureIdentity: {},
            flushPendingCategories: {},
            resolvedCategoryID: { $0 },
            refreshCategories: {},
            beginWrite: { 1 },
            onFinish: { self.outcomes.append($0) }
        )
    }
}

/// 전체 500,000 만 정한 달. 쓴 돈은 0, 카테고리 몫은 없고 결제수단 세 묶음은 몫이 없다.
@MainActor
private func makeBudget(_ month: ServerMonth) -> MonthlyBudget {
    let total = BudgetLine(
        budgetAmount: 500_000,
        actualAmount: 0,
        status: BudgetStatus.none,
        percent: 0,
        remainingAmount: 500_000,
        overAmount: nil
    )
    let spentNothing = BudgetLine(
        budgetAmount: nil,
        actualAmount: 0,
        status: nil,
        percent: nil,
        remainingAmount: nil,
        overAmount: nil
    )
    let groups: [PaymentGroup] = [.creditCard, .cashAndDebit, .accountAndOther]
    let budget = MonthlyBudget(
        year: month.year,
        month: month.month,
        currentYear: 2026,
        currentMonth: 10,
        remainingDaysIncludingToday: 7,
        hasAnyBudget: true,
        status: BudgetStatus.none,
        currency: .krw,
        total: total,
        paymentGroups: groups.map { BudgetPaymentGroupLine(paymentGroup: $0, line: spentNothing) },
        categories: [],
        otherCategories: total,
        missingRateCount: 0,
        dailyAllowance: nil
    )
    #expect(BudgetTabViewModel.isWellFormed(budget))
    return budget
}
