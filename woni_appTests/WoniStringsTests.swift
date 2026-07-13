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
}
