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
}
