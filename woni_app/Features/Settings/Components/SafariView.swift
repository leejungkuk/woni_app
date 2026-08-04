import SafariServices
import SwiftUI

/// 법적 문서 게시본을 앱을 벗어나지 않고 보여주는 인앱 브라우저.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}
