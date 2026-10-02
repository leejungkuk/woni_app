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

    /// 탭 첫 화면에 붙인다. 왼쪽 가장자리부터 끄는 것을 아무 데로도 옮기지 않고 삼킨다.
    func rootEdgeSwipeBlocked() -> some View {
        background(RootEdgeSwipeBlocker())
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

private struct RootEdgeSwipeBlocker: UIViewRepresentable {
    func makeUIView(context _: Context) -> RootEdgeSwipeBlockerView {
        RootEdgeSwipeBlockerView()
    }

    func updateUIView(_: RootEdgeSwipeBlockerView, context _: Context) {}
}

/// 첫 화면에서는 pop 제스처가 시작하지 않는다(`PopGestureDelegate`의 `viewControllers.count > 1`). 그러면
/// 가장자리 끌기를 가져가는 인식기가 없어 손을 뗄 때 손가락 아래 행이 눌렸다(2026-10-02, 세 탭 모두).
/// 그 끌기를 이 인식기가 인식해 터치를 취소한다 — 인식해도 하는 일은 없다.
/// pop 제스처를 첫 화면에서 켜서 막지 않는다 — 루트에서 켜면 내비게이션이 멈춘다.
final class RootEdgeSwipeBlockerView: UIView {
    private let recognizer = UIScreenEdgePanGestureRecognizer()
    private let blockHandler = RootEdgeSwipeDelegate()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // 표식일 뿐이다 — 인식기는 내비게이션 컨트롤러 뷰에 단다. 이 뷰가 터치를 받으면 뒤 화면 히트 테스트가 바뀐다.
        isUserInteractionEnabled = false
        recognizer.edges = .left
        recognizer.delegate = blockHandler
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            recognizer.view?.removeGestureRecognizer(recognizer)
            blockHandler.nav = nil
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, let nav = self.findNavController() else { return }
            self.blockHandler.nav = nav
            nav.view.addGestureRecognizer(self.recognizer)
        }
    }

    /// 응답 사슬로만 찾는다. 창의 루트부터 뒤지면 다른 탭의 내비게이션 컨트롤러를 집는다.
    private func findNavController() -> UINavigationController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let nav = current as? UINavigationController {
                return nav
            }
            if let viewController = current as? UIViewController, let nav = viewController.navigationController {
                return nav
            }
            responder = current.next
        }
        return nil
    }
}

private final class RootEdgeSwipeDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var nav: UINavigationController?

    func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        guard let nav else { return false }
        return nav.viewControllers.count == 1 && nav.transitionCoordinator == nil
    }

    /// 스크롤 뷰의 팬과는 함께 인식한다 — 가장자리에서 시작해도 달력 가로 페이징과 목록 스크롤은 지금처럼 움직인다.
    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        guard let scrollView = other.view as? UIScrollView else { return false }
        return other === scrollView.panGestureRecognizer
    }
}
