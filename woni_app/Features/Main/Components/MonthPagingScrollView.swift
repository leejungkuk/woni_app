import SwiftUI
import UIKit

/// 픽커·세로 스와이프처럼 View 밖에서 월이 바뀐 경우의 슬라이드 명령.
/// 같은 방향이 연달아 와도 구분되도록 매번 새 `id`를 만든다.
struct MonthSlideCommand: Equatable {
    let id: UUID
    /// +1 다음 달(새 달이 오른쪽에서 들어온다), -1 이전 달.
    let direction: Int
}

/// 월 스트립을 실제 `UIScrollView` 위에 얹는다. 손가락 추종·감속·탄성·grab-to-stop은 전부
/// UIKit 물리가 주고 우리는 계산하지 않는다. 스트립 전체를 `UIHostingController` **하나**로
/// 호스팅하므로 메모리 추가분이 없고, 콘텐츠가 스크롤 뷰의 정식 자식이라 날짜 셀 탭도 살아 있다.
struct MonthPagingScrollView<Content: View>: UIViewControllerRepresentable {
    /// 사용자 스와이프가 이웃 슬롯에 정착했을 때(-1 이전, +1 다음).
    let onCommit: (Int) -> Void
    /// 스크롤이 시작/종료될 때. 정착 중 접근성 창을 여닫는 데 쓴다.
    let onScrollActivity: (Bool) -> Void
    /// 프로그램적 슬라이드 명령. 같은 값이 다시 와도 재실행하지 않는다.
    let slide: MonthSlideCommand?
    /// 프로그램적 슬라이드가 끝났을 때.
    let onSlideFinished: () -> Void
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context _: Context) -> MonthPagingController<Content> {
        MonthPagingController(
            rootView: content(),
            onCommit: onCommit,
            onScrollActivity: onScrollActivity,
            onSlideFinished: onSlideFinished
        )
    }

    func updateUIViewController(_ controller: MonthPagingController<Content>, context _: Context) {
        controller.update(
            rootView: content(),
            onCommit: onCommit,
            onScrollActivity: onScrollActivity,
            onSlideFinished: onSlideFinished,
            slide: slide
        )
    }
}

final class MonthPagingController<Content: View>: UIViewController, UIScrollViewDelegate {
    /// 이전·현재·다음 3슬롯.
    private static var slotCount: CGFloat {
        3
    }

    private let scrollView = UIScrollView()
    private let host: UIHostingController<Content>
    private var onCommit: (Int) -> Void
    private var onScrollActivity: (Bool) -> Void
    private var onSlideFinished: () -> Void

    /// 되감기는 폭이 바뀐 프레임에서만 한다. 레이아웃이 돌 때마다 되감으면 달력 높이
    /// 애니메이션(월 전환마다 0.35초, 매 프레임 레이아웃)이 진행 중인 스와이프를 중앙으로
    /// 되돌려 빠른 연속 스와이프가 통째로 씹힌다.
    private var lastLaidOutWidth: CGFloat = 0
    /// 프로그램적 슬라이드 중에는 정착 커밋을 내지 않는다 — 이미 바뀐 달을 한 번 더 옮기게 된다.
    private var isSliding = false
    private var lastSlide: MonthSlideCommand?

    init(
        rootView: Content,
        onCommit: @escaping (Int) -> Void,
        onScrollActivity: @escaping (Bool) -> Void,
        onSlideFinished: @escaping () -> Void
    ) {
        host = UIHostingController(rootView: rootView)
        self.onCommit = onCommit
        self.onScrollActivity = onScrollActivity
        self.onSlideFinished = onSlideFinished
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        // 기본값(true)이면 스크롤 판단을 위해 터치를 붙잡아 두어 날짜 셀 탭이 먹히지 않는다.
        scrollView.delaysContentTouches = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(host.view)
        host.didMove(toParent: self)

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            host.view.topAnchor.constraint(equalTo: content.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            host.view.heightAnchor.constraint(equalTo: frame.heightAnchor),
            host.view.widthAnchor.constraint(equalTo: frame.widthAnchor, multiplier: Self.slotCount)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = scrollView.bounds.width
        guard width > 0, width != lastLaidOutWidth else {
            return
        }

        lastLaidOutWidth = width
        recenter()
    }

    func update(
        rootView: Content,
        onCommit: @escaping (Int) -> Void,
        onScrollActivity: @escaping (Bool) -> Void,
        onSlideFinished: @escaping () -> Void,
        slide: MonthSlideCommand?
    ) {
        self.onCommit = onCommit
        self.onScrollActivity = onScrollActivity
        self.onSlideFinished = onSlideFinished
        host.rootView = rootView

        guard let slide, slide != lastSlide else {
            return
        }

        lastSlide = slide
        performSlide(direction: slide.direction)
    }

    func scrollViewWillBeginDragging(_: UIScrollView) {
        // 슬라이드 도중 손을 대면 UIKit이 애니메이션을 끊고 스크롤을 넘겨받는다. 가드를 여기서
        // 내리지 않으면 그 뒤 정착이 커밋되지 않아 화면과 헤더 월이 어긋난 채로 남는다.
        // 카운터 반납은 건드리지 않는다 — 끊긴 애니메이션도 completion은 반드시 불린다.
        isSliding = false
        onScrollActivity(true)
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        commitSettledPage()
        onScrollActivity(false)
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else {
            return
        }

        commitSettledPage()
        onScrollActivity(false)
    }

    /// 정착한 페이지가 중앙이 아니면 그만큼 월을 옮긴다. 되감기를 **먼저** 끝내야 다음 스와이프가
    /// 곧바로 가능하다 — 되감기를 콘텐츠 갱신까지 미루면 그 사이 오프셋이 스트립 끝에 걸려
    /// 빠른 연속 스와이프가 막힌다.
    private func commitSettledPage() {
        let width = scrollView.bounds.width
        guard width > 0, !isSliding else {
            return
        }

        let step = Int((scrollView.contentOffset.x / width).rounded()) - 1
        guard step != 0 else {
            return
        }

        recenter()
        onCommit(step)
    }

    /// 새 달은 이미 중앙 슬롯에 있으니, 반대편으로 밀어 두고 중앙으로 되돌리면 슬라이드가 된다.
    private func performSlide(direction: Int) {
        let width = scrollView.bounds.width
        guard width > 0 else {
            onSlideFinished()
            return
        }

        isSliding = true
        scrollView.setContentOffset(CGPoint(x: width * CGFloat(1 - direction), y: 0), animated: false)
        UIView.animate(
            withDuration: MainViewModel.monthTransitionDuration,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) { [weak self] in
            guard let self else {
                return
            }

            scrollView.contentOffset = CGPoint(x: width, y: 0)
        } completion: { [weak self] _ in
            guard let self else {
                return
            }

            isSliding = false
            onSlideFinished()
        }
    }

    private func recenter() {
        let width = scrollView.bounds.width
        guard width > 0, scrollView.contentOffset.x != width else {
            return
        }

        scrollView.setContentOffset(CGPoint(x: width, y: 0), animated: false)
    }
}
