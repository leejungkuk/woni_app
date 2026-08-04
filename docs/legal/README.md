# 법적 고지 문서

앱 내 [설정] → 서비스 약관 / 개인정보 보호정책에 표시되고, App Store Connect의 Privacy Policy URL로도 사용되는 문서다.

| 파일 | 내용 |
| --- | --- |
| `terms-of-service.ko.md` / `.en.md` | 서비스 이용약관 (15개 조 + 문의처 + 부칙) |
| `privacy-policy.ko.md` / `.en.md` | 개인정보처리방침 (14개 항목) |

법적 주체는 **명의자 개인**(법인 아님)이며, 문서상 호칭은 "운영자"(영문 "Operator")다. 앱을 개발하고 문의에 대응하는 실무자는 "개발자"(영문 "Developer")로 구분해 적는다 — 두 역할이 다른 사람이므로 호칭을 겹치게 쓰지 않는다. 개인사업자 등록은 예정 상태이나, 등록해도 계약 주체는 여전히 자연인 명의자이므로 문서 명의는 바뀌지 않는다.

## 확정된 값

- **명의자(운영자): 이지영** — 약관 제1조의 계약 당사자와 방침 서두의 개인정보처리자에 사용. Apple Developer Program(Individual) 계정 명의자이며 App Store 판매자명으로 실명이 노출되므로, 문서 기재로 인한 추가 노출은 없다. 계약 당사자·처리자에는 실무자를 적지 않는다.
- **인프라: Supabase, Inc.(인증·계정) + Amazon Web Services, Inc.(서버·가계부 데이터)** — 두 리전 모두 도쿄 `ap-northeast-1`이므로 **이전 국가는 일본**이고, 가계부 데이터도 국외로 나가므로 AWS도 국외 이전 고지 대상이다. 그래서 방침 6항 표를 단일 수탁자 세로형에서 수탁자별 가로형으로 바꿨다. AWS는 콘솔 직접 가입이라 계약 주체가 미국 법인(`Amazon Web Services, Inc.`)이며, AWS 코리아 계약으로 바뀌면 상호를 함께 고친다.
- **개발자 / 개인정보 보호책임자: 이정국** — 앱을 개발하고 문의 대응을 맡는 실무자로, 약관 "문의처" 절과 방침 12항에 사용. 「개인정보 보호법」상 보호책임자는 개인정보처리자가 지정하는 사람이므로 명의자와 달라도 된다.
- **문의 이메일: woniapp.help@gmail.com** — 약관 "문의처" 절과 방침 12항(개인정보 보호책임자 연락처)에 공통 사용. 개인 계정이 아닌 앱 전용 계정이라 실명 노출이 없고, 나중에 도메인 메일로 옮기더라도 구버전 앱 이용자를 위해 이 주소는 계속 살려 둔다.
- **시행일자: 2026년 8월 4일 / August 4, 2026** — 웹 게시일로 잡았다. 출시 예정일로 잡으면 심사 지연 시 어긋나는데, 이 값은 앱에 하드코딩되어 있어 날짜를 고치려면 앱을 다시 배포해야 한다. 게시일로 두면 심사 중 리뷰어가 방침 URL을 열었을 때 이미 시행 중인 문서를 보게 된다.

**채워야 할 플레이스홀더는 모두 해소됐다.**

## 비회원(게스트) 데이터 취급 — 문서를 코드에 맞춘 근거

코드 감사 결과, **로그인하지 않은 이용자의 가계부 데이터도 서버에 저장된다.**

| 단계 | 근거 |
| --- | --- |
| 게스트 저장 | `AddExpenseViewModel.swift` → `SyncEngine.performLocalWrite` → `schedulePushPending()` |
| 익명 세션 발급 | `SyncEngine.performPush()` → `AuthService.ensureIdentity()` → `signInAnonymously()` |
| push 통과 | `SyncEngine.performPush()`의 `guard let memberID = authProvider.currentUserID` — 익명 여부를 걸러내지 않는다 |
| 서버 수용 | 백엔드 `SecurityConfig.java`의 `.anyRequest().authenticated()` — 익명 JWT를 구분하지 않는다 |

초기 문안은 "비회원 데이터는 기기에만 저장된다"고 적었으나 사실과 달라, 2026-08-01 문서를 실동작에 맞춰 고쳤다(약관 제2조 4항·제4조 2항·제5조 1항·제12조 4항·제13조 1항, 방침 2-라·3항·5항·6항·8항·9항).

### 로그인 시 귀속은 경로에 따라 갈린다

리뷰에서 잡힌 사항이다. 게스트가 로그인할 때 익명 식별자의 운명은 두 갈래다(`LoginViewModel.performLinkIdentity` / `performConflictSignIn`).

| 경로 | 동작 | 익명 식별자로 서버에 올라간 사본 |
| --- | --- | --- |
| 해당 소셜 계정으로 **처음** 로그인 | `linkIdentity` 성공 — 익명 UUID가 그대로 회원 UUID가 된다 | 그대로 회원 데이터가 된다 |
| 이미 그 소셜 계정의 **회원** | `identityAlreadyExists` → `performConflictSignIn` → 기존 계정 로그인, **UUID가 바뀐다** | 익명 UUID에 남아 고아가 된다 |

