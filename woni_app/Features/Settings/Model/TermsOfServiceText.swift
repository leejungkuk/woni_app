import Foundation

/// 서비스 이용약관 전문. 원본은 `docs/legal/terms-of-service.{ko,en}.md`이며 개정 시 양쪽을 함께 고친다.
///
/// 문의처(문의 이메일)와 부칙(시행일자)은 값이 확정되지 않아 아직 넣지 않았다.
/// 확정되면 두 조항을 배열 끝에 추가한다 — `docs/legal/README.md` 참고.
enum TermsOfServiceText {
    static let korean: [LegalClause] = [
        LegalClause(
            title: "제1조 (목적)",
            body: """
            이 약관은 이지영(이하 "운영자")가 제공하는 가계부 서비스 "Woni"(이하 "서비스")의 이용과 관련하여 \
            운영자와 이용자 간의 권리, 의무 및 책임사항, 기타 필요한 사항을 규정함을 목적으로 합니다.
            """
        ),
        LegalClause(
            title: "제2조 (용어의 정의)",
            body: """
            1. "서비스"란 운영자가 제공하는 Woni 애플리케이션 및 이에 부수되는 일체의 서비스를 의미합니다.
            2. "이용자"란 이 약관에 따라 서비스를 이용하는 자로서, 회원과 비회원을 모두 포함합니다.
            3. "회원"이란 구글 또는 애플 계정을 이용한 소셜로그인을 통해 운영자와 이용계약을 체결하고 \
            서비스를 이용하는 자를 말합니다.
            4. "비회원"이란 로그인하지 않고 서비스를 이용하는 자를 말합니다. 비회원이 입력한 콘텐츠는 \
            이용자의 기기에 저장되는 동시에, 서비스 제공을 위하여 발급되는 익명 식별자에 연결되어 \
            운영자의 서버에도 저장됩니다.
            5. "콘텐츠"란 이용자가 서비스 내에서 작성·입력하는 가계부 데이터(수입·지출 구분, 금액, 통화, \
            분류, 자산, 거래일자, 메모 등)를 의미합니다.
            """
        ),
        LegalClause(
            title: "제3조 (약관의 효력 및 변경)",
            body: """
            1. 이 약관은 서비스 화면 또는 앱 내 게시를 통해 공지함으로써 효력이 발생합니다.
            2. 운영자는 「약관의 규제에 관한 법률」 등 관련 법령을 위반하지 않는 범위에서 이 약관을 \
            변경할 수 있습니다.
            3. 운영자가 약관을 변경하는 경우 적용일자 및 변경사유를 명시하여 적용일자 7일 전부터 앱 내 공지 \
            또는 서비스 화면을 통해 공지합니다. 다만 이용자에게 불리한 변경의 경우에는 적용일자 30일 \
            전부터 공지합니다.
            4. 이용자가 변경된 약관에 동의하지 않는 경우 서비스 이용을 중단하고 탈퇴할 수 있습니다. 변경 \
            약관을 공지하면서 이용자가 적용일자까지 거부의사를 표시하지 않으면 동의한 것으로 본다는 뜻을 \
            명확하게 고지하였음에도 이용자가 명시적으로 거부의사를 표시하지 아니한 경우, 변경된 약관에 \
            동의한 것으로 봅니다.
            """
        ),
        LegalClause(
            title: "제4조 (이용계약의 체결)",
            body: """
            1. 회원가입은 이용자가 구글 또는 애플 계정을 이용한 소셜로그인 과정에서 이 약관 및 \
            개인정보처리방침에 동의하고, 운영자가 이를 승낙함으로써 체결됩니다.
            2. 비회원의 이용계약은 이용자가 서비스를 설치하여 이용을 시작함으로써 이 약관 및 \
            개인정보처리방침에 동의한 것으로 보아 체결됩니다. 이 약관과 개인정보처리방침의 전문은 앱 내 \
            [설정] 화면에서 언제든지 확인하실 수 있습니다.
            3. 서비스 이용 가능 연령은 만 14세 이상입니다. 만 14세 미만인 자는 서비스를 이용할 수 없습니다.
            4. 운영자는 다음 각 호에 해당하는 경우 이용신청을 승낙하지 않거나 사후에 이용계약을 해지할 수 \
            있습니다.
             · 만 14세 미만인 경우
             · 타인의 명의 또는 계정을 도용한 경우
             · 허위 정보를 기재한 경우
             · 이 약관을 위반하여 이용계약이 해지된 이력이 있는 경우
            """
        ),
        LegalClause(
            title: "제5조 (서비스의 제공 및 변경)",
            body: """
            1. 운영자는 다음과 같은 서비스를 제공합니다.
             · 수입·지출 등 가계부 데이터의 수동 입력, 수정, 삭제 및 조회 기능
             · 월별 수입·지출 합계 및 거래 내역 조회 기능
             · 외화 거래에 대한 환율 적용 및 원화 환산 표시 기능
             · 이용자의 가계부 데이터에 대한 서버(클라우드) 동기화 기능
            2. 본 서비스는 계좌·카드 자동 연동(오픈뱅킹 등) 기능을 제공하지 않으며, 모든 거래 내역은 \
            이용자가 직접 입력합니다.
            3. 운영자는 서비스의 내용을 변경할 수 있으며, 중요한 변경의 경우 제3조에 준하여 사전에 \
            공지합니다.
            """
        ),
        LegalClause(
            title: "제6조 (서비스 이용시간 및 중단)",
            body: """
            1. 서비스는 운영자의 업무상 또는 기술상 특별한 사유가 없는 한 연중무휴, 1일 24시간 제공함을 \
            원칙으로 합니다.
            2. 운영자는 시스템 점검, 서버·설비의 장애, 통신 두절, 천재지변 등의 사유가 발생한 경우 서비스 \
            제공을 일시 중단할 수 있으며, 이 경우 사전에 공지합니다. 다만 부득이한 사유로 사전 공지가 \
            불가능한 경우 사후에 공지할 수 있습니다.
            3. 운영자는 상당한 이유가 있는 경우 서비스의 전부 또는 일부를 종료할 수 있습니다. 이 경우 \
            종료일 30일 전까지 앱 내 공지 등을 통해 이용자에게 알리고, 이용자가 자신의 데이터를 \
            확인·보관할 수 있는 방법을 함께 안내합니다.
            """
        ),
        LegalClause(
            title: "제7조 (이용요금)",
            body: """
            1. 서비스의 모든 기능은 현재 무료로 제공됩니다.
            2. 운영자가 향후 유료 서비스를 도입하는 경우 상품 구성, 가격, 결제수단, 환불 기준 등 세부 \
            사항을 제3조에 따른 약관 개정 및 사전 공지를 통해 안내하며, 이용자의 별도 동의 없이 기존에 \
            무료로 제공되던 기능을 소급하여 유료로 전환하지 않습니다.
            """
        ),
        LegalClause(
            title: "제8조 (이용자의 의무)",
            body: """
            1. 이용자는 관계 법령, 이 약관, 이용안내 및 서비스와 관련하여 공지된 사항을 준수하여야 합니다.
            2. 이용자는 본인의 계정(소셜로그인 정보 포함)을 제3자가 이용하도록 하여서는 안 되며, 계정 관리 \
            소홀로 발생한 손해에 대한 책임은 이용자에게 있습니다.
            3. 이용자는 다음 각 호의 행위를 하여서는 안 됩니다.
             · 서비스의 정상적인 운영을 방해하는 행위
             · 운영자의 사전 승낙 없이 서비스를 이용하여 얻은 정보를 복제, 송신, 출판, 배포, 방송 기타 \
            방법으로 영리목적으로 이용하거나 제3자에게 이용하게 하는 행위
             · 자동화된 수단을 이용하여 서비스에 비정상적으로 접근하거나 과도한 부하를 유발하는 행위
             · 타인의 권리를 침해하거나 법령에 위반되는 행위
            """
        ),
        LegalClause(
            title: "제9조 (운영자의 의무)",
            body: """
            1. 운영자는 관련 법령과 이 약관이 금지하거나 미풍양속에 반하는 행위를 하지 않으며, 계속적이고 \
            안정적인 서비스 제공을 위하여 최선을 다합니다.
            2. 운영자는 이용자의 개인정보 보호를 위하여 보안시스템을 갖추고 개인정보처리방침을 공시하고 \
            준수합니다.
            3. 운영자는 이용자로부터 제기되는 의견이나 불만이 정당하다고 인정할 경우 이를 처리하며, 처리에 \
            장기간이 소요되는 경우 그 사유와 처리 일정을 안내합니다.
            """
        ),
        LegalClause(
            title: "제10조 (콘텐츠의 소유 및 이용)",
            body: """
            1. 이용자가 서비스 내에 입력한 콘텐츠의 소유권은 해당 이용자에게 있습니다.
            2. 운영자는 이용자의 콘텐츠를 서비스 제공에 필요한 범위(저장, 동기화, 화면 표시, 장애 대비 \
            백업)에 한정하여 이용하며, 그 외의 목적으로 이용하거나 제3자에게 제공하지 않습니다.
            3. 운영자가 개인을 식별할 수 없도록 가공한 통계 정보를 서비스 개선 목적으로 이용하는 경우, 그 \
            처리 기준은 개인정보처리방침에 따릅니다.
            """
        ),
        LegalClause(
            title: "제11조 (지식재산권)",
            body: """
            1. 서비스 및 서비스에 포함된 소프트웨어, 디자인, 상표, 문안 등에 대한 지식재산권은 운영자에게 \
            귀속됩니다.
            2. 이용자는 운영자의 사전 서면 승낙 없이 전항의 지식재산권을 복제, 배포, 개작, 역설계하거나 \
            제3자에게 이용하게 할 수 없습니다.
            3. 제1항은 이용자가 입력한 콘텐츠에 대한 이용자의 권리에 영향을 미치지 않습니다.
            """
        ),
        LegalClause(
            title: "제12조 (계약해지 및 이용제한)",
            body: """
            1. 회원은 언제든지 앱 내 [설정] 화면의 탈퇴 기능을 통해 이용계약 해지(탈퇴)를 신청할 수 \
            있습니다.
            2. 탈퇴가 완료되면 운영자는 회원의 계정 정보 및 서버에 저장된 콘텐츠를 지체 없이 삭제하며, \
            삭제된 데이터는 복구할 수 없습니다. 다만 관련 법령에 따라 보존할 의무가 있는 정보는 해당 \
            법령이 정한 기간 동안 보관합니다.
            3. 탈퇴 시 이용자의 기기에 저장된 데이터도 함께 삭제됩니다.
            4. 비회원에게는 계정이 없으므로 탈퇴 절차가 적용되지 않습니다. 비회원은 앱 내 삭제 기능을 \
            통해 자신이 입력한 콘텐츠를 기기와 서버에서 함께 삭제할 수 있습니다.
            5. 운영자는 이용자가 이 약관을 위반하거나 서비스의 정상적인 운영을 방해한 경우 사전 통지 후 \
            서비스 이용을 제한하거나 이용계약을 해지할 수 있습니다. 다만 긴급한 조치가 필요한 경우 \
            사후에 통지할 수 있습니다.
            """
        ),
        LegalClause(
            title: "제13조 (데이터의 보관 및 백업)",
            body: """
            1. 비회원이 입력한 콘텐츠는 익명 식별자에 연결되어 서버에 저장되나, 비회원에게는 로그인 수단이 \
            없어 다른 기기에서 해당 콘텐츠에 접근할 수 없습니다. 따라서 앱 삭제, 기기 초기화, 기기 \
            분실·고장 등의 경우 복구할 수 없습니다.
            2. 회원의 콘텐츠는 로그인 상태에서 서버에 동기화되며, 기기 변경 시 동일한 계정으로 로그인하여 \
            복원할 수 있습니다.
            3. 운영자는 서버에 저장된 데이터의 보관을 위하여 합리적인 노력을 다하나, 이는 이용자가 직접 \
            관리하는 별도의 백업을 대체하지 않습니다.
            """
        ),
        LegalClause(
            title: "제14조 (면책조항)",
            body: """
            1. 운영자는 천재지변, 불가항력, 이용자의 귀책사유로 인한 서비스 중단에 대하여 책임을 지지 \
            않습니다.
            2. 운영자는 이용자가 직접 입력한 콘텐츠의 정확성에 대하여 보증하지 않으며, 이를 기반으로 한 \
            이용자의 재무적 판단 및 그 결과에 대하여 책임을 지지 않습니다.
            3. 서비스가 제공하는 환율 정보는 외부 기관이 제공하는 데이터에 기초한 참고용 정보로서, 실제 \
            거래 시점의 환율이나 금융기관이 적용하는 환율과 다를 수 있습니다. 운영자는 환율 정보의 \
            정확성·실시간성을 보증하지 않으며, 이를 이용한 판단의 결과에 대하여 책임을 지지 않습니다.
            4. 운영자는 서비스를 매개로 이용자 상호간 또는 이용자와 제3자 간에 발생한 분쟁에 대하여 개입할 \
            의무가 없으며, 이로 인한 손해를 배상할 책임이 없습니다.
            5. 이 조의 어떠한 규정도 운영자의 고의 또는 중대한 과실로 인하여 발생한 손해에 대한 책임을 \
            배제하지 않습니다.
            """
        ),
        LegalClause(
            title: "제15조 (준거법 및 재판관할)",
            body: """
            1. 이 약관 및 운영자와 이용자 간의 분쟁에 관하여는 대한민국 법령을 준거법으로 합니다.
            2. 서비스 이용과 관련하여 운영자와 이용자 간에 발생한 분쟁에 관한 소송은 「민사소송법」에 따른 \
            관할법원에 제기합니다.
            """
        )
    ]
}

