//
//  AmountFieldInputTests.swift
//  woni_appTests
//

import SwiftUI
import Testing
import UIKit
@testable import woni_app

/// 금액 칸 두 개(거래 `AmountTextField` · 예산 `BudgetAmountTextField`)의 커서와 붙여넣기(UI_GUIDE 입력 규칙, 2026-10-04).
/// 판정 함수가 아니라 두 칸의 실제 `Coordinator` delegate 메서드를 부른다 — 판정 함수만 보면 칸에 연결하지 않아도 초록이다.
/// 커서·선택은 key window 에 붙여 편집을 시작한 `UITextField` 로 본다 — 창 없는 칸은 `selectedTextRange` 가 nil 일 수 있다.
@MainActor
struct AmountFieldInputTests {
    private static let text = "300,000"
    private static let end = 7

    // MARK: R1 — 고른 범위가 없으면 커서는 끝

    @Test("BDF.S5-R1 선택이 바뀌어 앞·가운데에 선 커서는 끝으로 간다", arguments: FieldKind.allCases)
    func caretMovesToEndOnSelectionChange(kind: FieldKind) throws {
        for offset in [0, 3] {
            let probe = FieldProbe(kind)
            try withEditingField(Self.text) { field in
                try place(field, at: offset ..< offset)
                probe.changeSelection(field)
                #expect(selection(of: field) == Self.end ..< Self.end, "\(kind) 칸 \(offset) 자리 커서는 끝으로 가야 한다")
            }
        }
    }

    @Test("BDF.S5-R1 편집을 시작할 때 가운데에 선 커서도 끝으로 간다", arguments: FieldKind.allCases)
    func caretMovesToEndOnBeginEditing(kind: FieldKind) throws {
        let probe = FieldProbe(kind)
        try withEditingField(Self.text) { field in
            try place(field, at: 3 ..< 3)
            probe.beginEditing(field)
            #expect(selection(of: field) == Self.end ..< Self.end, "\(kind) 칸은 편집을 시작할 때 커서를 끝에 둬야 한다")
        }
    }

    @Test("BDF.S5-R1 실패 짝: 이미 끝이거나 빈 칸이면 커서를 옮기지 않는다", arguments: FieldKind.allCases)
    func caretAlreadyAtEndIsNotMoved(kind: FieldKind) throws {
        for (text, end) in [(Self.text, Self.end), ("", 0)] {
            let probe = FieldProbe(kind)
            try withEditingField(text) { field in
                try place(field, at: end ..< end)
                let sets = field.selectionSetCount
                probe.beginEditing(field)
                probe.changeSelection(field)
                #expect(field.selectionSetCount == sets, "\(kind) 칸 \"\(text)\" 끝 커서를 다시 옮기면 선택 변경이 되불린다")
                #expect(selection(of: field) == end ..< end)
            }
        }
    }

    // MARK: R2 — 고른 범위는 그대로

    @Test("BDF.S5-R2 모두·일부 고른 범위는 편집 시작·선택 변경 때 그대로다", arguments: FieldKind.allCases)
    func selectedRangeIsKept(kind: FieldKind) throws {
        for range in [0 ..< Self.end, 1 ..< 3] {
            let probe = FieldProbe(kind)
            try withEditingField(Self.text) { field in
                try place(field, at: range)
                let sets = field.selectionSetCount
                probe.beginEditing(field)
                probe.changeSelection(field)
                #expect(selection(of: field) == range, "\(kind) 칸에서 고른 \(range) 는 그대로여야 한다")
                #expect(field.selectionSetCount == sets, "\(kind) 칸이 고른 \(range) 를 다시 정하면 안 된다")
            }
        }
    }

    @Test("BDF.S5-R2 실패 짝: 같은 자리라도 길이 0 이면 끝으로 간다", arguments: FieldKind.allCases)
    func collapsedCaretAtRangeStartMoves(kind: FieldKind) throws {
        let probe = FieldProbe(kind)
        try withEditingField(Self.text) { field in
            try place(field, at: 1 ..< 1)
            probe.changeSelection(field)
            #expect(selection(of: field) == Self.end ..< Self.end, "\(kind) 칸 1 자리 커서는 끝으로 가야 한다")
        }
    }

