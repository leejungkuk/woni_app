//
//  CatalogService.swift
//  woni_app
//

import Foundation

/// 카테고리/자산 카탈로그 조회 API. 백엔드 `/api/v1/categories`, `/api/v1/assets` 계약에 대응한다.
struct CatalogService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    /// 거래 타입별 카테고리. `transactionType` 값은 서버 계약상 `EXPENSE` 또는 `INCOME`.
    func fetchCategories(transactionType: String) async throws -> [Category] {
        let query = [URLQueryItem(name: "transactionType", value: transactionType)]
        let dtos: [CategoryDTO] = try await client.get("/api/v1/categories", query: query)
        return dtos.map { $0.toDomain() }
    }

    /// 결제/입금 자산 카탈로그.
    func fetchAssets() async throws -> [Asset] {
        let dtos: [AssetDTO] = try await client.get("/api/v1/assets")
        return dtos.map { $0.toDomain() }
    }
}
