import SwiftUI

extension View {
    /// Figma 메모: "금액 입력 후 주변 터치 시 숫자 키패드 사라짐" — 화면 배경을 탭하면 키보드를 내림.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
