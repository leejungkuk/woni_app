enum WoniStrings {
    static func income(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "수입"
        case .en: "Income"
        }
    }

    static func expense(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "지출"
        case .en: "Expense"
        }
    }

    static func total(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "합계"
        case .en: "Total"
        }
    }

    static func conversionWarning(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "선택한 기본 통화로 환산할 수 없는 거래는 집계에서 제외했습니다."
        case .en: "Entries that cannot be converted to the selected base currency are excluded from totals."
        }
    }

    static func uncategorized(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "미분류"
        case .en: "Uncategorized"
        }
    }

    static func unassigned(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "미지정"
        case .en: "Unassigned"
        }
    }

    static func save(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "저장"
        case .en: "Save"
        }
    }

    static func tabExpense(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "지출"
        case .en: "Expense"
        }
    }

    static func tabIncome(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "수입"
        case .en: "Income"
        }
    }

    static func memoFieldTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "메모"
        case .en: "MEMO"
        }
    }

    static func memoPlaceholder(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "어디에 사용했는지 적어주세요."
        case .en: "Write down where you used it."
        }
    }

    static func category(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "카테고리"
        case .en: "CATEGORY"
        }
    }

    static func asset(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "자산"
        case .en: "PROPERTY"
        }
    }

    static func retry(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "다시 시도"
        case .en: "Retry"
        }
    }

    static func settingsTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "설정"
        case .en: "Setting"
        }
    }

    static func baseCurrency(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "기본 통화"
        case .en: "Main Currency"
        }
    }

    static func languageRow(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "언어 설정"
        case .en: "Language"
        }
    }

    static func myInfo(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "내 정보"
        case .en: "My Info"
        }
    }

    static func languageKorean(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "한국어"
        case .en: "Korean"
        }
    }

    static func languageEnglish(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "영어"
        case .en: "English"
        }
    }

    static func loginSignup(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그인/회원가입"
        case .en: "Sign In / Sign Up"
        }
    }

    static func appVersion(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "앱 버전"
        case .en: "App Version"
        }
    }

    static func support(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "고객센터"
        case .en: "Customer Service"
        }
    }

    static func terms(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "서비스 약관"
        case .en: "Terms of Service"
        }
    }

    static func privacy(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "개인정보 보호정책"
        case .en: "Privacy Policy"
        }
    }

    static func confirmOK(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "확인"
        case .en: "OK"
        }
    }

    static func appStartFailedTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "앱을 시작할 수 없습니다."
        case .en: "Unable to start the app."
        }
    }

    static func ratePreviewStale(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "기준일 다름"
        case .en: "Different rate date"
        }
    }

    static func ratePreviewStale(_ language: AppLanguage, baseDate: String) -> String {
        switch language {
        case .ko: "기준일 \(baseDate)"
        case .en: "Rate date \(baseDate)"
        }
    }

    static func rateEstimated(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "추정 환율"
        case .en: "Estimated rate"
        }
    }

    static func addTransactionA11y(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "거래 추가"
        case .en: "Add transaction"
        }
    }

    static func settingsA11y(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "설정"
        case .en: "Settings"
        }
    }

    static func loginSheetTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그인 / 회원가입"
        case .en: "Sign In / Sign Up"
        }
    }

    static func loginSheetSubtitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "데이터 동기화와 기기 이전을 위해 로그인할 수 있어요"
        case .en: "Sign in to sync your data and move to a new device."
        }
    }

    /// 소셜로그인이 곧 이용계약 체결이므로(약관 제4조 1항) 동의 대상 문서를 로그인 시점에 알린다.
    static func loginConsentNotice(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그인하면 아래 문서에 동의한 것으로 봅니다"
        case .en: "By signing in, you agree to the documents below."
        }
    }

    static func loginGoogle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "Google로 계속하기"
        case .en: "Continue with Google"
        }
    }
}

