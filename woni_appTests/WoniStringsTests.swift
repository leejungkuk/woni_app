import Testing
@testable import woni_app

struct WoniStringsTests {
    @Test("정적 chrome 문자열은 언어별 값을 반환한다")
    func staticChromeStringsUseLanguageSpecificValues() {
        #expect(WoniStrings.income(.ko) == "수입")
        #expect(WoniStrings.income(.en) == "Income")
        #expect(WoniStrings.settingsTitle(.en) == "Setting")
        #expect(WoniStrings.baseCurrency(.en) == "Main Currency")
        #expect(WoniStrings.category(.en) == "CATEGORY")
        #expect(WoniStrings.asset(.en) == "PROPERTY")
        #expect(WoniStrings.memoPlaceholder(.en) == "Write down where you used it.")
        #expect(WoniStrings.appStartFailedTitle(.ko) == "앱을 시작할 수 없습니다.")
        #expect(WoniStrings.appStartFailedTitle(.en) == "Unable to start the app.")
        #expect(WoniStrings.ratePreviewStale(.ko) == "기준일 다름")
        #expect(WoniStrings.ratePreviewStale(.en) == "Different rate date")
        #expect(WoniStrings.rateEstimated(.ko) == "추정 환율")
        #expect(WoniStrings.rateEstimated(.en) == "Estimated rate")
        #expect(WoniStrings.remoteLogoutTitle(.ko) == "세션이 종료되었습니다.")
        #expect(WoniStrings.remoteLogoutTitle(.en) == "Your session has ended.")
        #expect(WoniStrings.remoteLogoutMessage(.ko).contains("만료"))
        #expect(WoniStrings.remoteLogoutMessage(.en).contains("expired"))
        #expect(WoniStrings.loginOfflineMessage(.ko).contains("연결"))
        #expect(WoniStrings.loginOfflineMessage(.en).contains("connection"))
        #expect(WoniStrings.myInfo(.ko) == "내 정보")
        #expect(WoniStrings.myInfo(.en) == "My Info")
        #expect(WoniStrings.languageKorean(.ko) == "한국어")
        #expect(WoniStrings.languageKorean(.en) == "Korean")
        #expect(WoniStrings.languageEnglish(.ko) == "영어")
        #expect(WoniStrings.languageEnglish(.en) == "English")
        #expect(WoniStrings.withdraw(.ko) == "탈퇴하기")
        #expect(WoniStrings.withdraw(.en) == "Delete Account")
        #expect(WoniStrings.deleteMyData(.ko) == "내 데이터 삭제")
        #expect(WoniStrings.deleteMyData(.en) == "Delete My Data")
    }

