//
//  CustomCategoryService.swift
//  woni_app
//

import Foundation

protocol CustomCategoryServicing {
    func fetchCustomCategories(transactionType: String) async throws -> [CategoryDTO]
    func createCustomCategory(name: String, transactionType: String) async throws -> CategoryDTO
    func deleteCustomCategory(id: Int) async throws
}

struct CreateCustomCategoryRequest: Encodable {
    let name: String
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

    func deleteCustomCategory(id: Int) async throws {
        try await client.delete("/api/v1/categories/custom/\(id)")
    }
}

enum CustomCategoryServiceError: Error, Equatable {
    case invalidName
}
