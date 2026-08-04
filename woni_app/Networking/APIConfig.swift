//
//  APIConfig.swift
//  woni_app
//

import Foundation

/// 네트워크 환경 설정. 값은 빌드 구성별 xcconfig(`Config/Debug.xcconfig`·`Release.xcconfig`)가
/// Info.plist로 주입한다. 개발 기본값은 로컬 백엔드(`./gradlew :module-api:bootRun`)이고,
/// 실기기 테스트용 LAN IP 등 개인 값은 gitignore된 `Config/Secrets.xcconfig`에서 덮어쓴다.
enum APIConfig {
    /// 백엔드 베이스 URL. 주입이 없으면 빈 문자열이 되어 모든 요청이 실패한다. `CatalogLoader`가
    /// 그 실패를 삼키고 seed 카탈로그로 폴백하므로 화면은 뜨지만 서버 데이터가 오지 않는다 —
    /// 설정 누락을 의심할 지점이다. `APIConfigTests`가 이 값을 직접 단언한다.
    static let baseURL: String = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 변수가 치환되지 않고 `$(API_BASE_URL)` 그대로 남으면 URL로 쓸 수 없으니 빈 값과 같이 본다.
        return raw.hasPrefix("$(") ? "" : raw
    }()
}