    // MARK: R3 — ASCII 숫자 없는 글은 무시

    @Test("BDF.S5-R3 숫자 없는 글(abc·전각·이모지·점)은 끝에 넣어도 모두 고른 뒤 넣어도 칸을 바꾸지 않는다",
          arguments: FieldKind.allCases)
    func nonDigitReplacementIsIgnored(kind: FieldKind) throws {
        for replacement in ["abc", "１２３", "😀", "."] {
            for range in [Self.end ..< Self.end, 0 ..< Self.end] {
                let probe = FieldProbe(kind, text: Self.text, amount: 300_000)
                try withEditingField(Self.text) { field in
                    try place(field, at: range)
                    let changes = probe.change(field, range: range, replacement: replacement)
                    let label = "\(kind) 칸 \(range) 에 \"\(replacement)\""
                    #expect(changes == false, "\(label) — UIKit 이 글자를 바꾸게 두면 안 된다")
                    #expect(field.text == Self.text, "\(label) — 칸 글자가 그대로여야 한다")
                    #expect(selection(of: field) == range, "\(label) — 선택 범위가 그대로여야 한다")
                    #expect(probe.text == Self.text, "\(label) — 거래 칸 글자 바인딩이 그대로여야 한다")
                    #expect(probe.amount == 300_000, "\(label) — 금액이 그대로여야 한다")
                    #expect(probe.acceptCount == 0, "\(label) — 예산 칸은 새 값을 넘기지 않아야 한다")
                }
            }
        }
    }

    @Test("BDF.S5-R3 실패 짝: 범위를 지우는 빈 글은 지우고 숫자 5 는 칸을 바꾼다", arguments: FieldKind.allCases)
    func deletionAndDigitStillChange(kind: FieldKind) throws {
        let deleting = FieldProbe(kind, text: Self.text, amount: 300_000)
        try withEditingField(Self.text) { field in
            try place(field, at: 0 ..< Self.end)
            _ = deleting.change(field, range: 0 ..< Self.end, replacement: "")
            #expect(field.text?.isEmpty == true, "\(kind) 칸에서 고른 범위를 지우면 비어야 한다")
            #expect(deleting.amount == kind.emptyAmount)
        }

        let typing = FieldProbe(kind, text: Self.text, amount: 300_000)
        try withEditingField(Self.text) { field in
            try place(field, at: Self.end ..< Self.end)
            _ = typing.change(field, range: Self.end ..< Self.end, replacement: "5")
            #expect(field.text == "3,000,005", "\(kind) 칸 끝에 5 를 넣으면 붙어야 한다")
            #expect(typing.amount == 3_000_005)
        }
    }
}

// MARK: R4·R5 — 숫자가 섞인 글

extension AmountFieldInputTests {
    /// 위 표(배경 D7): 0자리 통화는 첫 `.` 뒤를 버리고, 숫자는 ASCII `0-9` 만 센다.
    private static let zeroDecimalPastes: [(paste: String, amount: String)] = [
        ("1.2.3", "1"), ("-500", "500"), (" 7 7 ", "77"), ("1,234", "1234"), ("12a34", "1234"), ("1１2", "12")
    ]

    @Test("BDF.S5-R4 0자리 통화에서 숫자가 섞인 글은 두 칸이 거래 칸 규칙으로 같은 금액이 된다")
    func zeroDecimalMixedPasteMatchesAcrossFields() throws {
        for (paste, expected) in Self.zeroDecimalPastes {
            let amounts = try FieldKind.allCases.map { kind in
                try pasted(paste, into: "", kind: kind, currencyCode: "KRW")
            }
            #expect(amounts == [Decimal(string: expected), Decimal(string: expected)], "KRW \"\(paste)\"")
        }
        for kind in FieldKind.allCases {
            let appended = try pasted("2.5", into: Self.text, kind: kind, currencyCode: "KRW")
            #expect(appended == 3_000_002, "\(kind) 칸 300,000 끝에 2.5 — 첫 . 뒤를 버려야 한다")
        }
    }

