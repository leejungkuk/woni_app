import SwiftUI
import UIKit

struct HorizontalPagingModifier: ViewModifier {
    let onPage: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .gesture(HorizontalPagingGesture(onPage: onPage))
    }
}

extension View {
    func horizontalPaging(onPage: @escaping (Int) -> Void) -> some View {
        modifier(HorizontalPagingModifier(onPage: onPage))
    }
}

private struct HorizontalPagingGesture: UIGestureRecognizerRepresentable {
    let onPage: (Int) -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(onPage: onPage)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_: UIPanGestureRecognizer, context: Context) {
        context.coordinator.onPage = onPage
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: recognizer.view)
        let dx = translation.x
        let dy = translation.y
        guard abs(dx) > abs(dy) else { return }
        if dx < 0 {
            context.coordinator.onPage(1)
        } else if dx > 0 {
            context.coordinator.onPage(-1)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPage: (Int) -> Void

        init(onPage: @escaping (Int) -> Void) {
            self.onPage = onPage
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view = gestureRecognizer.view,
                  let nav = navigationController(for: view),
                  let topView = nav.topViewController?.view,
                  view.isDescendant(of: topView) else { return false }
            guard let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return false }

            let translation = panGestureRecognizer.translation(in: view)
            let startX = panGestureRecognizer.location(in: view).x - translation.x
            guard startX > 44 else { return false }
            return abs(translation.y) <= abs(translation.x)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let view = gestureRecognizer.view,
                  let nav = navigationController(for: view) else { return false }
            return otherGestureRecognizer === nav.interactivePopGestureRecognizer
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// 팬이 인식되면 행 버튼의 탭은 죽어야 한다 — 한 번의 드래그가 월 전환과 카테고리
        /// 상세 진입을 **둘 다** 일으키던 결함(D-009)의 차단점이다.
        ///
        /// `shouldRecognizeSimultaneouslyWith`를 좁히는 길은 쓰지 않는다. UIKit은 그쪽의
        /// `false`가 동시 인식을 막는다고 **보장하지 않는다** — 상대 delegate가 `true`면
        /// 그대로 동시 인식된다. 반면 이 메서드의 `true`는 보장된다.
        ///
        /// 판별자는 속도가 아니라 **이동 여부**다. 팬이 시작되면 탭이 죽고, 이동 없는 탭은
        /// 팬이 `.failed`로 떨어진 뒤 정상 발화한다.
        ///
        /// 세로 `ScrollView`의 팬과 좌측 가장자리 pop은 제외한다. pop은 위
        /// `shouldRequireFailureOf`로 이미 **반대 방향** 의존을 걸어 뒀고, 양방향은 순환이다.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard !(otherGestureRecognizer.view is UIScrollView) else { return false }
            guard let view = gestureRecognizer.view,
                  let nav = navigationController(for: view),
                  otherGestureRecognizer !== nav.interactivePopGestureRecognizer
            else { return false }
            return true
        }

        private func navigationController(for view: UIView) -> UINavigationController? {
            var responder: UIResponder? = view.next
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
}
