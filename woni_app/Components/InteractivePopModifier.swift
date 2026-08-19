import SwiftUI
import UIKit

struct InteractivePopModifier: ViewModifier {
    var isEnabled = true

    func body(content: Content) -> some View {
        content
            .background(InteractivePopEnabler(isEnabled: isEnabled))
    }
}

extension View {
    func interactivePopGestureEnabled(_ isEnabled: Bool = true) -> some View {
        modifier(InteractivePopModifier(isEnabled: isEnabled))
    }
}

private struct InteractivePopEnabler: UIViewRepresentable {
    let isEnabled: Bool

    func makeUIView(context _: Context) -> InteractivePopView {
        let view = InteractivePopView()
        view.desiredEnabled = isEnabled
        return view
    }

    func updateUIView(_ uiView: InteractivePopView, context _: Context) {
        uiView.desiredEnabled = isEnabled
    }
}

final class InteractivePopView: UIView {
    /// 화면이 원하는 제스처 상태. 삭제 요청 진행 중처럼 pop을 일시 차단할 때 false가 된다.
    /// 파라미터 하나로 끝나지 않는다 — `enable()`의 초기 적용과 KVO 강제 복원까지 이 값을
    /// 관통시켜야 시스템이 제스처를 되살려도 차단이 유지된다.
    var desiredEnabled = true {
        didSet {
            guard desiredEnabled != oldValue,
                  let gesture = navController?.interactivePopGestureRecognizer,
                  gesture.delegate === popHandler else { return }
            gesture.isEnabled = desiredEnabled
        }
    }

    private weak var navController: UINavigationController?
    private var popHandler: PopGestureDelegate?
    private weak var savedDelegate: UIGestureRecognizerDelegate?
    private var savedEnabled = false
    private var enabledObservation: NSKeyValueObservation?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.enable()
            }
        } else {
            disable()
        }
    }

    private func enable() {
        guard let nav = findNavController() else { return }
        let gesture = nav.interactivePopGestureRecognizer

        if navController == nil, gesture?.delegate !== popHandler {
            savedDelegate = gesture?.delegate
            savedEnabled = gesture?.isEnabled ?? false
        }

        navController = nav
        let handler = PopGestureDelegate(markerView: self, nav: nav)
        popHandler = handler
        gesture?.delegate = handler
        gesture?.isEnabled = desiredEnabled

        // SwiftUI가 `.toolbar(.hidden, for: .navigationBar)`를 적용할 때 이 인식기를 다시 끈다.
        // 끄는 시점이 화면마다 달라(언어 설정 push에서 실측) 한 번 켜 두는 것만으로는 부족하므로,
        // 우리 delegate가 꽂혀 있는 동안에는 어긋날 때마다 desired 상태로 즉시 되돌린다.
        // 무조건 true로 복원하면 요청 중 차단(desiredEnabled=false)을 시스템이 풀어 버린다.
        enabledObservation = gesture?.observe(\.isEnabled) { [weak self] recognizer, _ in
            guard let self = self,
                  self.navController != nil,
                  recognizer.delegate === self.popHandler,
                  recognizer.isEnabled != self.desiredEnabled else { return }
            recognizer.isEnabled = self.desiredEnabled
        }
    }

    private func disable() {
        enabledObservation = nil
        defer { navController = nil }
        guard let gesture = navController?.interactivePopGestureRecognizer,
              gesture.delegate === popHandler else { return }
        popHandler = nil
        // 저장해 둔 delegate가 이미 해제됐다면 복원할 대상이 없다. 그때 인식기를 켜 둔 채 두면
        // delegate 없이 활성 상태가 되어 modifier를 붙이지 않은 화면(입력 화면 등)에서도
        // 스와이프 백이 열린다. 복원 불가는 조용히 넘기지 말고 명시적 비활성으로 끝낸다.
        guard let savedDelegate else {
            gesture.delegate = nil
            gesture.isEnabled = false
            return
        }
        gesture.delegate = savedDelegate
        gesture.isEnabled = savedEnabled
    }

    private func findNavController() -> UINavigationController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let nav = current as? UINavigationController {
                return nav
            }
            if let vc = current as? UIViewController, let nav = vc.navigationController {
                return nav
            }
            responder = current.next
        }
        guard let window else { return nil }
        return findNavController(from: window.rootViewController)
    }

    private func findNavController(from viewController: UIViewController?) -> UINavigationController? {
        if let nav = viewController as? UINavigationController { return nav }
        for child in viewController?.children ?? [] {
            if let nav = findNavController(from: child) { return nav }
        }
        return nil
    }
}

private final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var markerView: InteractivePopView?
    private weak var nav: UINavigationController?

    init(markerView: InteractivePopView, nav: UINavigationController) {
        self.markerView = markerView
        self.nav = nav
    }

    func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        guard let marker = markerView, marker.window != nil,
              let nav else { return false }
        guard nav.viewControllers.count > 1 else { return false }
        guard nav.transitionCoordinator == nil else { return false }
        guard let topView = nav.topViewController?.view else { return false }
        return marker.isDescendant(of: topView)
    }
}
