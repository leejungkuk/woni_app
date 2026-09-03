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
