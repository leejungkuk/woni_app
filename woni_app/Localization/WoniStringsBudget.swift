//
//  WoniStringsBudget.swift
//  woni_app
//

import Foundation

/// 예산 탭 총액 카드 문구(UI_GUIDE "월 예산 화면"·en 표).
extension WoniStrings {
    static func budgetHeroLabel(isOver: Bool, language: AppLanguage) -> String {
        switch (language, isOver) {
        case (.ko, false): "남은 돈"
        case (.ko, true): "넘은 돈"
        case (.en, false): "Remaining"
        case (.en, true): "Over by"
        }
    }

    static func budgetStatusNothingSpent(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "아직 쓰지 않았습니다"
        case .en: "Nothing spent yet"
        }
    }

    static func budgetStatusPercentUsed(_ percent: Int, language: AppLanguage) -> String {
        switch language {
        case .ko: "\(percent)% 썼습니다"
        case .en: "\(percent)% used"
        }
    }

    static func budgetStatusUsedUp(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산을 다 썼습니다"
        case .en: "Budget used up"
        }
    }

    static func budgetStatusOver(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산을 넘었습니다"
        case .en: "Over budget"
        }
    }

    static func budgetDailyAllowance(days: Int, amountText: String, language: AppLanguage) -> String {
        switch language {
        case .ko: "남은 \(days)일, 하루 \(amountText)씩 쓸 수 있습니다"
        case .en: "\(budgetDaysLeft(days)) · \(amountText) a day"
        }
    }

    static func budgetDailyNothingLeft(days: Int, language: AppLanguage) -> String {
        switch language {
        case .ko: "남은 \(days)일, 더 쓸 수 있는 돈이 없습니다"
        case .en: "\(budgetDaysLeft(days)) · nothing remaining"
        }
    }

    static func budgetTodayMarkerInfo(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "▼는 이번 달 중 오늘의 자리입니다. 막대가 ▼를 넘었다면 예산을 고르게 나눠 쓸 때보다 많이 쓴 것입니다."
        case .en: "▼ marks today in this month. If the bar has passed ▼, you're spending faster than an even pace."
        }
    }

    static func budgetUnsyncedExcluded(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .ko: "동기화 전 거래 \(count)건은 아직 빠져 있습니다."
        case .en: count == 1 ? "1 unsynced entry isn't included yet." : "\(count) unsynced entries aren't included yet."
        }
    }

    static func budgetMissingRateExcluded(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .ko: "환율이 없는 거래 \(count)건은 빠져 있습니다."
        case .en: count == 1
            ? "1 entry without an exchange rate isn't included."
            : "\(count) entries without an exchange rate aren't included."
        }
    }

    private static func budgetDaysLeft(_ days: Int) -> String {
        days == 1 ? "1 day left" : "\(days) days left"
    }
}

/// 예산 탭 카테고리·결제수단 카드 문구(UI_GUIDE "월 예산 화면"·en 표).
extension WoniStrings {
    static func budgetCategoryCardTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "카테고리"
        case .en: "Categories"
        }
    }

    static func budgetPaymentCardTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "결제수단"
        case .en: "Payment Methods"
        }
    }

    static func budgetOtherCategories(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "그 외 카테고리"
        case .en: "Other categories"
        }
    }

    static func budgetDeletedCategory(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제된 카테고리"
        case .en: "Deleted category"
        }
    }

    static func budgetPendingDeletion(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제 대기"
        case .en: "Pending deletion"
        }
    }

    /// 넘은 줄의 막대 아래 문구. 통화 글자를 붙이지 않는다.
    static func budgetOverAmount(_ amountText: String, language: AppLanguage) -> String {
        switch language {
        case .ko: "\(amountText) 넘었습니다"
        case .en: "\(amountText) over"
        }
    }

    /// 결제수단 3묶음 이름(스펙 §2.1 · UI_GUIDE en 표).
    static func budgetPaymentGroupName(_ group: PaymentGroup, language: AppLanguage) -> String {
        switch (language, group) {
        case (.ko, .creditCard): "신용카드"
        case (.ko, .cashAndDebit): "현금·체크카드"
        case (.ko, .accountAndOther): "계좌·수표·기타"
        case (.en, .creditCard): "Credit Card"
        case (.en, .cashAndDebit): "Cash · Debit Card"
        case (.en, .accountAndOther): "Account · Check · Other"
        }
    }
}

