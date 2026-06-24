import Foundation
import Observation
import SwiftUI

@Observable
final class AddExpenseViewModel {
    var selectedTab: WoniSegmentTabs.Tab = .expense {
        didSet {
            guard selectedTab != oldValue else {
                return
            }

            selectDefaultCategory(for: selectedTab)
            selectDefaultAsset()

            if !didLoadCategories(for: selectedTab) || !didLoadAssets {
                Task {
                    await load()
                }
            } else {
                // 현재 탭 데이터가 이미 캐시됨 → 이전 탭의 in-flight load가
                // selectedTab != loadingTab 분기로 끝나도 로딩 상태에 갇히지 않게 해제.
                isLoadingCatalog = false
                catalogError = nil
            }
        }
    }

    var amount: Decimal = 0
    var selectedCurrency: SelectableCurrency = .krw
    var expenseCategories: [Category] = []
    var incomeCategories: [Category] = []
    var assets: [Asset] = []
    var selectedCategoryId: Int?
    var selectedAssetId: Int?
    var isLoadingCatalog = false
    var catalogError: String?
    var memo: String = ""
    var date: Date = .init()

    var currentRate: Decimal?

    private let catalogService: CatalogService
    private let exchangeRateService: ExchangeRateService
    private var didLoadExpenseCategories = false
    private var didLoadIncomeCategories = false
    private var didLoadAssets = false

    var palette: AccentPalette {
        selectedTab == .expense ? .terracotta : .olive
    }

    var visibleCategories: [Category] {
        categories(for: selectedTab)
    }

    var canSave: Bool {
        !isLoadingCatalog && catalogError == nil && selectedCategoryId != nil && selectedAssetId != nil
    }

    init(catalogService: CatalogService = .init(), exchangeRateService: ExchangeRateService = .init()) {
        self.catalogService = catalogService
        self.exchangeRateService = exchangeRateService
    }

    func load() async {
        let loadingTab = selectedTab
        isLoadingCatalog = true
        catalogError = nil

        do {
            try await loadCategoriesIfNeeded(for: loadingTab)
            try await loadAssetsIfNeeded()

            if selectedTab == loadingTab {
                selectDefaultCategory(for: loadingTab)
                selectDefaultAsset()
                isLoadingCatalog = false
            }
        } catch {
            if selectedTab == loadingTab {
                catalogError = "Unable to load catalog. Please try again."
                isLoadingCatalog = false
            }
        }

        await fetchRate()
    }

    func fetchRate() async {
        guard let exchangeCode = selectedCurrency.exchangeCode else {
            await MainActor.run {
                self.currentRate = nil
            }
            return
        }

        do {
            let rateData = try await exchangeRateService.fetchRate(for: exchangeCode, on: date)
            await MainActor.run {
                self.currentRate = rateData.dealBasRate
            }
        } catch {
            await MainActor.run {
                self.currentRate = nil
            }
        }
    }

    func updateCurrency(_ newCurrency: SelectableCurrency) {
        selectedCurrency = newCurrency
        Task {
            await fetchRate()
        }
    }

    var convertedBaseAmount: Decimal? {
        guard let rate = currentRate else { return nil }
        // TODO: Backend dealBasRate 단위 의미 확인 전까지 1:1로 처리. JPY 등 100단위 통화 오차 가능 (환율 스케일 per-100 보정 필요)
        return amount * rate
    }

    var krwToForeignRate: Decimal? {
        guard let rate = currentRate, rate > 0 else { return nil }
        let krwDecimal = NSDecimalNumber(decimal: 1)
        let rateDecimal = NSDecimalNumber(decimal: rate)
        let result = krwDecimal.dividing(by: rateDecimal)
        return result.decimalValue
    }

    func save(onSave: (ExpenseDraft) -> Void) {
        // TODO: Step 4에서 LedgerService 연결 시 ExpenseDraft/onSave 의존을 제거한다.
        _ = onSave
    }

    func selectCategory(_ category: Category) {
        selectedCategoryId = category.id
    }

    func selectAsset(_ asset: Asset) {
        selectedAssetId = asset.id
    }
}

private extension AddExpenseViewModel {
    func loadCategoriesIfNeeded(for tab: WoniSegmentTabs.Tab) async throws {
        guard !didLoadCategories(for: tab) else {
            return
        }

        let categories = try await catalogService
            .fetchCategories(transactionType: transactionType(for: tab))
            .sortedByCatalogOrder()

        switch tab {
        case .expense:
            expenseCategories = categories
            didLoadExpenseCategories = true
        case .income:
            incomeCategories = categories
            didLoadIncomeCategories = true
        }
    }

    func loadAssetsIfNeeded() async throws {
        guard !didLoadAssets else {
            return
        }

        assets = try await catalogService.fetchAssets().sortedByCatalogOrder()
        didLoadAssets = true
    }

    func didLoadCategories(for tab: WoniSegmentTabs.Tab) -> Bool {
        switch tab {
        case .expense:
            didLoadExpenseCategories
        case .income:
            didLoadIncomeCategories
        }
    }

    func categories(for tab: WoniSegmentTabs.Tab) -> [Category] {
        switch tab {
        case .expense:
            expenseCategories
        case .income:
            incomeCategories
        }
    }

    func selectDefaultCategory(for tab: WoniSegmentTabs.Tab) {
        selectedCategoryId = categories(for: tab).first?.id
    }

    func selectDefaultAsset() {
        selectedAssetId = assets.first?.id
    }

    func transactionType(for tab: WoniSegmentTabs.Tab) -> String {
        switch tab {
        case .expense:
            "EXPENSE"
        case .income:
            "INCOME"
        }
    }
}

private extension Array where Element == Category {
    func sortedByCatalogOrder() -> [Category] {
        sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.id < $1.id
            }
            return $0.sortOrder < $1.sortOrder
        }
    }
}

private extension Array where Element == Asset {
    func sortedByCatalogOrder() -> [Asset] {
        sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.id < $1.id
            }
            return $0.sortOrder < $1.sortOrder
        }
    }
}