    @Test("BDF.S5-R4 실패 짝: 소수 통화는 . 뒤 숫자를 버리지 않고 오른쪽부터 채운다")
    func decimalCurrencyKeepsDigitsAfterDot() throws {
        for (paste, expected) in [("1.2.3", "1.23"), ("12.5", "1.25")] {
            let amounts = try FieldKind.allCases.map { kind in
                try pasted(paste, into: "", kind: kind, currencyCode: "USD")
            }
            #expect(amounts == [Decimal(string: expected), Decimal(string: expected)], "USD \"\(paste)\"")
        }
    }

    @Test("BDF.S5-R5 예산 칸 빈칸에 0·000 을 넣으면 0원이다(빈칸 아님)")
    func budgetZeroPasteConfirmsZero() {
        let empty = NSRange(location: 0, length: 0)
        for paste in ["0", "000"] {
            var received: [Decimal?] = []
            let commit = BudgetAmountInput.commit(paste, in: empty, of: "", decimalPlaces: 0) {
                received.append($0)
                return true
            }
            #expect(commit == .accepted("0"), "\"\(paste)\" 은 0원 글자여야 한다")
            #expect(received == [0], "\"\(paste)\" 은 0원 몫이어야 한다")
        }
    }

    @Test("BDF.S5-R5 실패 짝: 숫자를 다 지우면 빈칸이고 상한을 넘는 붙여넣기는 거절한다")
    func budgetEmptyAndOverLimitPaste() {
        var received: [Decimal?] = []
        let all = NSRange(location: 0, length: (Self.text as NSString).length)
        let cleared = BudgetAmountInput.commit("", in: all, of: Self.text, decimalPlaces: 0) {
            received.append($0)
            return true
        }
        #expect(cleared == .accepted(""))
        #expect(received == [nil], "숫자를 다 지우면 몫 없음(nil)이어야 한다")

        received = []
        let empty = NSRange(location: 0, length: 0)
        let overLimit = BudgetAmountInput.commit("999999999", in: empty, of: "", decimalPlaces: 0) {
            received.append($0)
            return true
        }
        #expect(overLimit == .overLimit)
        #expect(received.isEmpty, "상한을 넘으면 칸 밖의 판정에 묻지 않는다")
        let atLimit = BudgetAmountInput.commit("99999999", in: empty, of: "", decimalPlaces: 0) { _ in true }
        #expect(atLimit == .accepted("99,999,999"))
    }

    /// `text` 가 든 칸 끝에 `paste` 를 넣고 칸이 밖으로 넘긴 금액.
    private func pasted(_ paste: String, into text: String, kind: FieldKind, currencyCode: String) throws -> Decimal? {
        let probe = FieldProbe(kind, currencyCode: currencyCode, text: text)
        let field = UITextField()
        field.text = text
        let end = (text as NSString).length
        _ = probe.change(field, range: end ..< end, replacement: paste)
        return probe.amount
    }
}

// MARK: - 도우미

enum FieldKind: CaseIterable, CustomStringConvertible {
    case entry
    case budget

    var description: String {
        switch self {
        case .entry: "거래"
        case .budget: "예산"
        }
    }

    /// 다 지운 칸의 금액 — 거래 칸은 0, 예산 칸은 몫 없음(nil).
    var emptyAmount: Decimal? {
        switch self {
        case .entry: 0
        case .budget: nil
        }
    }
}

/// 칸 하나의 실제 `Coordinator` 와 칸이 밖으로 넘긴 값(거래 칸 `text`·`amount` 바인딩, 예산 칸 `onAmountChange`).
@MainActor
private final class FieldProbe {
    var text: String
    var amount: Decimal?
    private(set) var acceptCount = 0
    private var entry: AmountTextField.Coordinator?
    private var budget: BudgetAmountTextField.Coordinator?

