//
//  CatalogModels.swift
//  woni_app
//

import Foundation

/// 화면에서 사용하는 카테고리 도메인 모델. 서버 DTO(`CategoryDTO`)와 분리한다.
struct Category: Identifiable {
    let id: Int
    let code: String
    let displayNameKo: String
    let displayNameEn: String
    let icon: String?
    let sortOrder: Int
}

/// 화면에서 사용하는 자산 도메인 모델. 서버 DTO(`AssetDTO`)와 분리한다.
struct Asset: Identifiable {
    let id: Int
    let code: String
    let displayNameKo: String
    let displayNameEn: String
    let sortOrder: Int
}

extension CategoryDTO {
    /// 서버 DTO → 도메인 모델 매핑(DTO가 뷰에 직접 침투하지 않게 분리).
    func toDomain() -> Category {
        Category(
            id: id,
            code: code,
            displayNameKo: displayNameKo,
            displayNameEn: displayNameEn,
            icon: icon,
            sortOrder: sortOrder
        )
    }
}

extension AssetDTO {
    /// 서버 DTO → 도메인 모델 매핑(DTO가 뷰에 직접 침투하지 않게 분리).
    func toDomain() -> Asset {
        Asset(
            id: id,
            code: code,
            displayNameKo: displayNameKo,
            displayNameEn: displayNameEn,
            sortOrder: sortOrder
        )
    }
}
