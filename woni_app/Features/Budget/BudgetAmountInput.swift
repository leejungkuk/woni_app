//
//  BudgetAmountInput.swift
//  woni_app
//

import Foundation

/// 예산 금액 칸에 키 하나를 반영한 결과. `BudgetAmountTextField` 가 이대로 칸 글자를 확정한다.
enum BudgetAmountCommit: Equatable {
    /// 칸 글자를 이것으로 바꾼다.
    case accepted(String)
    /// 칸 상한(`AddExpenseViewModel.maximumAmount`)을 넘어 받지 않았다 — 칸이 상한 신호를 올린다.
    case overLimit
    /// 칸 밖의 판정(카테고리 합 상한 등)이 받지 않았다 — 토스트는 거절한 쪽이 이미 띄웠다.
    case rejected
}

/// 예산 금액 칸의 글자 ↔ 금액(스펙 §2.4). 거래 칸(`AmountInputSection.acceptedInput`)과 `0` 의 뜻이 다르다 —
/// 예산 칸은 빈칸 = 몫 없음(nil), 0 = 0원 몫이다. 그래서 빈칸에서 `0` 을 치면 0원으로 확정하고,
/// 빈칸은 지우기로만 된다. 이어 치면 거래 칸과 같은 오른쪽부터 채우기다(소수 통화 "0.00" 에서 5 → "0.05").
enum BudgetAmountInput {
    /// 키 입력 하나(바꿀 범위·넣을 글자)를 반영한 결과. 상한을 넘으면 nil(입력 거절).
    static func apply(
        _ replacement: String,
        in range: NSRange,
        of text: String,
        decimalPlaces: Int
    ) -> (text: String, amount: Decimal?)? {
        let typesDigit = replacement.contains(where: isASCIIDigit)
        // 숫자를 넣지도 지우지도 않는 키(전각·원문자 숫자 등)는 칸을 바꾸지 않는다.
        guard let editedRange = Range(range, in: text), typesDigit || range.length > 0 else {
            return resolve(text, keepsZero: true, decimalPlaces: decimalPlaces)
        }
        let candidate = text.replacingCharacters(in: editedRange, with: replacement)
        return resolve(candidate, keepsZero: typesDigit, decimalPlaces: decimalPlaces)
    }

    /// 칸 하나의 키 확정 순서. 칸 상한을 넘으면 `accept` 를 부르지 않고 `.overLimit`,
    /// 아니면 새 값을 `accept` 에 넘겨 받아들일 때만 새 글자로 확정한다.
    /// 글자가 그대로인 키(쉼표 지우기·숫자 아닌 글자)도 `accept` 를 부르지 않는다 — 부르면 자동 합계 전체 칸에
    /// 직접 입력이 생겨 "카테고리 합계" 안내가 사라지고 초안이 바뀐 것이 된다.
    static func commit(
        _ replacement: String,
        in range: NSRange,
        of text: String,
        decimalPlaces: Int,
        accept: (Decimal?) -> Bool
    ) -> BudgetAmountCommit {
        guard let result = apply(replacement, in: range, of: text, decimalPlaces: decimalPlaces) else {
            return .overLimit
        }
        guard result.text != text else {
            return .accepted(text)
        }
        return accept(result.amount) ? .accepted(result.text) : .rejected
    }

    /// 값 → 칸 글자(통화 전환·불러오기처럼 밖에서 값이 바뀔 때). nil → "".
    static func text(for amount: Decimal?, decimalPlaces: Int) -> String {
        guard let amount else {
            return ""
        }
        // `CurrencyFormat.string` 과 같은 모양 — 기기 로케일과 무관하게 천 단위 쉼표·점 소수·ASCII 숫자.
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.roundingMode = .down
        formatter.minimumFractionDigits = decimalPlaces
        formatter.maximumFractionDigits = decimalPlaces
        return formatter.string(for: amount) ?? "\(amount)"
    }

    /// 글자의 숫자만 오른쪽부터 채워 읽는다. 쉼표·소수점은 버린다 — 자리는 통화 자릿수가 정한다.
    /// 숫자가 모두 0 이면 `keepsZero`(0 을 쳤다)일 때 0원, 아니면(지웠다) 빈칸이다.
    private static func resolve(
        _ candidate: String,
        keepsZero: Bool,
        decimalPlaces: Int
    ) -> (text: String, amount: Decimal?)? {
        let digits = candidate.filter(isASCIIDigit)
        let significant = String(digits.drop { $0 == "0" })
        guard !significant.isEmpty else {
            return keepsZero && !digits.isEmpty ? (text(for: 0, decimalPlaces: decimalPlaces), 0) : ("", nil)
        }
        // 숫자가 Decimal 이 담지 못할 만큼 길면(붙여 넣기) nil — 상한을 넘은 것과 같다.
        guard let integer = Decimal(string: significant, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        let amount = Decimal(sign: .plus, exponent: -decimalPlaces, significand: integer)
        guard amount <= AddExpenseViewModel.maximumAmount else {
            return nil
        }
        return (text(for: amount, decimalPlaces: decimalPlaces), amount)
    }

    /// `Character.isNumber` 는 ①·１ 같은 비ASCII 숫자도 통과시킨다.
    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}
