import Foundation
import Testing
@testable import woni_app

/// `APIConfig.baseURL`은 xcconfig → Info.plist 주입을 거친다. 이 경로가 끊기는 방식이 조용하다 —
/// 값이 비거나 잘려도 빌드는 성공하고, 뒤이은 요청 실패를 `CatalogLoader`가 삼켜 seed 카탈로그로
/// 폴백하므로 앱이 정상처럼 보인다. 그래서 주입 결과를 여기서 직접 단언한다.
struct APIConfigTests {
    @Test("주입된 baseURL은 스킴과 호스트를 가진 URL로 파싱된다")
    func baseURLHasSchemeAndHost() throws {
        // xcconfig에서 `//`는 주석이라 `$()`로 끊어야 한다(`http:/$()/localhost:8080`).
        // 빠뜨리면 값이 `http:`로 잘려 호스트가 사라지고, 모든 요청이 조용히 실패한다.
        let url = try #require(URL(string: APIConfig.baseURL), "API_BASE_URL이 비었거나 URL이 아니다")
        #expect(url.scheme?.isEmpty == false)
        #expect(url.host?.isEmpty == false)
    }
}
