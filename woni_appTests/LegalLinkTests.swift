import Foundation
import Testing
@testable import woni_app

/// 설정 화면·로그인 시트의 문서 버튼이 선택한 언어의 게시본으로 연결되는지 지킨다.
///
/// 문서가 앱 내장 전문에서 Notion 게시본 링크로 바뀌면서 "영어로 두었는데 국문 문서가 열린다"는
/// 회귀를 UITest로는 더 이상 잡을 수 없다 — 인앱 브라우저의 웹 콘텐츠는 별도 프로세스라 XCUITest가
/// 읽지 못한다. 결함 D-004가 지키던 언어 정합을 여기서 대신 못 박는다.
///
/// URL 문자열을 그대로 복사해 비교하면 구현을 옮겨 적은 것에 지나지 않으므로, 링크 사이의 관계와
/// 주소가 갖춰야 할 성질만 검사한다.
struct LegalLinkTests {
    @Test("약관 링크는 언어마다 다른 게시본을 가리킨다")
    func termsLinkDiffersByLanguage() throws {
        let korean = try #require(LegalContent.termsOfServiceLink(.ko))
        let english = try #require(LegalContent.termsOfServiceLink(.en))
        #expect(korean.url != english.url, "언어를 바꿔도 같은 문서가 열리면 D-004 회귀다")
    }

    @Test("개인정보처리방침 링크는 언어마다 다른 게시본을 가리킨다")
    func privacyLinkDiffersByLanguage() throws {
        let korean = try #require(LegalContent.privacyPolicyLink(.ko))
        let english = try #require(LegalContent.privacyPolicyLink(.en))
        #expect(korean.url != english.url, "언어를 바꿔도 같은 문서가 열리면 D-004 회귀다")
    }

    @Test("같은 언어에서 약관과 방침은 서로 다른 문서다")
    func termsAndPrivacyAreDistinctDocuments() throws {
        for language in AppLanguage.allCases {
            let terms = try #require(LegalContent.termsOfServiceLink(language))
            let privacy = try #require(LegalContent.privacyPolicyLink(language))
            #expect(terms.url != privacy.url, "\(language)에서 두 버튼이 같은 문서를 연다")
        }
    }

    /// 지원 페이지는 문의 창구가 하나뿐이라 언어별로 나누지 않는다. 약관·방침과 달리 언어에 따라
    /// 갈리지 않는다는 것 자체가 지켜야 할 성질이다.
    @Test("고객센터 링크는 약관·방침과 다른 문서이고 언어를 타지 않는다")
    func supportLinkIsSharedAcrossLanguages() throws {
        let support = try #require(LegalContent.supportLink)
        for language in AppLanguage.allCases {
            let terms = try #require(LegalContent.termsOfServiceLink(language))
            let privacy = try #require(LegalContent.privacyPolicyLink(language))
            #expect(support.url != terms.url, "\(language)에서 고객센터가 약관을 연다")
            #expect(support.url != privacy.url, "\(language)에서 고객센터가 방침을 연다")
        }
    }

    /// URL 생성이 실패하면 `LegalContent`가 `nil`을 돌려주고 버튼은 눌러도 아무 반응이 없다.
    /// 오탈자가 섞여도 조용히 넘어가므로 여기서 주소를 모두 확인한다.
    @Test("모든 링크가 notion.site 게시본을 https로 가리킨다")
    func allLinksArePublishedOverHTTPS() throws {
        for language in AppLanguage.allCases {
            for link in [
                LegalContent.termsOfServiceLink(language),
                LegalContent.privacyPolicyLink(language),
                LegalContent.supportLink
            ] {
                let url = try #require(link?.url, "\(language) 링크 생성이 실패했다")
                #expect(url.scheme == "https", "\(url)이 https가 아니다")
                #expect(url.host()?.hasSuffix("notion.site") == true, "\(url)이 게시본 도메인이 아니다")
            }
        }
    }
}
