//
//  GuestBudgetImporter.swift
//  woni_app
//

import Foundation
import OSLog

/// 비회원 예산을 로그인한 회원 계정으로 옮기는 표면.
protocol GuestBudgetImporting {
    func importGuestBudget(guestAccessToken: String) async throws
}

enum GuestBudgetImportError: Error {
    /// 회원 계정에 아직 못 만든 카테고리가 있거나 대응표를 읽지 못했다. 요청은 보내지 않았다.
    case incompleteCategoryMapping
}

/// 카테고리 대응표를 확정한 뒤 옮기기 요청을 한 번 보낸다.
/// 표가 덜 찼으면 보내지 않는다 — 그 몫은 서버에서 "그 외"가 되고, 다시 보내도 이미 옮긴 달은 건너뛰어 되돌릴 길이 없다.
/// 비회원 토큰은 로그·오류 어디에도 남기지 않는다.
struct GuestBudgetImporter: GuestBudgetImporting {
    nonisolated static let logger = Logger(subsystem: "woni_app", category: "GuestBudgetImport")

    private let service: BudgetService
    private let categoryMappings: @MainActor () async -> [Int: Int]?

    init(service: BudgetService, categoryMappings: @escaping @MainActor () async -> [Int: Int]?) {
        self.service = service
        self.categoryMappings = categoryMappings
    }

    func importGuestBudget(guestAccessToken: String) async throws {
        guard let mappings = await categoryMappings() else {
            Self.logger.error("비회원 예산 옮기기 보류: 카테고리 대응표가 덜 찼거나 캐시를 읽지 못했다")
            throw GuestBudgetImportError.incompleteCategoryMapping
        }
        let result = try await service.importFromGuest(GuestBudgetImportRequest(
            guestAccessToken: guestAccessToken,
            categoryMappings: mappings.sorted { $0.key < $1.key }.map {
                GuestCategoryMapping(guestCategoryId: $0.key, memberCategoryId: $0.value)
            }
        ))
        Self.logger.notice(
            """
            비회원 예산 옮김: 옮긴 달 \(result.importedMonthCount, privacy: .public)·\
            건너뛴 달 \(result.skippedMonthCount, privacy: .public)
            """
        )
    }
}
