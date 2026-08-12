import SwiftUI

/// 완료를 알리는 하단 토스트. 사용자가 닫지 않아도 스스로 사라진다.
struct WoniToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 0) {
            // 아이콘 24pt 프레임의 여백이 글리프와 문구 사이 간격을 만든다(Figma에도 gap은 0이다).
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                // HStack은 자식을 하나로 병합하지 않아, 숨기지 않으면 비지역화 자동 라벨
                // "checkmark"가 문구와 따로 읽힌다.
                .accessibilityHidden(true)
            Text(message)
                .woniFont(.body3)
        }
        .foregroundStyle(WoniColor.base10)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(WoniColor.gray100.opacity(0.95))
        .clipShape(Capsule())
        .woniShadow(.shadow1)
        .accessibilityIdentifier("toast")
    }
}

extension View {
    /// 메시지가 들어오면 하단에 띄우고 3초 뒤 스스로 비운다.
    func woniToast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            ZStack {
                if let text = message.wrappedValue {
                    WoniToast(message: text)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                        .task(id: text) {
                            // 이 시점은 삽입 애니메이션·호출부의 네비게이션 pop 직후와 겹쳐,
                            // 지연 없이 post하면 announcement가 화면-변경 이벤트에 밀려 소리
                            // 없이 유실될 수 있다. pop 전환은 통상 0.35초라 그보다 짧게
                            // 기다리면 레이스가 그대로 남는다 — 전환(0.35초)과 삽입(0.2초)을
                            // 모두 넘긴 뒤 알린다.
                            try? await Task.sleep(for: .milliseconds(500))
                            // 기다리는 사이 취소됐다면 토스트가 이미 사라졌거나 교체된 것이므로
                            // 읽지 않는다.
                            guard !Task.isCancelled else {
                                return
                            }
                            // 토스트는 포커스를 뺏지 않고 스스로 사라지므로, 직접 알리지
                            // 않으면 VoiceOver 사용자는 완료 사실을 놓친다. 종전 시스템
                            // alert이 주던 자동 낭독을 이 알림이 대신한다.
                            AccessibilityNotification.Announcement(text).post()
                            try? await Task.sleep(for: .seconds(3))
                            // 화면을 벗어나거나 다음 메시지로 교체돼 취소된 경우다. 여기서 비우면
                            // 방금 올라온 토스트를 지운다.
                            guard !Task.isCancelled else {
                                return
                            }
                            message.wrappedValue = nil
                        }
                }
            }
            // 애니메이션은 이 오버레이 안에 가둔다. 바깥에 걸면 토스트를 띄우지 않는 동안에도
            // 화면 전체가 트랜잭션에 묶여 무관한 화면의 입력이 끊긴다 — 금액 입력이 유실돼
            // UI 테스트(EntryValidationUITests의 C7)가 실패하며 잡은 회귀다.
            .animation(.easeInOut(duration: 0.2), value: message.wrappedValue)
        }
    }
}