두 번째 경로에서 로컬 pending 행은 `finishAccountSwitch` 후 새 계정으로 push되지만, 이미 익명 UUID로 올라간 사본은 남는다. 이 사본은 계정과 연결되지 않아 앱 내 삭제로 지워지지 않는다. 방침 2-라·3항 3호·8항 2호에 이 사실과 보호책임자 요청 경로를 명시했다.

### 남은 운영 과제

- **고아 익명 데이터**: 위 두 번째 경로, 그리고 게스트가 로그인하지 않고 앱을 삭제하는 경우 서버의 익명 데이터를 이용자와 연결할 방법이 없다. 방침은 자동 파기 기간을 약속하지 않고 "이용자의 삭제 요청 시 지체 없이 파기"로 적었으므로, **보호책임자 앞으로 삭제 요청이 오면 수동으로 처리할 수 있어야 한다**(요청자의 데이터 특정 방법을 운영 절차로 정해둘 것). 정리 배치를 도입하면 보유기간을 명시하는 쪽으로 바꿀 수 있다.
- **App Store 개인정보 라벨**: 로그인 없이도 가계부 데이터가 수집되므로, App Store Connect의 App Privacy에 게스트 수집을 반영해야 한다. "로그인 사용자만 수집"으로 신고하면 사실과 다르다.

## 소셜로그인 수집 항목 — 코드로 확정

방침 2-가의 수집 항목이 실제와 맞는지 확인한 결과다.

| 제공자 | 요청 스코프 | 근거 |
| --- | --- | --- |
| 구글 | `email` + `profile` (항상) | 앱은 `signInWithOAuth(provider:.google, redirectTo:)`에 스코프를 넘기지 않는다. Supabase Auth의 Google 프로바이더가 기본 `[]string{"email", "profile"}`을 쓰고, 클라이언트가 넘긴 스코프는 여기에 **append**된다(replace가 아니다). 즉 앱에서 `email`만 받도록 줄일 수 없다. |
| 애플 | `.email`, `.fullName` | `AppleIDTokenProvider.swift`의 `request.requestedScopes` |

`profile` 스코프 때문에 Google ID 토큰에 `name`과 `picture`가 실려 오고, Supabase가 이를 `user_metadata`에 보관한다. **앱 자신은 `currentUserEmail`만 읽고 이름·프로필 사진을 쓰지 않지만**, 수탁자(Supabase)가 보관하는 이상 운영자가 수집하는 것이므로 방침에 기재해야 한다. 따라서 2-가의 "이메일 주소, 이름, 프로필 사진 URL, 구글 계정 고유 식별자"는 **그대로 두는 것이 맞다** — 줄여 적으면 과소 고지가 된다.

## 게시본과 앱 표시본의 드리프트 방지

`woni_appTests/LegalTextParityTests.swift`가 `docs/legal/terms-of-service.{ko,en}.md`의 번호 붙은 조 전문을 `TermsOfServiceText`와 문자 단위로 대조한다. UITest 픽스처는 조 제목과 문단 개수만 세므로 본문 오기를 잡지 못한다(실제로 영문 제4조 2항이 한 번 어긋났다).

마크다운을 테스트 번들 리소스로 넣으면 `project.pbxproj`를 고쳐야 해서, `#filePath`로 소스 트리를 직접 읽는다. 게시본에만 있는 "문의처"·"부칙"은 대조 대상에서 제외하므로, 나중에 그 두 조항을 앱에 넣어도 테스트는 깨지지 않는다.

## 백엔드 리전 확정 시 추가 작업

개인정보가 두 곳으로 나뉜다.

- **Supabase** — 계정 정보(이메일·이름·식별자) 및 익명 식별자
- **백엔드 클라우드** — 가계부 데이터(`ledger_entry`)

현재 개인정보처리방침 6항(국외 이전) 표에는 Supabase 한 줄만 있다.

- 백엔드를 **서울 리전**에 배포하면 → 추가 작업 없음. 위탁(5항)에만 남는다.
- 백엔드를 **해외 리전**에 배포하면 → 6항 표에 백엔드 클라우드 한 줄을 추가하고, 이전 항목에 가계부 데이터를 명시해야 한다.

## 문서와 코드가 일치해야 하는 지점

문안은 출시 후 상태를 기준으로 작성했다. 아래가 구현되지 않으면 문서가 사실과 달라진다.

