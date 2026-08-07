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
- **시행일자 — 약관 2026년 8월 5일 / 방침 2026년 8월 8일**(둘 다 8월 4일 제정, 8월 5일 개정. 방침만 8월 8일 재개정) — 게시일로 잡는다. 출시 예정일로 잡으면 심사 지연 시 어긋나지만, 게시일로 두면 심사 중 리뷰어가 방침 URL을 열었을 때 이미 시행 중인 문서를 보게 된다. 시행일자는 게시본(마크다운·Notion)에만 있고 **앱 표시본에는 들어가지 않는다** — `TermsOfServiceText`는 번호 붙은 조항만 담고 문의처·부칙은 제외하며, `LegalTextParityTests`도 조항만 대조한다. 따라서 시행일 변경은 앱 재배포와 무관하다.
- **개정 이력** — 2026년 8월 8일, 계정 연동 경로 제거(`c3a9871`)와 익명 계정 정리 도입(`dfc8671`)에 맞춰 방침 2-라를 단일 경로로 다시 썼고, 3항 2호를 그에 맞게 고쳤다(영문은 3항 3호·8항 2호에서 "제2조 라목" 참조 절의 위치를 한국어와 맞췄다). 3항 3호·8항 2호의 "제2조 라목에 따라 남게 된 사본"이라는 포괄 참조는 종전 그대로 두었다 — 라목이 잔존 사유를 두 갈래로 넓힌 이상 이 문구가 자동으로 둘 다 받는다. 방침만 바뀌었고 약관은 손대지 않았다(약관은 이관·삭제 동작을 서술하지 않는다). 시행일자는 게시일 원칙에 따라 8월 8일로 옮겼다.
- **개정 이력** — 2026년 8월 5일, 약관 제12조 제2항과 방침 7항 3호에 백업본 잔존 기간(최대 3개월)을 명시했다. 근거는 백엔드 백업 정책인 세대 보관(일7·주4·월3)이다. 종전 문구("삭제된 데이터는 복구할 수 없습니다"만)는 백업본 잔존과 어긋났다.

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

### 로그인 시 귀속은 한 갈래다 — 이관 후 익명 계정 삭제

**2026-08-08 갱신.** 종전에는 계정 연동(`linkIdentity`) 성공 여부에 따라 익명 식별자의 운명이 두 갈래로 갈렸고, "이미 그 소셜 계정의 회원"인 경로에서는 익명 UUID로 올라간 사본이 고아로 남았다. 이 분기가 기기마다 다른 결과를 만드는 원인이어서 `c3a9871`에서 연동 경로를 제거하고 로그인을 한 갈래로 통일했다(`performLinkIdentity`·`performConflictSignIn`·`identityAlreadyExists` 모두 삭제됨).

현재 동작은 다음 한 경로뿐이다.

| 단계 | 동작 | 근거 |
| --- | --- | --- |
| 인증 | 언제나 해당 소셜 계정의 회원 UUID로 로그인한다. 활성 익명 세션과 병합하지 않는다 | `AuthService.signIn` |
| 이관 | 로컬 전 행을 `pendingPush`로 되돌려 새 계정으로 다시 올린다 | `TransactionRepository.resetSyncStateForAccountSwitch` → `SyncEngine.finishAccountSwitch` |
| 정리 | **이관이 확인되면** 캡처해 둔 익명 토큰으로 익명 계정을 삭제한다 | `LoginViewModel.deleteAnonymousAccountIfFullyMigrated` |

정리는 네 겹 게이트를 전부 통과할 때만 실행된다: ①로그인 전 신원이 익명 ②신원이 실제로 바뀜 ③`sync.hasPendingPush() == false` ④`finishAccountSwitch` 성공. ③이 "미푸시 0"을 실제로 보장하는 것은 두 함수가 나눠 맡기 때문이다 — `finishAccountSwitch`가 `pushPending()`을 await해 재업로드를 끝내고 돌아온 **뒤에**, `deleteAnonymousAccountIfFullyMigrated`가 `hasPendingPush()`로 남은 행을 다시 조회한다. `performPush`는 실패를 삼켜 반환값만으로는 성공 여부를 알 수 없으므로, 이 재조회가 없으면 ④만으로는 이관 완료를 판정할 수 없다. 즉 **오프라인 등으로 이관이 덜 끝났으면 삭제는 자동으로 보류되고 익명 계정이 보존된다** — 데이터 유실보다 사본 잔존을 택한 설계다.

삭제는 `DELETE /api/v1/members/me` 한 번이고, 서버는 `auth.users` 행만 지운다. 가계부 데이터는 `ledger_entry.member_id → auth.users(id) ON DELETE CASCADE`(`V10__ledger_member_fk_auth_users.sql`)로 함께 사라진다.

삭제 실패는 **조용히 포기한다**(재시도 큐 없음, 사용자 미통지). 따라서 사본은 두 경우에 익명 식별자에 남는다: ①이번 구조에서 삭제 호출이 실패한 경우 ②위 종전 방식에서 이미 고아가 된 사본. 방침 2-라는 이 둘을 모두 열거하고, 3항 3호·8항 2호가 "제2조 라목에 따라 남게 된 사본"으로 둘 다 받아 보호책임자 요청 경로로 연결한다.

### 남은 운영 과제

- **고아 익명 데이터**: 위 두 잔존 경로(종전 방식이 남긴 사본, 삭제 호출 실패), 그리고 게스트가 로그인하지 않고 앱을 삭제하는 경우 서버의 익명 데이터를 이용자와 연결할 방법이 없다. 방침은 자동 파기 기간을 약속하지 않고 "이용자의 삭제 요청 시 지체 없이 파기"로 적었으므로, **보호책임자 앞으로 삭제 요청이 오면 수동으로 처리할 수 있어야 한다**(요청자의 데이터 특정 방법을 운영 절차로 정해둘 것). 정리 배치를 도입하면 보유기간을 명시하는 쪽으로 바꿀 수 있다.
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
