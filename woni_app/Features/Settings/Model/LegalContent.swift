import Foundation

struct LegalClause: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

enum LegalContent {
    static let termsOfService: [LegalClause] = [
        LegalClause(
            title: "서비스 이용",
            body: "Woni는 수입과 지출을 기록하고 월별 내역을 확인할 수 있는 가계부 서비스입니다."
        ),
        LegalClause(
            title: "사용자 데이터",
            body: "사용자가 입력한 내용은 서비스 제공을 위해 처리됩니다. 자세한 개인정보 처리 기준은 정식 정책에서 안내됩니다."
        ),
        LegalClause(
            title: "약관 변경",
            body: "서비스 이용약관이 확정되거나 변경되면 앱 내 화면 또는 공지 수단을 통해 안내합니다."
        )
    ]

    static let privacyPolicyPending = "개인정보 처리방침은 준비 중입니다."
}
