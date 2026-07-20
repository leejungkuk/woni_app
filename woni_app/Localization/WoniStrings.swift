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
        case .ko: "환율이 없는 외화 거래는 합계에서 제외됐습니다."
        case .en: "Foreign entries without rates are excluded from totals."
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

    static func memoFallback(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "메모"
        case .en: "Memo"
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

    static func supportPending(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "고객센터 연결은 준비 중입니다."
        case .en: "Customer service is not available yet."
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

    static func identityAnonymous(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "익명"
        case .en: "Anonymous"
        }
    }

    static func identitySignedIn(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그인"
        case .en: "Signed In"
        }
    }

    static func identityConflictTitle(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "이미 가입된 계정입니다."
        case .en: "This account already exists."
        }
    }

    static func identityConflictMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "기존 계정으로 로그인하시겠어요? 로컬 익명 데이터는 삭제되지 않습니다."
        case .en: "Sign in to the existing account? Your local anonymous data will be kept."
        }
    }

    static func signInExistingAccount(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "로그인"
        case .en: "Sign In"
        }
    }

    static func cancel(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "취소"
        case .en: "Cancel"
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
        case .ko: "금액은 0보다 크고 99,999,999.00 이하, 소수점 둘째 자리까지만 가능합니다."
        case .en: "Amount must be greater than 0, at most 99,999,999.00, and have no more than 2 decimal places."
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
        case .ko: "외화 거래는 미래 날짜를 사용할 수 없습니다."
        case .en: "Foreign currency transactions cannot use a future date."
        }
    }
}
