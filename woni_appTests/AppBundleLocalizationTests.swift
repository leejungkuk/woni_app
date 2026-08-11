import Foundation
import Testing

/// 앱 번들이 선언한 지원 언어 목록을 검증한다.
/// iOS는 `Locale.current`를 「기기 선호 언어 ∩ 앱 지원 언어」로 계산하므로, 지원 언어에 ko가 없으면
/// 한국어 기기에서도 항상 en으로 수렴해 `AppLanguageStore`가 첫 진입 언어를 영어로 정한다.
/// 실제 `Locale.current`는 기기 설정에 좌우돼 단언할 수 없으니, 그 계산에 들어가는 입력인
/// 번들 선언과 선호 언어 매칭 결과를 대신 고정한다.
struct AppBundleLocalizationTests {
    @Test("앱 번들이 ko·en을 지원 언어로 선언한다")
    func declaresKoreanAndEnglish() {
        let localizations = Set(Bundle.main.localizations)

        #expect(localizations.contains("ko"))
        #expect(localizations.contains("en"))
    }

    @Test("기기 선호 언어가 한국어면 ko로 매칭된다")
    func matchesKoreanForKoreanPreference() {
        let matched = Bundle.preferredLocalizations(
            from: Bundle.main.localizations,
            forPreferences: ["ko-KR"]
        )

        #expect(matched.first == "ko")
    }

    /// 정책은 "ko면 한국어, **그 외는 모두 영어**"다. ko를 지원 언어로 넣은 뒤에도 지원하지 않는
    /// 기기 언어가 영어로 떨어지는지 못 박는다 — 여기가 깨지면 일본어 기기 등에서 첫 진입 언어가 갈린다.
    @Test("지원하지 않는 기기 언어는 영어로 떨어진다")
    func fallsBackToEnglishForUnsupportedPreference() {
        let matched = Bundle.preferredLocalizations(
            from: Bundle.main.localizations,
            forPreferences: ["ja-JP"]
        )

        #expect(matched.first == "en")
    }
}
