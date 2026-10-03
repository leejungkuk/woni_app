//
//  BudgetAmountInputTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 예산 금액 칸의 키 입력(스펙 §2.4). 빈칸 = 몫 없음(nil), 0 = 0원 몫이다 — 거래 칸과 `0` 의 뜻이 다르다.
/// KRW 는 0자리, USD 는 2자리다.
@MainActor
struct BudgetAmountInputTests {
    private static let krw = 0
    private static let usd = 2

    @Test("빈칸에서 0 을 치면 0원으로 확정된다 — 0 이 아닌 첫 입력은 오른쪽부터 채운다")
    func zeroOnEmptyConfirmsZero() throws {
        let krwZero = try typed("0", after: "", decimalPlaces: Self.krw)
        #expect(krwZero.text == "0")
        #expect(krwZero.amount == 0)

        let usdZero = try typed("0", after: "", decimalPlaces: Self.usd)
        #expect(usdZero.text == "0.00")
        #expect(usdZero.amount == 0)

        let usdFive = try typed("5", after: "", decimalPlaces: Self.usd)
        #expect(usdFive.text == "0.05")
        #expect(usdFive.amount == Decimal(string: "0.05"))

        let krwFive = try typed("5", after: "", decimalPlaces: Self.krw)
        #expect(krwFive.text == "5")
        #expect(krwFive.amount == 5)
    }

    @Test("0원 확정 뒤 이어 치면 오른쪽부터 채우고, 0 을 더 쳐도 빈칸이 되지 않는다")
    func typingAfterZeroFillsFromRight() throws {
        let usdFive = try typed("5", after: "0.00", decimalPlaces: Self.usd)
        #expect(usdFive.text == "0.05")
        #expect(usdFive.amount == Decimal(string: "0.05"))
        let usdFifty = try typed("0", after: usdFive.text, decimalPlaces: Self.usd)
        #expect(usdFifty.text == "0.50")
        #expect(usdFifty.amount == Decimal(string: "0.50"))

        let krwFive = try typed("5", after: "0", decimalPlaces: Self.krw)
        #expect(krwFive.text == "5")
        #expect(krwFive.amount == 5)
        let krwFifty = try typed("0", after: krwFive.text, decimalPlaces: Self.krw)
        #expect(krwFifty.text == "50")
        #expect(krwFifty.amount == 50)

        let usdStillZero = try typed("0", after: "0.00", decimalPlaces: Self.usd)
        #expect(usdStillZero.text == "0.00")
        #expect(usdStillZero.amount == 0)

        let krwStillZero = try typed("0", after: "0", decimalPlaces: Self.krw)
        #expect(krwStillZero.text == "0")
        #expect(krwStillZero.amount == 0)
    }

    @Test("지우기로 숫자가 모두 0 이 되거나 비면 빈칸이다 — 0 이 아닌 숫자가 남으면 오른쪽부터 당긴다")
    func deletingToZeroDigitsEmpties() throws {
        let usdEmptied = try deletedLast(from: "0.05", decimalPlaces: Self.usd)
        #expect(usdEmptied.text.isEmpty)
        #expect(usdEmptied.amount == nil)

        let krwEmptied = try deletedLast(from: "0", decimalPlaces: Self.krw)
        #expect(krwEmptied.text.isEmpty)
        #expect(krwEmptied.amount == nil)

        let usdShifted = try deletedLast(from: "1.05", decimalPlaces: Self.usd)
        #expect(usdShifted.text == "0.10")
        #expect(usdShifted.amount == Decimal(string: "0.10"))
    }

    @Test("99,999,999 까지는 받고 넘으면 그 키를 거절한다")
    func inputBeyondLimitIsRejected() throws {
        var krw = (text: "", amount: Decimal?.none)
        for key in Array(repeating: "9", count: 8) {
            krw = try typed(key, after: krw.text, decimalPlaces: Self.krw)
        }
        #expect(krw.text == "99,999,999")
        #expect(krw.amount == 99_999_999)

        #expect(apply("9", atEndOf: krw.text, decimalPlaces: Self.krw) == nil)
        #expect(apply("1", atEndOf: "99,999,999.00", decimalPlaces: Self.usd) == nil)
    }