    init(_ kind: FieldKind, currencyCode: String = "KRW", text: String = "", amount: Decimal? = nil) {
        self.text = text
        self.amount = amount
        switch kind {
        case .entry:
            entry = AmountTextField.Coordinator(parent: AmountTextField(
                text: Binding(
                    get: { [unowned self] in self.text },
                    set: { [unowned self] in self.text = $0 }
                ),
                amount: Binding(
                    get: { [unowned self] in self.amount ?? 0 },
                    set: { [unowned self] in self.amount = $0 }
                ),
                isFocused: .constant(false),
                currencyCode: currencyCode,
                onMaximumAmountExceeded: {}
            ))
        case .budget:
            budget = BudgetAmountTextField.Coordinator(parent: BudgetAmountTextField(
                onAmountChange: { [unowned self] newAmount in
                    self.acceptCount += 1
                    self.amount = newAmount
                    return true
                },
                isFocused: .constant(false),
                displayAmount: amount,
                decimalPlaces: CurrencyFormat.decimalPlaces(for: currencyCode),
                style: .line,
                isEnabled: true,
                accessibilityIdentifier: "",
                emptyAccessibilityValue: "",
                onLimitExceeded: {},
                onEditingEnded: {}
            ))
        }
    }

    func beginEditing(_ field: UITextField) {
        entry?.textFieldDidBeginEditing(field)
        budget?.textFieldDidBeginEditing(field)
    }

    func changeSelection(_ field: UITextField) {
        entry?.textFieldDidChangeSelection(field)
        budget?.textFieldDidChangeSelection(field)
    }

    func change(_ field: UITextField, range: Range<Int>, replacement: String) -> Bool {
        let nsRange = NSRange(location: range.lowerBound, length: range.count)
        if let entry {
            return entry.textField(field, shouldChangeCharactersIn: nsRange, replacementString: replacement)
        }
        return budget?.textField(field, shouldChangeCharactersIn: nsRange, replacementString: replacement) ?? true
    }
}

/// 선택을 정한 횟수를 센다 — 이미 끝인 커서를 다시 옮기는지(되부름 고리) 본다.
private final class SelectionCountingField: UITextField {
    private(set) var selectionSetCount = 0

    override var selectedTextRange: UITextRange? {
        didSet {
            selectionSetCount += 1
        }
    }
}

/// key window 에 붙여 편집을 시작한 칸으로 `body` 를 돈다. delegate 는 붙이지 않는다 — 선택을 넣는 순간 UIKit 이
/// delegate 를 불러 버리면 넣은 자리를 먼저 확인할 수 없다. 끝나면 원래 key window 를 되돌린다 —
/// key window 가 하나라고 전제하는 테스트(`PresentationAnchorTests`)와 섞이지 않게.
@MainActor
private func withEditingField(_ text: String, _ body: (SelectionCountingField) throws -> Void) throws {
    let scene = try #require(
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive },
        "테스트 호스트 앱의 전면 scene 이 있어야 칸을 key window 에 붙일 수 있다"
    )
    let previousKeyWindow = scene.keyWindow
    let window = UIWindow(windowScene: scene)
    let root = UIViewController()
    window.rootViewController = root
    let field = SelectionCountingField(frame: CGRect(x: 16, y: 120, width: 320, height: 44))
    field.keyboardType = .numberPad
    field.text = text
    root.view.addSubview(field)
    window.makeKeyAndVisible()
    defer {
        field.resignFirstResponder()
        window.isHidden = true
        previousKeyWindow?.makeKey()
    }
    try #require(window.isKeyWindow, "칸을 붙인 창이 key window 여야 한다")
    try #require(field.becomeFirstResponder(), "칸이 편집을 시작해야 커서·선택을 볼 수 있다")
    try body(field)
}

/// 커서·선택을 `range` 에 두고, 정말 그 자리에 들어갔는지 먼저 확인한다 — 들어가지 않았으면 뒤 단언이 공허하다.
@MainActor
private func place(_ field: UITextField, at range: Range<Int>) throws {
    let start = try #require(field.position(from: field.beginningOfDocument, offset: range.lowerBound))
    let end = try #require(field.position(from: field.beginningOfDocument, offset: range.upperBound))
    field.selectedTextRange = field.textRange(from: start, to: end)
    try #require(selection(of: field) == range, "선택을 \(range) 에 넣은 직후 그 자리여야 한다")
}

@MainActor
private func selection(of field: UITextField) -> Range<Int>? {
    guard let range = field.selectedTextRange else {
        return nil
    }
    let lower = field.offset(from: field.beginningOfDocument, to: range.start)
    let upper = field.offset(from: field.beginningOfDocument, to: range.end)
    return lower ..< upper
}
