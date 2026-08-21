//
//  CustomCategoryService.swift
//  woni_app
//

import Foundation

protocol CustomCategoryServicing {
    func fetchCustomCategories(transactionType: String) async throws -> [CategoryDTO]
    func createCustomCategory(name: String, transactionType: String) async throws -> CategoryDTO
    func updateCustomCategory(id: Int, name: String) async throws -> CategoryDTO
    func reorderCustomCategories(orderedIDs: [Int], transactionType: String) async throws -> [CategoryDTO]
    func deleteCustomCategory(id: Int) async throws
}

struct CreateCustomCategoryRequest: Encodable {
    let name: String
    let transactionType: String
}

struct UpdateCustomCategoryRequest: Encodable {
    let name: String
}

struct ReorderCustomCategoriesRequest: Encodable {
    let orderedIds: [Int]
    let transactionType: String
}

struct CustomCategoryService: CustomCategoryServicing {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func fetchCustomCategories(transactionType: String) async throws -> [CategoryDTO] {
        try await client.get(
            "/api/v1/categories/custom",
            query: [URLQueryItem(name: "transactionType", value: transactionType)]
        )
    }

    func createCustomCategory(
        name: String,
        transactionType: String
    ) async throws -> CategoryDTO {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1 ... 50).contains(trimmedName.utf16.count) else {
            throw CustomCategoryServiceError.invalidName
        }
        return try await client.post(
            "/api/v1/categories/custom",
            body: CreateCustomCategoryRequest(
                name: trimmedName,
                transactionType: transactionType
            )
        )
    }

    func updateCustomCategory(id: Int, name: String) async throws -> CategoryDTO {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1 ... 50).contains(trimmedName.utf16.count) else {
            throw CustomCategoryServiceError.invalidName
        }
        return try await client.put(
            "/api/v1/categories/custom/\(id)",
            body: UpdateCustomCategoryRequest(name: trimmedName)
        )
    }

    /// 서버는 보낸 목록에 없는 행의 `sortOrder`를 유지하므로 호출부가 그 타입의 전체 목록을 보낸다.
    /// 응답도 그 타입의 전체 활성 커스텀 목록이다.
    func reorderCustomCategories(
        orderedIDs: [Int],
        transactionType: String
    ) async throws -> [CategoryDTO] {
        try await client.put(
            "/api/v1/categories/custom/order",
            body: ReorderCustomCategoriesRequest(
                orderedIds: orderedIDs,
                transactionType: transactionType
            )
        )
    }

    func deleteCustomCategory(id: Int) async throws {
        try await client.delete("/api/v1/categories/custom/\(id)")
    }
}

enum CustomCategoryServiceError: Error, Equatable {
    case invalidName
}