    @Test("탈퇴 문구는 Apple 예고·완료 안내를 해당 상황에서만 담는다")
    func withdrawalStringsMentionAppleOnlyWhenRelevant() {
        for language in [AppLanguage.ko, .en] {
            // D7 — 시트 예고는 Apple 연동 회원 문구에만 있다.
            #expect(WoniStrings.withdrawConfirmMessageMemberApple(language).contains("Apple"))
            #expect(!WoniStrings.withdrawConfirmMessageMember(language).contains("Apple"))
            #expect(!WoniStrings.withdrawConfirmMessageGuest(language).contains("Apple"))
            // 비회원 문구는 계정이 아니라 데이터만 말한다(D3).
            #expect(WoniStrings.withdrawConfirmMessageGuest(language)
                != WoniStrings.withdrawConfirmMessageMember(language))
            // D5·D8 — 완료 기본 문구에는 Apple 안내가 없고, 연동이 남은 경우의 안내에만 있다.
            #expect(!WoniStrings.withdrawCompletedMessage(language).contains("Apple"))
            #expect(WoniStrings.withdrawCompletedAppleNote(language).contains("Apple"))
            #expect(WoniStrings.purgeConfirmMessage(language).contains(
                language == .ko ? "계정과 로그인은 그대로 유지" : "account and sign-in remain"
            ))
            #expect(WoniStrings.purgeConfirmMessage(language).contains(
                language == .ko ? "복구할 수 없습니다" : "cannot be recovered"
            ))
            // pending 안내의 핵심은 "연결되면 자동 재개"다 — 문구가 이 약속을 잃으면 실패해야 한다.
            #expect(WoniStrings.purgePendingMessage(language).contains(
                language == .ko ? "자동으로" : "automatically"
            ))
            // 회원은 계정을, 비회원은 데이터를 지우므로 확인 버튼 문구도 갈린다.
            #expect(WoniStrings.withdrawActionMember(language)
                != WoniStrings.withdrawActionGuest(language))
            // 완료 토스트도 같은 이유로 갈린다.
            #expect(WoniStrings.withdrawCompletedToastMember(language)
                != WoniStrings.withdrawCompletedToastGuest(language))
            for string in [
                WoniStrings.withdrawActionMember(language),
                WoniStrings.withdrawActionGuest(language),
                WoniStrings.withdrawConfirmTitleMember(language),
                WoniStrings.withdrawConfirmTitleGuest(language),
                WoniStrings.withdrawInProgress(language),
                WoniStrings.withdrawFailedMessage(language),
                WoniStrings.withdrawOfflineMessage(language),
                WoniStrings.purgePendingMessage(language)
            ] {
                #expect(!string.isEmpty)
            }
        }
        #expect(WoniStrings.withdrawActionMember(.ko) == "탈퇴")
        #expect(WoniStrings.withdrawActionGuest(.ko) == "삭제")
        #expect(WoniStrings.withdrawInProgress(.ko) == "삭제 중")
        #expect(WoniStrings.withdrawCompletedMessage(.ko) == "삭제가 완료되었습니다.")
        #expect(WoniStrings.withdrawOfflineMessage(.ko).contains("네트워크"))
    }

    @Test("캘린더 문자열은 언어별 값을 반환한다")
    func calendarStringsUseLanguageSpecificValues() {
        #expect(WoniStrings.weekdaysShort(.ko) == ["일", "월", "화", "수", "목", "금", "토"])
        #expect(WoniStrings.weekdaysShort(.en) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        #expect(WoniStrings.pickerCancel(.ko) == "취소")
        #expect(WoniStrings.pickerCancel(.en) == "Cancel")
    }

    @Test("검증 에러 문자열은 언어별 값을 반환한다")
    func validationErrorStringsUseLanguageSpecificValues() {
        #expect(
            WoniStrings.errMissingSelection(.ko) == "저장하기 전에 카테고리와 자산을 선택하세요."
        )
        #expect(WoniStrings.errMissingSelection(.en) == "Select a category and asset before saving.")
        #expect(WoniStrings.errFutureDate(.ko) == "외화 거래는 미래 날짜를 사용할 수 없습니다.")
        #expect(WoniStrings.errFutureDate(.en) == "Foreign currency transactions cannot use a future date.")
    }

    @Test("수정과 삭제 화면 문자열은 ko/en 대칭 값을 제공한다")
    func editAndDeleteStringsUseLanguageSpecificValues() {
        #expect(WoniStrings.editEntryTitle(.ko) == "수정")
        #expect(WoniStrings.editEntryTitle(.en) == "Edit")
        #expect(WoniStrings.deleteEntry(.ko) == "삭제")
        #expect(WoniStrings.deleteEntry(.en) == "Delete")
        #expect(WoniStrings.deleteConfirmationTitle(.ko) == "정말 삭제하시겠습니까?")
        #expect(WoniStrings.deleteConfirmationTitle(.en) == "Delete this entry?")
        #expect(WoniStrings.deleteConfirmationMessage(.ko) == "삭제된 데이터는 복구할 수 없습니다.")
        #expect(WoniStrings.deleteConfirmationMessage(.en) == "Deleted data cannot be recovered.")
        #expect(WoniStrings.deleteConfirmationDelete(.ko) == "삭제")
        #expect(WoniStrings.deleteConfirmationDelete(.en) == "Delete")
        #expect(WoniStrings.deleteConfirmationCancel(.ko) == "취소")
        #expect(WoniStrings.deleteConfirmationCancel(.en) == "Cancel")
        #expect(WoniStrings.transactionNotFoundTitle(.ko) == "항목을 찾을 수 없습니다.")
        #expect(WoniStrings.transactionNotFoundTitle(.en) == "Entry not found.")
        #expect(WoniStrings.transactionNotFoundMessage(.ko).contains("목록"))
        #expect(WoniStrings.transactionNotFoundMessage(.en).contains("list"))
        #expect(WoniStrings.deleteFailedTitle(.ko) == "삭제할 수 없습니다.")
        #expect(WoniStrings.deleteFailedTitle(.en) == "Unable to delete entry.")
        #expect(WoniStrings.deleteFailedMessage(.ko).contains("다시"))
        #expect(WoniStrings.deleteFailedMessage(.en).contains("again"))
    }

    @Test("토스트 문구는 언어별 값을 반환한다")
    func toastStringsUseLanguageSpecificValues() {
        #expect(WoniStrings.entryDeletedToast(.ko) == "삭제되었습니다.")
        #expect(WoniStrings.entryDeletedToast(.en) == "Deleted.")
        #expect(WoniStrings.entryDeletedToast(.ko) != WoniStrings.entryDeletedToast(.en))
        #expect(WoniStrings.amountOverLimitToast(.ko, limit: "99,999,999")
            == "99,999,999를 넘는 금액은 입력할 수 없습니다.")
        #expect(WoniStrings.amountOverLimitToast(.en, limit: "99,999,999")
            == "You can't enter an amount over 99,999,999.")
        #expect(WoniStrings.amountOverLimitToast(.ko, limit: "99,999,999")
            != WoniStrings.amountOverLimitToast(.en, limit: "99,999,999"))
    }
}
