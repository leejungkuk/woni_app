//
//  APIConfig.swift
//  woni_app
//

import Foundation

/// 네트워크 환경 설정. 운영 전환 시 xcconfig/환경변수 주입으로 교체 예정.
enum APIConfig {
    /// 로컬 백엔드 베이스 URL (`./gradlew :module-api:bootRun`).
    static let baseURL = "http://localhost:8080"
}
