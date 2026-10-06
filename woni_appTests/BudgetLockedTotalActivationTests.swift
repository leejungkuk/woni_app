//
//  BudgetLockedTotalActivationTests.swift
//  woni_appTests
//

import SwiftUI
import Testing
import UIKit
@testable import woni_app

/// 잠긴 전체 칸(갈래 B)의 토스트·키보드 내림은 사용자 활성화 — 손가락 누름·VoiceOver 활성화 — 에서만 일어난다(UI_GUIDE "먼저 적은
/// 쪽이 기준이다" 갈래 B, 2026-10-06 QA F19). 포커스 질의(`textFieldShouldBeginEditing`)는 UIKit·SwiftUI 가 키보드를 내리거나 칸을
/// 옮길 때도 부르므로 누름이 아니다.
/// 판정 함수가 아니라 실제 `Coordinator` 와 `BudgetAmountUITextField` 를 쓴다. 칸은 key window 에 붙인다(`AmountFieldInputTests`).
@MainActor
struct BudgetLockedTotalActivationTests {
    // MARK: 포커스 질의

    @Test("BLTT.S0-R1 잠긴 칸은 포커스 질의에 편집을 거절하기만 하고 알리지 않는다")
    func lockedQueryHasNoSideEffect() throws {
        let probe = LockedFieldProbe(locked: true)
        try withKeyWindow(probe.field) {
            #expect(probe.coordinator.textFieldShouldBeginEditing(probe.field) == false, "잠긴 칸은 편집을 시작하지 않아야 한다")
            #expect(probe.field.becomeFirstResponder() == false, "잠긴 칸은 첫 응답자가 되지 않아야 한다(키보드 없음)")
            #expect(probe.lockedTapCount == 0, "포커스 질의는 누름이 아니다 — 알리면 칸 이동·키보드 내림에 토스트가 뜬다")
        }
    }

    @Test("BLTT.S0-R1 실패 짝: 열린 칸은 포커스 질의에 편집을 시작하고 알리지 않는다")
    func unlockedQueryBeginsEditing() throws {
        let probe = LockedFieldProbe(locked: false)
        try withKeyWindow(probe.field) {
            #expect(probe.coordinator.textFieldShouldBeginEditing(probe.field) == true, "열린 칸은 편집을 시작해야 한다")
            #expect(probe.field.becomeFirstResponder() == true, "열린 칸은 첫 응답자가 되어야 한다")
            #expect(probe.lockedTapCount == 0)
        }
    }

    // MARK: 사용자 활성화

    @Test("BLTT.S0-R1 잠긴 칸은 누름·VoiceOver 활성화마다 알리고 첫 응답자가 되지 않는다", arguments: Activation.allCases)
    func lockedActivationNotifies(activation: Activation) throws {
        let probe = LockedFieldProbe(locked: true)
        try withKeyWindow(probe.field) {
            let activated = try probe.activate(activation)
            #expect(activated, "\(activation) — 잠긴 칸은 활성화를 받아야 한다")
            #expect(probe.lockedTapCount == 1, "\(activation) — 한 번 알려야 한다")
            #expect(!probe.field.isFirstResponder, "\(activation) — 잠긴 칸은 첫 응답자가 되지 않아야 한다")
        }
    }

    @Test("BLTT.S0-R1 실패 짝: 열린 칸의 누름 인식기는 시작하지 않고 알리지 않는다")
    func unlockedTapDoesNotBegin() throws {
        let probe = LockedFieldProbe(locked: false)
        try withKeyWindow(probe.field) {
            let began = try probe.activate(.fingerTap)
            #expect(!began, "열린 칸의 누름은 칸 자신의 편집 누름에 맡겨야 한다")
            #expect(probe.lockedTapCount == 0)
        }
    }

    @Test("BLTT.S0-R1 실패 짝: 열린 칸의 VoiceOver 활성화는 알리지 않고 평범한 칸과 같다")
    func unlockedVoiceOverMatchesPlainField() throws {
        let probe = LockedFieldProbe(locked: false)
        let plain = UITextField()
        try withKeyWindow(probe.field, plain) {
            let activated = probe.field.accessibilityActivate()
            let becameFirstResponder = probe.field.isFirstResponder
            probe.field.resignFirstResponder()
            let plainActivated = plain.accessibilityActivate()
            let plainBecameFirstResponder = plain.isFirstResponder

            #expect(activated == plainActivated, "재정의가 열린 칸의 기본 활성화 반환값을 바꾸면 안 된다")
            #expect(becameFirstResponder == plainBecameFirstResponder, "재정의가 열린 칸의 기본 활성화를 막으면 안 된다")
            #expect(probe.lockedTapCount == 0)
        }
    }

    // MARK: 잠김은 누르는 순간 읽는다

    @Test("BLTT.S0-R1 실패 짝: 열림 → 잠김으로 바뀐 칸은 다음 활성화에 알린다", arguments: Activation.allCases)
    func becameLockedNotifies(activation: Activation) throws {
        let probe = LockedFieldProbe(locked: false)
        try withKeyWindow(probe.field) {
            probe.setLocked(true)
            let activated = try probe.activate(activation)
            #expect(activated, "\(activation)")
            #expect(probe.lockedTapCount == 1, "\(activation) — 잠김은 누르는 순간 코디네이터에서 읽어야 한다")
        }
    }