extension TermsOfServiceText {
    static let english: [LegalClause] = [
        LegalClause(
            title: "Article 1 (Purpose)",
            body: """
            These Terms of Service ("Terms") govern the rights, obligations, and responsibilities \
            between Ji Young Lee ("Operator") and users in connection with the use of "Woni," a personal \
            budgeting service ("Service") provided by the Operator.
            """
        ),
        LegalClause(
            title: "Article 2 (Definitions)",
            body: """
            1. "Service" means the Woni application provided by the Operator and all related services.
            2. "User" means any person who uses the Service under these Terms, including both Members \
            and Non-members.
            3. "Member" means a person who has entered into a service agreement with the Operator \
            through social login using a Google or Apple account.
            4. "Non-member" means a person who uses the Service without logging in. Content entered by \
            a Non-member is stored on the user's device and, at the same time, is stored on the \
            Operator's servers linked to an anonymous identifier issued to provide the Service.
            5. "Content" means the budgeting data a User creates or enters within the Service, \
            including income/expense type, amount, currency, category, asset, transaction date, and \
            memo.
            """
        ),
        LegalClause(
            title: "Article 3 (Effect and Amendment of the Terms)",
            body: """
            1. These Terms take effect when posted within the Service screen or the application.
            2. The Operator may amend these Terms to the extent that such amendment does not violate \
            applicable laws.
            3. When the Operator amends these Terms, it will announce the effective date and the \
            reason for the amendment within the application or on the Service screen at least 7 days \
            before the effective date. For amendments unfavorable to Users, the announcement will be \
            made at least 30 days in advance.
            4. A User who does not agree to the amended Terms may discontinue use of the Service and \
            withdraw from membership. If the Operator has clearly stated that failure to express \
            refusal by the effective date will be deemed acceptance, and the User does not expressly \
            refuse by that date, the User is deemed to have accepted the amended Terms.
            """
        ),
        LegalClause(
            title: "Article 4 (Formation of the Service Agreement)",
            body: """
            1. Membership is established when a User agrees to these Terms and the Privacy Policy \
            during social login with a Google or Apple account, and the Operator accepts the \
            application.
            2. For Non-members, the service agreement is formed when the User installs the Service and \
            begins using it, at which point the User is deemed to have agreed to these Terms and the \
            Privacy Policy. The full text of these Terms and the Privacy Policy is available at any \
            time in the app's [Settings] screen.
            3. Users must be at least 14 years of age. Persons under 14 may not use the Service.
            4. The Operator may refuse an application, or terminate the agreement after acceptance, \
            in any of the following cases:
             · The applicant is under 14 years of age
             · The applicant has misappropriated another person's identity or account
             · The applicant has provided false information
             · The applicant's agreement was previously terminated for violation of these Terms
            """
        ),
        LegalClause(
            title: "Article 5 (Provision and Modification of the Service)",
            body: """
            1. The Operator provides the following services:
             · Manual entry, modification, deletion, and viewing of budgeting data such as income and \
            expenses
             · Viewing of monthly income/expense totals and transaction history
             · Application of exchange rates to foreign-currency transactions and display of \
            KRW-converted amounts
             · Server (cloud) synchronization of Users' budgeting data
            2. The Service does not provide automatic linkage with bank accounts or credit cards (such \
            as open banking). All transaction records are entered directly by the User.
            3. The Operator may modify the content of the Service and will provide advance notice of \
            material changes in accordance with Article 3.
            """
        ),
        LegalClause(
            title: "Article 6 (Service Hours and Suspension)",
            body: """
            1. The Service is provided 24 hours a day, year-round, in principle, unless there are \
            special operational or technical reasons.
            2. The Operator may temporarily suspend the Service in the event of system maintenance, \
            server or equipment failure, communication outage, natural disaster, or similar \
            circumstances, and will provide advance notice. Where advance notice is not possible for \
            unavoidable reasons, notice may be given afterwards.
            3. The Operator may discontinue all or part of the Service for substantial reasons. In \
            such case, the Operator will notify Users at least 30 days before the discontinuation \
            date and provide guidance on how Users may review and preserve their data.
            """
        ),
        LegalClause(
            title: "Article 7 (Fees)",
            body: """
            1. All features of the Service are currently provided free of charge.
            2. If the Operator introduces paid services in the future, details such as product \
            composition, pricing, payment methods, and refund criteria will be announced through \
            amendment of these Terms and advance notice under Article 3. The Operator will not \
            retroactively convert previously free features into paid features without the User's \
            separate consent.
            """
        ),
        LegalClause(
            title: "Article 8 (Obligations of the User)",
            body: """
            1. Users shall comply with applicable laws, these Terms, usage guidelines, and any notices \
            published in connection with the Service.
            2. Users shall not allow any third party to use their account (including social login \
            credentials), and Users are responsible for any damage arising from negligent account \
            management.
            3. Users shall not engage in any of the following:
             · Interfering with the normal operation of the Service
             · Reproducing, transmitting, publishing, distributing, broadcasting, or otherwise using \
            information obtained through the Service for commercial purposes, or allowing a third \
            party to do so, without the Operator's prior consent
             · Accessing the Service by automated means in an abnormal manner or generating excessive \
            load
             · Infringing the rights of others or violating applicable laws
            """
        ),
        LegalClause(
            title: "Article 9 (Obligations of the Operator)",
            body: """
            1. The Operator shall not engage in any act prohibited by applicable laws or these Terms, \
            or contrary to public morals, and shall use its best efforts to provide the Service \
            continuously and reliably.
            2. The Operator shall maintain security systems to protect Users' personal information \
            and shall publish and comply with its Privacy Policy.
            3. Where a User's opinion or complaint is found to be justified, the Operator shall \
            address it. If processing requires an extended period, the Operator shall inform the \
            User of the reason and the expected schedule.
            """
        ),
        LegalClause(
            title: "Article 10 (Ownership and Use of Content)",
            body: """
            1. Ownership of Content entered by a User within the Service belongs to that User.
            2. The Operator uses User Content solely to the extent necessary to provide the Service — \
            storage, synchronization, display, and backup for failure recovery — and does not use it \
            for any other purpose or provide it to third parties.
            3. Where the Operator uses statistical information processed so that individuals cannot \
            be identified for the purpose of improving the Service, such processing is governed by \
            the Privacy Policy.
            """
        ),
        LegalClause(
            title: "Article 11 (Intellectual Property)",
            body: """
            1. Intellectual property rights in the Service and in the software, designs, trademarks, \
            and text included in the Service belong to the Operator.
            2. Users may not reproduce, distribute, adapt, reverse-engineer, or allow third parties to \
            use the intellectual property described in the preceding paragraph without the \
            Operator's prior written consent.
            3. Paragraph 1 does not affect Users' rights in the Content they enter.
            """
        ),
        LegalClause(
            title: "Article 12 (Termination and Restriction of Use)",
            body: """
            1. Members may request termination of the service agreement (withdrawal) at any time \
            through the account deletion feature in the app's [Settings] screen.
            2. Upon completion of withdrawal, the Operator will delete the Member's account \
            information and Content stored on its servers without delay. Deleted data cannot be \
            recovered. Information that the Operator is required to retain under applicable laws \
            will be kept for the period prescribed by those laws.
            3. Upon withdrawal, data stored on the User's device is also deleted.
            4. Non-members have no account, so the withdrawal procedure does not apply to them. A \
            Non-member may delete Content they have entered from both the device and the server using \
            the delete feature in the app.
            5. The Operator may restrict use of the Service or terminate the service agreement, after \
            prior notice, where a User violates these Terms or interferes with the normal operation \
            of the Service. Where urgent action is required, notice may be given afterwards.
            """
        ),
        LegalClause(
            title: "Article 13 (Data Storage and Backup)",
            body: """
            1. Content entered by Non-members is stored on the server linked to an anonymous \
            identifier, but Non-members have no means of signing in and therefore cannot access that \
            Content from another device. It accordingly cannot be recovered if the application is \
            deleted, the device is reset, or the device is lost or damaged.
            2. Members' Content is synchronized to the server while logged in and can be restored by \
            signing in with the same account on a new device.
            3. The Operator makes reasonable efforts to preserve data stored on its servers, but this \
            does not replace a separate backup managed by the User.
            """
        ),
        LegalClause(
            title: "Article 14 (Disclaimers)",
            body: """
            1. The Operator is not liable for Service interruptions caused by natural disasters, \
            force majeure, or causes attributable to the User.
            2. The Operator does not warrant the accuracy of Content entered directly by Users and is \
            not liable for Users' financial decisions based on such Content or the results thereof.
            3. Exchange rate information provided by the Service is reference information based on \
            data supplied by external institutions and may differ from the exchange rate at the \
            actual time of a transaction or from rates applied by financial institutions. The \
            Operator does not warrant the accuracy or timeliness of exchange rate information and \
            is not liable for the results of decisions made using it.
            4. The Operator has no obligation to intervene in, and is not liable for damages arising \
            from, disputes between Users or between a User and a third party arising through the \
            Service.
            5. Nothing in this Article excludes the Operator's liability for damages caused by its \
            intentional misconduct or gross negligence.
            """
        ),
        LegalClause(
            title: "Article 15 (Governing Law and Jurisdiction)",
            body: """
            1. These Terms and any dispute between the Operator and a User are governed by the laws \
            of the Republic of Korea.
            2. Any lawsuit concerning a dispute between the Operator and a User arising in connection \
            with the use of the Service shall be filed with the court having jurisdiction under the \
            Civil Procedure Act of the Republic of Korea.
            """
        )
    ]
}
