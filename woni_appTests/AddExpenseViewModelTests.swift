//
//  AddExpenseViewModelTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct AddExpenseViewModelTests {
    @Test("load는 현재 탭 카테고리와 자산을 로드하고 sortOrder 첫 항목을 기본 선택한다")
    func loadFetchesCatalogAndSelectsFirstItems() async {
        let recorder = AddExpenseCatalogRequestRecorder()
        AddExpenseCatalogURLProtocol.handler = { request in
            recorder.record(request)
            return try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let viewModel = AddExpenseViewModel(catalogService: CatalogService(client: makeAddExpenseCatalogClient()))

        await viewModel.load()

        #expect(viewModel.catalogError == nil)
        #expect(viewModel.isLoadingCatalog == false)
        #expect(viewModel.expenseCategories.map(\.id) == [10, 11])
        #expect(viewModel.assets.map(\.id) == [20, 21])
        #expect(viewModel.selectedCategoryId == 10)
        #expect(viewModel.selectedAssetId == 20)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "EXPENSE") == 1)
        #expect(recorder.count(path: "/api/v1/assets") == 1)
    }

    @Test("탭 전환은 income 카테고리를 로드하고 캐시된 expense 카테고리는 재요청하지 않는다")
    func tabSwitchLoadsIncomeAndReusesCachedExpenseCategories() async throws {
        let recorder = AddExpenseCatalogRequestRecorder()
        AddExpenseCatalogURLProtocol.handler = { request in
            recorder.record(request)
            return try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let viewModel = AddExpenseViewModel(catalogService: CatalogService(client: makeAddExpenseCatalogClient()))

        await viewModel.load()
        viewModel.selectedTab = .income
        try await waitUntil {
            viewModel.incomeCategories.map(\.id) == [30, 31]
                && viewModel.selectedCategoryId == 30
                && viewModel.isLoadingCatalog == false
        }

        #expect(viewModel.visibleCategories.map(\.id) == [30, 31])
        #expect(viewModel.selectedAssetId == 20)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "EXPENSE") == 1)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "INCOME") == 1)
        #expect(recorder.count(path: "/api/v1/assets") == 1)

        viewModel.selectedTab = .expense
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.visibleCategories.map(\.id) == [10, 11])
        #expect(viewModel.selectedCategoryId == 10)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "EXPENSE") == 1)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "INCOME") == 1)
        #expect(recorder.count(path: "/api/v1/assets") == 1)
    }

    @Test("이미 캐시된 탭으로 전환하면 이전 탭 로딩이 끝나지 않아도 로딩 상태에 갇히지 않는다")
    func switchingToCachedTabClearsStaleLoadingState() async throws {
        AddExpenseCatalogURLProtocol.handler = { request in
            try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let viewModel = AddExpenseViewModel(catalogService: CatalogService(client: makeAddExpenseCatalogClient()))

        // 양 탭 + 자산을 모두 캐시한다.
        await viewModel.load()
        viewModel.selectedTab = .income
        try await waitUntil {
            viewModel.incomeCategories.map(\.id) == [30, 31] && viewModel.isLoadingCatalog == false
        }

        // 이전 탭의 in-flight load가 selectedTab != loadingTab 분기로 끝난 직후 상태를 모사:
        // isLoadingCatalog가 true로 남아 있고 캐시된 탭으로 전환된다.
        viewModel.isLoadingCatalog = true
        viewModel.catalogError = "stale"
        viewModel.selectedTab = .expense
        viewModel.amount = 1

        #expect(viewModel.isLoadingCatalog == false)
        #expect(viewModel.catalogError == nil)
        #expect(viewModel.visibleCategories.map(\.id) == [10, 11])
        #expect(viewModel.selectedCategoryId == 10)
        #expect(viewModel.canSave == true)
    }

    @Test("카탈로그 로드 실패는 catalogError를 노출하고 저장을 막는다")
    func loadSurfacesErrorOnFailureEnvelope() async {
        AddExpenseCatalogURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/categories" {
                return try addExpenseCatalogResponse(for: request, data: failureEnvelopePayload())
            }
            return try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let viewModel = AddExpenseViewModel(catalogService: CatalogService(client: makeAddExpenseCatalogClient()))

        await viewModel.load()

        #expect(viewModel.catalogError != nil)
        #expect(viewModel.isLoadingCatalog == false)
        #expect(viewModel.canSave == false)
        #expect(viewModel.expenseCategories.isEmpty)
        #expect(viewModel.selectedCategoryId == nil)
    }

    @Test("save 성공은 LedgerService.create 요청을 보내고 폼을 기본값으로 리셋한다")
    func saveSuccessCreatesLedgerAndResetsFormFromCachedCatalog() async throws {
        let recorder = AddExpenseCatalogRequestRecorder()
        AddExpenseCatalogURLProtocol.handler = { request in
            recorder.record(request)

            if request.url?.path == "/api/v1/ledgers" {
                return try addExpenseCatalogResponse(for: request, data: ledgerSuccessPayload())
            }

            return try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let client = makeAddExpenseCatalogClient()
        let viewModel = AddExpenseViewModel(
            catalogService: CatalogService(client: client),
            ledgerService: LedgerService(client: client)
        )

        await viewModel.load()
        viewModel.amount = try #require(Decimal(string: "1234.56"))
        viewModel.selectedCurrency = .usd
        viewModel.selectedCategoryId = 11
        viewModel.selectedAssetId = 21
        viewModel.date = try makeSeoulDate(year: 2026, month: 6, day: 24)
        viewModel.memo = "라떼"

        await viewModel.save()

        let recordedRequest = try #require(recorder.firstRequest(path: "/api/v1/ledgers"))
        let bodyData = try #require(recordedRequest.body)
        let decodedBody = try JSONDecoder().decode(AddExpenseLedgerRequestBody.self, from: bodyData)
        let object = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        #expect(recordedRequest.method == "POST")
        #expect(decodedBody.amount == Decimal(string: "1234.56"))
        #expect(decodedBody.currencyCode == "USD")
        #expect(decodedBody.categoryId == 11)
        #expect(decodedBody.assetId == 21)
        #expect(decodedBody.transactionDate == "2026-06-24")
        #expect(decodedBody.memo == "라떼")
        #expect(object.keys.contains("transactionType") == false)
        #expect(recorder.count(path: "/api/v1/categories", transactionType: "EXPENSE") == 1)
        #expect(recorder.count(path: "/api/v1/assets") == 1)
        #expect(recorder.count(path: "/api/v1/ledgers") == 1)

        #expect(viewModel.isSaving == false)
        #expect(viewModel.saveSucceeded == true)
        #expect(viewModel.saveError == nil)
        #expect(viewModel.amount == 0)
        #expect(viewModel.memo.isEmpty)
        #expect(viewModel.selectedCurrency == .krw)
        #expect(viewModel.selectedCategoryId == 10)
        #expect(viewModel.selectedAssetId == 20)
    }

    @Test("save 실패는 서버 메시지를 saveError로 노출하고 UNAUTHORIZED는 개발 토큰 안내를 붙인다")
    func saveFailureSurfacesServerMessage() async {
        AddExpenseCatalogURLProtocol.handler = { request in
            try addExpenseCatalogResponse(
                for: request,
                statusCode: 401,
                data: Data(
                    """
                    {
                        "success": false, "code": "UNAUTHORIZED",
                        "message": "인증이 필요합니다.", "data": null
                    }
                    """.utf8
                )
            )
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let client = makeAddExpenseCatalogClient()
        let viewModel = AddExpenseViewModel(ledgerService: LedgerService(client: client))
        viewModel.amount = 5000
        viewModel.selectedCurrency = .krw
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20
        viewModel.memo = "실패 케이스"

        await viewModel.save()

        #expect(viewModel.isSaving == false)
        #expect(viewModel.saveSucceeded == false)
        #expect(viewModel.saveError?.contains("인증이 필요합니다.") == true)
        #expect(viewModel.saveError?.contains("개발 토큰 확인") == true)
        #expect(viewModel.amount == 5000)
        #expect(viewModel.memo == "실패 케이스")
    }

    @Test("수입 탭 save는 선택된 income categoryId를 Ledger 요청에 포함한다")
    func saveFromIncomeTabSendsSelectedIncomeCategoryId() async throws {
        let recorder = AddExpenseCatalogRequestRecorder()
        AddExpenseCatalogURLProtocol.handler = { request in
            recorder.record(request)

            if request.url?.path == "/api/v1/ledgers" {
                return try addExpenseCatalogResponse(
                    for: request,
                    data: ledgerSuccessPayload(transactionType: "INCOME")
                )
            }

            return try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let client = makeAddExpenseCatalogClient()
        let viewModel = AddExpenseViewModel(
            catalogService: CatalogService(client: client),
            ledgerService: LedgerService(client: client)
        )

        await viewModel.load()
        viewModel.selectedTab = .income
        try await waitUntil {
            viewModel.incomeCategories.map(\.id) == [30, 31]
                && viewModel.selectedCategoryId == 30
                && viewModel.isLoadingCatalog == false
        }
        viewModel.amount = 9000
        viewModel.selectedCategoryId = 31
        viewModel.selectedAssetId = 20
        viewModel.date = try makeSeoulDate(year: 2026, month: 6, day: 24)

        await viewModel.save()

        let recordedRequest = try #require(recorder.firstRequest(path: "/api/v1/ledgers"))
        let bodyData = try #require(recordedRequest.body)
        let decodedBody = try JSONDecoder().decode(AddExpenseLedgerRequestBody.self, from: bodyData)
        let object = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        #expect(decodedBody.categoryId == 31)
        #expect(decodedBody.assetId == 20)
        #expect(decodedBody.currencyCode == "KRW")
        #expect(decodedBody.memo == nil)
        #expect(object.keys.contains("memo") == false)
        #expect(object.keys.contains("transactionType") == false)
    }

    @Test("canSave는 카테고리·자산 선택과 금액 범위를 검증한다")
    func canSaveValidatesRequiredSelectionsAndAmountRange() throws {
        let viewModel = AddExpenseViewModel()

        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20
        #expect(viewModel.canSave == false)

        viewModel.amount = try #require(Decimal(string: "0.01"))
        #expect(viewModel.canSave == true)

        viewModel.amount = 99_999_999
        #expect(viewModel.canSave == true)

        viewModel.amount = try #require(Decimal(string: "99999999.01"))
        #expect(viewModel.canSave == false)

        viewModel.amount = 1
        viewModel.selectedCategoryId = nil
        #expect(viewModel.canSave == false)

        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = nil
        #expect(viewModel.canSave == false)
    }

    @Test("동시 save 호출은 중복 POST를 보내지 않는다")
    func concurrentSaveCallsSendSinglePOST() async {
        let recorder = AddExpenseCatalogRequestRecorder()
        AddExpenseCatalogURLProtocol.handler = { request in
            recorder.record(request)

            if request.url?.path == "/api/v1/ledgers" {
                return try addExpenseCatalogResponse(for: request, data: ledgerSuccessPayload())
            }

            return try addExpenseCatalogResponse(for: request, data: catalogPayload(for: request))
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let client = makeAddExpenseCatalogClient()
        let viewModel = AddExpenseViewModel(ledgerService: LedgerService(client: client))
        viewModel.amount = 5000
        viewModel.selectedCurrency = .krw
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20

        async let first: Void = viewModel.save()
        async let second: Void = viewModel.save()
        _ = await(first, second)

        #expect(recorder.count(path: "/api/v1/ledgers") == 1)
        #expect(viewModel.saveSucceeded == true)
        #expect(viewModel.isSaving == false)
    }

    @Test("비-UNAUTHORIZED 실패는 서버 message를 그대로 노출하고 토큰 안내를 붙이지 않는다")
    func saveFailureSurfacesPlainServerMessage() async {
        AddExpenseCatalogURLProtocol.handler = { request in
            try addExpenseCatalogResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": false, "code": "CATEGORY_NOT_FOUND",
                        "message": "카테고리를 찾을 수 없습니다.", "data": null
                    }
                    """.utf8
                )
            )
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let client = makeAddExpenseCatalogClient()
        let viewModel = AddExpenseViewModel(ledgerService: LedgerService(client: client))
        viewModel.amount = 5000
        viewModel.selectedCurrency = .krw
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20

        await viewModel.save()

        #expect(viewModel.saveError == "카테고리를 찾을 수 없습니다.")
        #expect(viewModel.saveSucceeded == false)
        #expect(viewModel.isSaving == false)
    }

    @Test("canSave가 false면 save는 POST를 보내지 않는다")
    func saveDoesNotPostWhenInvalid() async {
        let recorder = AddExpenseCatalogRequestRecorder()
        AddExpenseCatalogURLProtocol.handler = { request in
            recorder.record(request)
            return try addExpenseCatalogResponse(for: request, data: ledgerSuccessPayload())
        }
        defer { AddExpenseCatalogURLProtocol.handler = nil }

        let client = makeAddExpenseCatalogClient()
        // amount 기본값 0 → canSave false
        let viewModel = AddExpenseViewModel(ledgerService: LedgerService(client: client))
        viewModel.selectedCategoryId = 10
        viewModel.selectedAssetId = 20

        await viewModel.save()

        #expect(recorder.count(path: "/api/v1/ledgers") == 0)
        #expect(viewModel.saveSucceeded == false)
        #expect(viewModel.saveError == nil)
    }
}