    @Test("BLTT.S0-R1 실패 짝: 잠김 → 열림으로 바뀐 칸은 다음 활성화에 알리지 않는다", arguments: Activation.allCases)
    func becameUnlockedDoesNotNotify(activation: Activation) throws {
        let probe = LockedFieldProbe(locked: true)
        try withKeyWindow(probe.field) {
            probe.setLocked(false)
            _ = try probe.activate(activation)
            #expect(probe.lockedTapCount == 0, "\(activation) — 열린 칸은 알리지 않아야 한다")
        }
    }

    @Test("BLTT.S0-R1 실패 짝: 꺼진 칸(저장 중)은 잠겨 있어도 누름·활성화에 알리지 않는다", arguments: Activation.allCases)
    func disabledLockedFieldIgnoresActivation(activation: Activation) throws {
        let probe = LockedFieldProbe(locked: true)
        probe.field.isEnabled = false
        try withKeyWindow(probe.field) {
            _ = try probe.activate(activation)
            #expect(probe.lockedTapCount == 0, "\(activation) — 꺼진 칸은 아무것도 하지 않아야 한다")
            #expect(!probe.field.isFirstResponder, "\(activation)")
        }
    }
}

// MARK: - 도우미

enum Activation: CaseIterable, CustomStringConvertible {
    /// 손가락 누름 — 칸에 붙은 실제 인식기의 delegate 시작 판단과 동작.
    case fingerTap
    /// VoiceOver 두 번 탭 — `accessibilityActivate()`.
    case voiceOver

    var description: String {
        switch self {
        case .fingerTap: "손가락 누름"
        case .voiceOver: "VoiceOver 활성화"
        }
    }
}

/// 실제 `BudgetAmountUITextField` 와 그 delegate 인 실제 `Coordinator`. 잠긴 칸이면 `onLockedTap` 을 부른 횟수를 센다.
@MainActor
private final class LockedFieldProbe {
    let field = BudgetAmountUITextField()
    /// `UITextField.delegate` 는 weak 라 여기서 강하게 쥔다.
    let coordinator: BudgetAmountTextField.Coordinator
    private let counter: Counter

    var lockedTapCount: Int {
        counter.count
    }

    init(locked: Bool) {
        let counter = Counter()
        self.counter = counter
        coordinator = BudgetAmountTextField.Coordinator(parent: Self.parent(locked: locked, counter: counter))
        field.delegate = coordinator
    }

    /// `updateUIView` 가 하는 것처럼 코디네이터의 `parent` 만 바꾼다.
    func setLocked(_ locked: Bool) {
        coordinator.parent = Self.parent(locked: locked, counter: counter)
    }

    /// 활성화를 보내고 칸이 받았는지(인식기는 시작 여부, VoiceOver 는 `accessibilityActivate()` 반환값)를 돌려준다.
    func activate(_ activation: Activation) throws -> Bool {
        switch activation {
        case .fingerTap:
            let recognizer = try #require(
                field.gestureRecognizers?.first { $0 === field.lockedTapRecognizer },
                "잠긴 칸 누름 인식기가 칸에 붙어 있어야 한다"
            )
            // delegate 가 없으면 UIKit 은 시작시킨다.
            let began = recognizer.delegate?.gestureRecognizerShouldBegin?(recognizer) ?? true
            if began {
                field.lockedTapRecognized()
            }
            return began
        case .voiceOver:
            return field.accessibilityActivate()
        }
    }

    private static func parent(locked: Bool, counter: Counter) -> BudgetAmountTextField {
        BudgetAmountTextField(
            onAmountChange: { _ in true },
            isFocused: .constant(false),
            displayAmount: 300_000,
            decimalPlaces: 0,
            style: .total,
            isEnabled: true,
            accessibilityIdentifier: "budgetEdit.total",
            emptyAccessibilityValue: "",
            onLimitExceeded: {},
            onEditingEnded: {},
            onLockedTap: locked ? { counter.count += 1 } : nil
        )
    }
}

private final class Counter {
    var count = 0
}

/// 칸들을 key window 에 붙여 `body` 를 돈다. 끝나면 첫 응답자를 내려놓고 원래 key window 를 되돌린다 —
/// key window 가 하나라고 전제하는 테스트(`PresentationAnchorTests`)와 섞이지 않게.
@MainActor
private func withKeyWindow(_ fields: UITextField..., body: () throws -> Void) throws {
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
    for (index, field) in fields.enumerated() {
        field.frame = CGRect(x: 16, y: 120 + CGFloat(index) * 60, width: 320, height: 44)
        root.view.addSubview(field)
    }
    window.makeKeyAndVisible()
    defer {
        fields.forEach { $0.resignFirstResponder() }
        window.isHidden = true
        previousKeyWindow?.makeKey()
    }
    try #require(window.isKeyWindow, "칸을 붙인 창이 key window 여야 한다")
    try body()
}
