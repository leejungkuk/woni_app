import Foundation

struct LegalClause: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

/// `sheet(item:)`으로 인앱 브라우저(`SafariView`)를 띄우기 위한 식별자 래퍼.
struct LegalLink: Identifiable {
    let id = UUID()
    let url: URL
}

enum LegalContent {
    static func termsOfService(_ language: AppLanguage) -> [LegalClause] {
        switch language {
        case .ko: TermsOfServiceText.korean
        case .en: TermsOfServiceText.english
        }
    }

    static let privacyPolicyPending = "개인정보 처리방침은 준비 중입니다."

    /// 게시본은 Notion에 있고 원본은 `docs/legal/*.md`다. 페이지를 삭제하거나 비공개로 돌리면
    /// 앱에서 문서를 볼 수 없게 되고 App Store에 등록한 URL도 함께 죽으므로 주소를 바꾸지 않는다.
    static func termsOfServiceLink(_ language: AppLanguage) -> LegalLink? {
        link(
            ko: "https://balanced-owner-32e.notion.site/3b27165d1c32811cbb88ef49f8811016",
            en: "https://balanced-owner-32e.notion.site/Terms-of-Service-English-3b27165d1c3281f3ac4eead114f26733",
            language
        )
    }

    static func privacyPolicyLink(_ language: AppLanguage) -> LegalLink? {
        link(
            ko: "https://balanced-owner-32e.notion.site/3b27165d1c3281a29604c6b390877b34",
            en: "https://balanced-owner-32e.notion.site/Privacy-Policy-English-3b27165d1c32810ebf0ecbc7fa26b3fa",
            language
        )
    }

    /// 지원 페이지는 언어별 게시본이 없는 단일 페이지다. 문의 창구가 하나라 번역본을 나눌 이유가
    /// 없고, 나누면 어느 쪽으로 들어왔는지에 따라 접수 경로가 갈린다.
    static var supportLink: LegalLink? {
        URL(string: "https://balanced-owner-32e.notion.site/Woni-Support-3b27165d1c3281e2b094cb2dda189654")
            .map { LegalLink(url: $0) }
    }

    private static func link(ko: String, en: String, _ language: AppLanguage) -> LegalLink? {
        let address = switch language {
        case .ko: ko
        case .en: en
        }
        return URL(string: address).map { LegalLink(url: $0) }
    }
}