/// 예산 탭 화면 문구 — 헤더 `수정` · 메시지 카드(UI_GUIDE "월 예산 화면"·en 표).
extension WoniStrings {
    static func budgetEdit(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "수정"
        case .en: "Edit"
        }
    }

    static func budgetNotSetMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산을 정하면 남은 돈을 보여 드립니다."
        case .en: "Set a budget to see what's left."
        }
    }

    static func budgetSetBudget(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산 정하기"
        case .en: "Set Budget"
        }
    }

    static func budgetLoadFailed(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산을 불러올 수 없습니다. 연결되면 다시 보여 드립니다."
        case .en: "Couldn't load your budget. It'll show up when you're back online."
        }
    }
}

/// 예산 탭 위 토스트 — 편집이 끝난 뒤와 비회원의 서버 시각 확인 실패(UI_GUIDE "편집 화면"·"확인·실패 문구"·en 표).
/// 성공(저장·삭제)만 체크 아이콘이다.
extension WoniStrings {
    static func budgetSavedToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산이 저장되었습니다."
        case .en: "Budget saved."
        }
    }

    static func budgetDeletedToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산이 삭제되었습니다."
        case .en: "Budget deleted."
        }
    }

    static func budgetCategoryDeletedReloadedToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제된 카테고리가 있어 예산을 다시 불러왔습니다."
        case .en: "A category was deleted, so your budget was reloaded."
        }
    }

    static func budgetMonthNotAllowedToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "이 달의 예산은 정할 수 없습니다."
        case .en: "You can't set a budget for this month."
        }
    }

    /// 편집 화면의 `budgetEditMonthLoadFailed`("이 달 예산을…")와 다른 문구다.
    static func budgetServerMonthFailedToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산을 불러올 수 없습니다. 연결을 확인해 주세요."
        case .en: "Couldn't load your budget. Check your network connection and try again."
        }
    }
}

/// 예산 편집 화면 문구(UI_GUIDE "편집 화면"·en 표).
extension WoniStrings {
    static func budgetEditTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산"
        case .en: "Budget"
        }
    }

    /// 몫이 없는 줄의 자리표시이자 빈칸을 VoiceOver 가 읽는 말.
    static func budgetNoBudget(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산 없음"
        case .en: "No budget"
        }
    }

    static func budgetEditTotalHint(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "전체 금액만 정해도 되고, 아래에서 카테고리별로 정하면 자동으로 합쳐집니다."
        case .en: "Set just a total, or set amounts by category below and they'll add up automatically."
        }
    }

    static func budgetEditCategorySum(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "카테고리 합계"
        case .en: "Sum of categories"
        }
    }

    /// 금액 칸 아래 그 달 사용액 줄.
    static func budgetEditSpent(month: Int, amountText: String, language: AppLanguage) -> String {
        switch language {
        case .ko: "\(month)월에 쓴 돈 \(amountText)"
        case .en: "Spent in \(WoniDateFormat.monthName(month: month)): \(amountText)"
        }
    }

    static func budgetEditLoadPrevious(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "지난 달 예산 불러오기"
        case .en: "Copy Last Month's Budget"
        }
    }

    static func budgetEditCategoryHint(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "정한 금액은 전체에 더해집니다."
        case .en: "Amounts here add up to your total."
        }
    }

    static func budgetEditSplitByPayment(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "+ 결제수단별 예산 나누기"
        case .en: "+ Split by Payment Method"
        }
    }

    static func budgetEditPaymentHint(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "전체 금액을 카드·현금·계좌로 나눌 수 있습니다."
        case .en: "Split your total across card, cash, and account."
        }
    }

    /// "나눌 수 있는 금액" 줄. ko 는 라벨 왼쪽·금액 오른쪽(시안 ⑪ — 임시 결정 #37), en 은 UI_GUIDE 표 그대로 한 문장이라 `amount` 가 nil 이다.
    static func budgetEditPaymentRemaining(
        _ amountText: String,
        language: AppLanguage
    ) -> (label: String, amount: String?) {
        switch language {
        case .ko: ("나눌 수 있는 금액", amountText)
        case .en: ("\(amountText) left to split", nil)
        }
    }

    /// 입력 중인 결제수단 칸 아래.
    static func budgetEditPaymentMaximum(_ amountText: String, language: AppLanguage) -> String {
        switch language {
        case .ko: "최대 \(amountText)"
        case .en: "Up to \(amountText)"
        }
    }

    static func budgetEditPaymentExcess(_ amountText: String, language: AppLanguage) -> String {
        switch language {
        case .ko: "결제수단 합이 전체보다 \(amountText) 많습니다. 줄여야 저장할 수 있습니다."
        case .en: "Payment methods exceed the total by \(amountText). Reduce them to save."
        }
    }

    static func budgetEditDeleteMonth(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "이 달 예산 삭제"
        case .en: "Delete This Month's Budget"
        }
    }

    static func budgetEditMonthLoadFailed(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "이 달 예산을 불러올 수 없습니다. 연결을 확인해 주세요."
        case .en: "Couldn't load this month's budget. Check your network connection and try again."
        }
    }
}

