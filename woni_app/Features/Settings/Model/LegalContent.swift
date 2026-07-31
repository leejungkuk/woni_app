import Foundation

struct LegalClause: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

enum LegalContent {
    static func termsOfService(_ language: AppLanguage) -> [LegalClause] {
        switch language {
        case .ko: TermsOfServiceText.korean
        case .en: TermsOfServiceText.english
        }
    }

    static let privacyPolicyPending = "개인정보 처리방침은 준비 중입니다."
}
