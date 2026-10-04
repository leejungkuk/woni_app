//
//  ConfirmDialogTapGuard.swift
//  woni_app
//

import UIKit

/// 확인 창 버튼을 누른 순간부터 `blockDuration` 동안 화면의 누름을 막는다(UI_GUIDE "공용 확인 창").
/// 창 버튼도 첫 누름만 받는다. QA 에서 통화 `바꾸기` 를 0.32초 간격으로 거듭 누르니 창이 닫힌 뒤의 누름이 뒤 칩에 닿았다.
///
/// 막기는 창 뷰의 수명과 무관하다 — 호출부가 첫 누름에 창을 없애도 뒤 화면을 막아야 한다. 그래서 하나(`shared`)를 앱이 쓴다.
/// 막은 것은 막을 때마다 예약한 풀기가 반드시 푼다. 앱 전체가 안 눌린 채 남는 것이 가장 나쁜 실패다.
@MainActor
final class ConfirmDialogTapGuard {
    static let blockDuration: TimeInterval = 0.5

    static let shared = ConfirmDialogTapGuard(
        now: { Date() },
        block: windowBlocker(keyWindow: foregroundKeyWindow),
        schedule: { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        },
        blockDuration: blockDuration(arguments: ProcessInfo.processInfo.arguments)
    )

    private let now: () -> Date
    private let block: () -> (() -> Void)
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let duration: TimeInterval
    /// 마지막 막기가 끝나는 시각. 그 막기의 풀기가 돌면 지운다 — 기기 시계가 뒤로 가도 막기가 남지 않게.
    private var blockedUntil: Date?

    /// `block` 은 누름을 막고, **그 막기를 푸는 클로저**를 돌려준다 — 가드는 `blockDuration` 뒤 그 클로저를 부른다.
    init(
        now: @escaping () -> Date,
        block: @escaping () -> (() -> Void),
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
        blockDuration: TimeInterval = ConfirmDialogTapGuard.blockDuration
    ) {
        self.now = now
        self.block = block
        self.schedule = schedule
        duration = blockDuration
    }

    /// 막기 시간. 제품은 늘 `blockDuration` 이다. UI 테스트(`-uiTest` 와 `UITestSupport.longTapGuardFlag` 가 함께 있을 때)만
    /// 3초로 늘린다 — XCUITest 의 다음 누름은 창 버튼 누름 뒤 0.4~0.8초쯤에 떨어져, 0.5초로는 "막는 동안의 누름"이 경계에서 흔들린다.
    static func blockDuration(arguments: [String]) -> TimeInterval {
        #if DEBUG
            if arguments.contains(UITestSupport.enableFlag), arguments.contains(UITestSupport.longTapGuardFlag) {
                return 3
            }
        #endif
        return blockDuration
    }

    var isBlocking: Bool {
        guard let blockedUntil else {
            return false
        }
        return now() < blockedUntil
    }

    /// 막는 중이면 액션을 부르지 않고 false. 아니면 막고(`block()`) 액션을 부른 뒤 true,
    /// `blockDuration` 뒤 `block()` 이 돌려준 풀기를 부른다.
    @discardableResult
    func handleTap(_ action: () -> Void) -> Bool {
        guard !isBlocking else {
            return false
        }
        let deadline = now().addingTimeInterval(duration)
        blockedUntil = deadline
        let release = block()
        schedule(duration) { [weak self] in
            if self?.blockedUntil == deadline {
                self?.blockedUntil = nil
            }
            release()
        }
        action()
        return true
    }

    /// `shared` 의 `block` — `keyWindow()` 가 준 window 의 `isUserInteractionEnabled` 를 끄고, **그 window** 를 다시
    /// 켜는 클로저를 돌려준다. 풀 때 `keyWindow()` 를 다시 부르지 않는다 — 예산 탭 알림 창의 `설정 열기` 는 0.5초 안에 앱을
    /// 내보내고, 돌아왔을 때 key window 가 없거나 다르면 막은 window 를 못 풀어 앱 전체가 안 눌린 채 남는다.
    /// 전체 화면 모달(예산 편집·입력)도 같은 window 라 모달 안의 창이면 모달 화면 전체가 막힌다.
    static func windowBlocker(keyWindow: @escaping () -> UIWindow?) -> () -> (() -> Void) {
        {
            guard let window = keyWindow() else {
                // 창 버튼을 누를 수 있었다면 key window 가 있다. 릴리스에서는 막기 없이 액션만 부른다 — 누름을 버리면
                // 사용자의 실행·취소가 사라진다.
                assertionFailure("확인 창을 누른 key window 를 찾지 못했습니다. 누름을 막지 않습니다.")
                return {}
            }
            window.isUserInteractionEnabled = false
            return { window.isUserInteractionEnabled = true }
        }
    }

    /// 전면 활성 scene 의 key window. 둘 이상이면 고르지 않는다 — 열거 순서가 결과를 가르면 기기마다 달라진다
    /// (`AuthenticationPresentationContextProvider.resolve` 와 같다).
    private static func foregroundKeyWindow() -> UIWindow? {
        let candidates = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .filter(\.isKeyWindow)
        return candidates.count == 1 ? candidates.first : nil
    }
}