| 문서 | 요구되는 구현 상태 |
| --- | --- |
| 방침 9항 1호 "모든 통신은 HTTPS/TLS" | `Networking/APIConfig.swift`가 `http://localhost:8080`이다. 프로덕션 HTTPS 엔드포인트로 교체해야 한다. |
| 약관 제12조 1항 "설정 화면의 탈퇴 기능" | 현재 "준비 중" 알럿만 있다. 탈퇴 기능 구현 필요(Apple App Review 5.1.1(v) 요구사항이기도 하다). |
| 약관 제12조 3항 "탈퇴 시 기기 데이터도 삭제" | 탈퇴 구현 시 서버 삭제와 함께 로컬 GRDB DB까지 삭제해야 한다. |
| 약관 제12조 4항 · 방침 8항 3호 "비회원은 앱 내 삭제로 서버에서도 삭제" | 반영 완료 — `SyncEngine.performPush()`가 `sync_delete_queue`를 `ledgerService.deleteSynced`로 서버에 전파한다. |
| 약관 제4조 1항 "소셜로그인 과정에서 약관·방침에 동의" | 반영 완료 — `LoginSheet`에 동의 문구와 약관·방침 링크를 넣었다. |
| 약관 제4조 2항 "약관·방침 전문은 [설정]에서 확인 가능" | 약관은 반영 완료. **방침은 아직 "준비 중" 한 줄이라 미충족** — 아래 반영 상태 참조. |

## 앱 반영 상태

| 대상 | 상태 |
| --- | --- |
| 약관·방침 열람 | **Notion 게시본 링크** — 설정 화면과 로그인 시트의 문서 버튼이 `SafariView`(인앱 브라우저) 시트로 아래 URL을 연다(`LegalContent.termsOfServiceLink` / `.privacyPolicyLink`). |
| 로그인 동의 문구 | **반영 완료** — `LoginSheet`에 문구 + 약관·방침 링크. |

앱 내장 전문(`TermsOfServiceText.swift`)과 `LegalTextView`, `LegalTextParityTests`는 되돌릴 여지를 두려고 남겨 두었으나 **현재 어느 화면에서도 쓰이지 않는다**. 방침 전문을 앱에 넣는 방안은 링크 방식 채택으로 보류했다 — 넣으려면 표 4개(2항 수집 항목, 5항 위탁, 6항 국외 이전, 13항 권익침해 구제기관)를 `LegalClause`가 어떻게 렌더링할지부터 정해야 한다.

### 게시 URL

| 문서 | URL |
| --- | --- |
| Woni 지원 · Support (공개 루트) | `https://balanced-owner-32e.notion.site/Woni-Support-3b27165d1c3281e2b094cb2dda189654` |
| 개인정보처리방침(한) | `https://balanced-owner-32e.notion.site/3b27165d1c3281a29604c6b390877b34` |
| Privacy Policy(영) | `https://balanced-owner-32e.notion.site/Privacy-Policy-English-3b27165d1c32810ebf0ecbc7fa26b3fa` |
| 서비스 이용약관(한) | `https://balanced-owner-32e.notion.site/3b27165d1c32811cbb88ef49f8811016` |
| Terms of Service(영) | `https://balanced-owner-32e.notion.site/Terms-of-Service-English-3b27165d1c3281f3ac4eead114f26733` |

Notion 트리는 `Woni 앱 기획서 → Woni 지원 · Support` 아래에 문서 4개가 달린 구조이며, 공개 설정은 "Woni 지원" 한 곳에서만 켠다(상위에서 켜면 기획서·개발 메모까지 전부 공개된다).

**원본은 이 저장소의 `*.md`이고 Notion은 게시본이다.** 자동 동기화가 없으므로 문서를 고치면 Notion 페이지도 함께 갱신해야 하며, 어긋나도 테스트로는 잡히지 않는다. 페이지를 삭제하거나 비공개로 돌리면 앱에서 문서를 볼 수 없고 App Store에 등록한 URL도 죽는다.

영문 문서에 한글 실명이 섞이지 않도록 사람 이름은 모두 로마자로 적는다. 명의자는 `Ji Young Lee`(영문 약관 제1조,
영문 방침 서두), 실무자는 `Jungkuk Lee`(영문 문의처, 영문 보호책임자)다.
명의자는 여권 표기(`JI YOUNG LEE`)를 확인해 반영했다 — 계약 당사자이자 App Store 판매자라 법적 신원과 일치해야 하기 때문이며,
여권이 전부 대문자여도 문서에는 계약서 관례대로 Title Case로 적는다. **실무자 표기는 여권 확인을 거치지 않았다**(문의 창구
표시용이라 법적 신원 일치가 요구되지 않는다). 표기를 바꿀 때는 `TermsOfServiceText.english`와 `*.en.md`를 함께 고친다.

## 게시 절차

1. ~~플레이스홀더를 채운다~~ — 완료.
2. ~~Notion에 한국어·영어 페이지를 만들고 웹에 게시해 공개 URL을 얻는다~~ — 완료(위 "게시 URL").
3. **App Store Connect 등록** — Privacy Policy URL은 로컬라이제이션별로 한/영을 각각 넣고, Support URL에는 "Woni 지원 · Support" 페이지 URL을 넣는다(`mailto:`는 받지 않는다). App Privacy 항목은 위 "App Store 개인정보 라벨" 주의사항에 맞춰 작성한다.
4. **문서를 고칠 때마다** `*.md` → Notion 페이지 순으로 갱신한다.