    @Test("ASCII 숫자만 받는다 — 전각·원문자 숫자는 칸을 바꾸지 않는다")
    func nonASCIIDigitsAreIgnored() throws {
        let fullWidth = try typed("１", after: "", decimalPlaces: Self.krw)
        #expect(fullWidth.text.isEmpty)
        #expect(fullWidth.amount == nil)

        let circled = try typed("①", after: "1,000", decimalPlaces: Self.krw)
        #expect(circled.text == "1,000")
        #expect(circled.amount == 1000)

        let ascii = try typed("1", after: "", decimalPlaces: Self.krw)
        #expect(ascii.text == "1")
        #expect(ascii.amount == 1)
    }

    @Test("밖에서 정한 값은 칸 글자로 같은 모양(천 단위 쉼표·통화 자릿수)이 되고, nil 은 빈칸이다")
    func textForAmountRoundTrips() throws {
        #expect(BudgetAmountInput.text(for: 0, decimalPlaces: Self.usd) == "0.00")
        #expect(BudgetAmountInput.text(for: nil, decimalPlaces: Self.usd).isEmpty)
        #expect(BudgetAmountInput.text(for: 1_234_567, decimalPlaces: Self.krw) == "1,234,567")

        let restored = try #require(Decimal(string: "1234.5"))
        let text = BudgetAmountInput.text(for: restored, decimalPlaces: Self.usd)
        #expect(text == "1,234.50")
        let continued = try typed("1", after: text, decimalPlaces: Self.usd)
        #expect(continued.text == "12,345.01")
        #expect(continued.amount == Decimal(string: "12345.01"))
    }

    @Test("칸 밖의 판정이 거절하면 글자를 확정하지 않는다 — 칸 상한을 넘는 키는 판정에 묻지 않는다")
    func ownerRejectionKeepsText() {
        var received: [Decimal?] = []
        let rejected = commit("1", atEndOf: "1,000") { amount in
            received.append(amount)
            return false
        }
        #expect(rejected == .rejected)
        #expect(received == [10001])

        let accepted = commit("1", atEndOf: "1,000") { _ in true }
        #expect(accepted == .accepted("10,001"))

        received = []
        let overLimit = commit("9", atEndOf: "99,999,999") { amount in
            received.append(amount)
            return true
        }
        #expect(overLimit == .overLimit)
        #expect(received.isEmpty)
    }

    // MARK: - 도우미

    private func apply(
        _ key: String,
        atEndOf text: String,
        decimalPlaces: Int
    ) -> (text: String, amount: Decimal?)? {
        let end = NSRange(location: (text as NSString).length, length: 0)
        return BudgetAmountInput.apply(key, in: end, of: text, decimalPlaces: decimalPlaces)
    }

    private func typed(
        _ key: String,
        after text: String,
        decimalPlaces: Int
    ) throws -> (text: String, amount: Decimal?) {
        try #require(apply(key, atEndOf: text, decimalPlaces: decimalPlaces))
    }

    /// 지우기 키 — 캐럿은 늘 끝에 있으므로 마지막 글자 하나를 비운다.
    private func deletedLast(
        from text: String,
        decimalPlaces: Int
    ) throws -> (text: String, amount: Decimal?) {
        let last = NSRange(location: (text as NSString).length - 1, length: 1)
        return try #require(BudgetAmountInput.apply("", in: last, of: text, decimalPlaces: decimalPlaces))
    }

    private func commit(
        _ key: String,
        atEndOf text: String,
        accept: (Decimal?) -> Bool
    ) -> BudgetAmountCommit {
        let end = NSRange(location: (text as NSString).length, length: 0)
        return BudgetAmountInput.commit(key, in: end, of: text, decimalPlaces: Self.krw, accept: accept)
    }
}
