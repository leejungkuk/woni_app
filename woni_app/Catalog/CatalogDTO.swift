//
//  CatalogDTO.swift
//  woni_app
//

import Foundation

/// 백엔드 `CategoryResponse`에 1:1 대응하는 서버 DTO.
struct CategoryDTO: Decodable {
    let id: Int
    let code: String
    let displayNameKo: String
    let displayNameEn: String
    let icon: String?
    let sortOrder: Int
}

/// 백엔드 `AssetResponse`에 1:1 대응하는 서버 DTO.
struct AssetDTO: Decodable {
    let id: Int
    let code: String
    let displayNameKo: String
    let displayNameEn: String
    let sortOrder: Int
}