extension WoniStrings {
    static func loginApple(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "Apple로 계속하기"
        case .en: "Continue with Apple"
        }
    }

    static func cancel(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "취소"
        case .en: "Cancel"
        }
    }

    /// 아이콘만 있는 버튼의 접근성 레이블. 지정하지 않으면 OS가 SF Symbol 이름에서 자동 생성하는데,
    /// 그 문구는 앱 언어 설정이 아니라 **기기 언어**를 따라 VoiceOver가 다른 언어로 읽는다.
    static func back(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "뒤로"
        case .en: "Back"
        }
    }

    static func previousDay(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "이전 날짜"
        case .en: "Previous day"
        }
    }

    static func previousMonth(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "이전 달"
        case .en: "Previous month"
        }
    }

    static func nextDay(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "다음 날짜"
        case .en: "Next day"
        }
    }

    static func nextMonth(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "다음 달"
        case .en: "Next month"
        }
    }

    static func loginFailedTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그인할 수 없습니다."
        case .en: "Unable to sign in."
        }
    }

    static func loginFailedMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "잠시 후 다시 시도해 주세요."
        case .en: "Please try again later."
        }
    }

    static func loginOfflineMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "네트워크 연결 후 다시 시도해 주세요."
        case .en: "Check your network connection and try again."
        }
    }

    static func restoreFailedTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그인은 완료됐습니다."
        case .en: "Sign-in is complete."
        }
    }

    static func restoreFailedMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "기존 데이터를 복원하지 못했습니다. 다시 시도해 주세요."
        case .en: "We couldn't restore your existing data. Please try again."
        }
    }

    static func close(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "닫기"
        case .en: "Close"
        }
    }

    static func logout(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그아웃"
        case .en: "Sign Out"
        }
    }

    static func logoutSyncing(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "동기화 중"
        case .en: "Syncing"
        }
    }

    static func unsyncedLogoutTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "미동기 항목이 있습니다"
        case .en: "You have unsynced entries"
        }
    }

    static func unsyncedLogoutMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "강행하면 이 기기의 미동기 항목이 삭제됩니다."
        case .en: "Continuing will delete unsynced entries from this device."
        }
    }

    static func forceLogout(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "강행"
        case .en: "Continue"
        }
    }

    static func logoutFailedTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그아웃할 수 없습니다."
        case .en: "Unable to sign out."
        }
    }

    static func logoutFailedMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로컬 데이터는 임의로 삭제하지 않았습니다. 잠시 후 다시 시도해 주세요."
        case .en: "Local data was not deleted unexpectedly. Please try again later."
        }
    }

    static func logoutCleanupRequiredTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그아웃을 완료해야 합니다"
        case .en: "Finish signing out"
        }
    }

    static func logoutCleanupRequiredMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그아웃은 됐지만 이 기기의 로컬 데이터 정리에 실패했습니다. 다시 시도해 정리를 완료해 주세요."
        case .en: "You are signed out, but clearing this device's local data failed. Retry to finish."
        }
    }

    static func remoteLogoutTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "세션이 종료되었습니다."
        case .en: "Your session has ended."
        }
    }

    static func remoteLogoutMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "세션이 만료되었거나 다른 기기에서 로그인되었습니다. 다시 로그인해 주세요."
        case .en: "Your session expired or another device signed in. Please sign in again."
        }
    }
}

extension WoniStrings {
    static func weekdaysShort(_ language: AppLanguage) -> [String] {
        switch language {
        case .ko: ["일", "월", "화", "수", "목", "금", "토"]
        case .en: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        }
    }

    static func pickerCancel(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "취소"
        case .en: "Cancel"
        }
    }

    static func pickerSave(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "저장"
        case .en: "Save"
        }
    }

    static func yearSuffix(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "년"
        case .en: ""
        }
    }

    static func monthSuffix(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "월"
        case .en: ""
        }
    }

    static func errMissingSelection(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "저장하기 전에 카테고리와 자산을 선택하세요."
        case .en: "Select a category and asset before saving."
        }
    }

    static func errInvalidAmount(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "금액은 0보다 크고 99,999,999 이하, 선택한 통화에서 허용하는 소수 자릿수까지만 가능합니다."
        case .en:
            "Amount must be greater than 0, at most 99,999,999, "
                + "and within the decimal places allowed for the selected currency."
        }
    }

    static func errMemoTooLong(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "메모는 255자 이하여야 합니다."
        case .en: "Memo must be 255 characters or fewer."
        }
    }

    static func errFutureDate(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "거래일은 1년 이후 날짜를 입력할 수 없습니다."
        case .en: "You can't enter a date more than a year ahead."
        }
    }

    static func editEntryTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "수정"
        case .en: "Edit"
        }
    }

    static func deleteEntry(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제"
        case .en: "Delete"
        }
    }

    static func deleteConfirmationTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "정말 삭제하시겠습니까?"
        case .en: "Delete this entry?"
        }
    }

    static func deleteConfirmationMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제된 데이터는 복구할 수 없습니다."
        case .en: "Deleted data cannot be recovered."
        }
    }

    static func deleteConfirmationDelete(_ language: AppLanguage) -> String {
        deleteEntry(language)
    }

    static func deleteConfirmationCancel(_ language: AppLanguage) -> String {
        cancel(language)
    }

    static func transactionNotFoundTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "항목을 찾을 수 없습니다."
        case .en: "Entry not found."
        }
    }

    static func transactionNotFoundMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "항목이 삭제되었거나 더 이상 존재하지 않습니다. 목록으로 돌아갑니다."
        case .en: "This entry was deleted or no longer exists. Return to the list."
        }
    }

    static func deleteFailedTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제할 수 없습니다."
        case .en: "Unable to delete entry."
        }
    }

    static func deleteFailedMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "항목을 삭제하지 못했습니다. 다시 시도해 주세요."
        case .en: "We couldn't delete this entry. Please try again."
        }
    }

    /// 달력에서 오늘 날짜임을 VoiceOver로 알리는 접근성 값.
    static func today(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "오늘"
        case .en: "Today"
        }
    }

    /// 내역 1건 삭제 완료 토스트(홈).
    static func entryDeletedToast(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제되었습니다."
        case .en: "Deleted."
        }
    }

    /// 금액 상한 초과 안내 토스트. 상한 표기는 검증 기준(AddExpenseViewModel.maximumAmount)에서
    /// 파생한 값을 호출부가 넘겨, 문구와 검증 기준이 어긋나지 않는다.
    static func amountOverLimitToast(_ language: AppLanguage, limit: String) -> String {
        switch language {
        case .ko: "\(limit)를 넘는 금액은 입력할 수 없습니다."
        case .en: "You can't enter an amount over \(limit)."
        }
    }
}