/// 예산 편집 화면 확인 창 문구(시안 ⑯). 취소는 `WoniStrings.cancel`, 삭제는 `deleteConfirmationDelete` 를 쓴다.
extension WoniStrings {
    static func budgetEditChangeCurrencyTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "통화를 바꿀까요?"
        case .en: "Change currency?"
        }
    }

    static func budgetEditChangeCurrencyMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "입력한 금액이 모두 지워집니다."
        case .en: "All amounts you entered will be cleared."
        }
    }

    static func budgetEditReplaceWithPreviousTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "입력한 금액을 지난 달 값으로 바꿀까요?"
        case .en: "Replace what you entered with last month's amounts?"
        }
    }

    /// 통화 변경·불러오기 확인 버튼.
    static func budgetEditChange(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "바꾸기"
        case .en: "Change"
        }
    }

    static func budgetEditDeleteDialogTitle(month: Int, language: AppLanguage) -> String {
        switch language {
        case .ko: "\(month)월 예산을 삭제할까요?"
        case .en: "Delete your \(WoniDateFormat.monthName(month: month)) budget?"
        }
    }

    static func budgetEditDeleteDialogMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "이 달은 예산이 없는 상태가 됩니다. 되돌릴 수 없습니다."
        case .en: "This month will have no budget. This can't be undone."
        }
    }

    static func budgetEditLeaveTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "저장하지 않고 나갈까요?"
        case .en: "Leave without saving?"
        }
    }

    static func budgetEditLeaveMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "바꾼 금액은 저장되지 않습니다."
        case .en: "Your changes won't be saved."
        }
    }

    static func budgetEditLeave(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "나가기"
        case .en: "Leave"
        }
    }
}

/// 예산 편집 화면 토스트 문구 — 안내·실패라 체크 아이콘이 없다. 금액 상한은 `amountOverLimitToast` 를 쓴다.
extension WoniStrings {
    static func budgetEditTotalBelowCategorySum(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "카테고리 합계보다 작게 정할 수 없습니다."
        case .en: "The total can't be less than the sum of categories."
        }
    }

    static func budgetEditNoPreviousBudget(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "지난 달에 정한 예산이 없습니다."
        case .en: "No budget was set last month."
        }
    }

    static func budgetEditPreviousLoadFailed(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "지난 달 예산을 불러오지 못했습니다."
        case .en: "Couldn't copy last month's budget."
        }
    }

    static func budgetEditDroppedDeletedCategories(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제된 카테고리 \(count)개는 빼고 불러왔습니다."
        case .en: count == 1 ? "Copied without 1 deleted category." : "Copied without \(count) deleted categories."
        }
    }

    static func budgetEditSaveFailed(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "예산을 저장하지 못했습니다. 연결을 확인해 주세요."
        case .en: "Couldn't save your budget. Check your network connection and try again."
        }
    }

    static func budgetEditCategoryUploadFailed(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "새 카테고리를 못 올려 예산도 저장하지 못했습니다."
        case .en: "Couldn't upload your new category, so your budget wasn't saved."
        }
    }

    static func budgetEditTotalRequired(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "전체 예산을 먼저 정해 주세요."
        case .en: "Set a total budget first."
        }
    }

    static func budgetEditAllocationExceedsTotal(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "나눈 금액이 전체보다 많아 저장하지 못했습니다."
        case .en: "Couldn't save because the split exceeds the total."
        }
    }
}
