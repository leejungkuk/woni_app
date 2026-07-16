import Foundation
import Observation

@Observable
final class AddExpenseViewModel {
    var selectedTab: EntryType = .expense {
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
    var isSaving = false
    var saveError: AddExpenseSaveError?
    var saveSucceeded = false
    var memo: String = ""
    var date: Date = .init()

    var currentRate: Decimal?
    private(set) var currentQuote: RateQuote?

    private let transactionRepository: TransactionRepository
    private let catalogProvider: CatalogProvider
    private let addExpenseRateProvider: any RateProviding
    private var didLoadExpenseCategories = false
    private var didLoadIncomeCategories = false
    private var didLoadAssets = false

    var visibleCategories: [Category] {
        categories(for: selectedTab)
    }

    var canSave: Bool {
        selectedCategoryId != nil
            && selectedAssetId != nil
            && Self.isValidAmount(amount)
    }

    init(
        transactionRepository: TransactionRepository,
        catalogProvider: CatalogProvider,
        addExpenseRateProvider: any RateProviding
    ) {
        self.transactionRepository = transactionRepository
        self.catalogProvider = catalogProvider
        self.addExpenseRateProvider = addExpenseRateProvider
    }

    @MainActor
    func load() async {
        catalogError = nil
        isLoadingCatalog = false
        loadCategoriesIfNeeded(for: .expense)
        loadCategoriesIfNeeded(for: .income)
        loadAssetsIfNeeded()
        selectDefaultCategory(for: selectedTab)
        selectDefaultAsset()

        await fetchRate()
    }

    @MainActor
    func fetchRate() async {
        let currency = selectedCurrency
        let transactionDate = date
        let localDate = ServerDateFormatter.localDate.string(from: transactionDate)
        let quote = await addExpenseRateProvider.quote(for: currency, on: transactionDate)

        if selectedCurrency == currency, ServerDateFormatter.localDate.string(from: date) == localDate {
            currentQuote = quote
            currentRate = quote?.tts
        }
    }

    func updateCurrency(_ newCurrency: SelectableCurrency) {
        selectedCurrency = newCurrency
        clearRatePreview()
        Task {
            await fetchRate()
        }
    }

    @discardableResult
    func updateDate(_ newDate: Date) -> Task<Void, Never> {
        date = newDate
        clearRatePreview()
        return Task {
            await fetchRate()
        }
    }

    /// currency/date 변경 시 이전 context의 환율 프리뷰를 즉시 비운다.
    /// 새 quote 로드 전까지 잘못된 환산(새 통화 × 이전 rate)이 노출되지 않게 한다.
    private func clearRatePreview() {
        currentRate = nil
        currentQuote = nil
    }

    var convertedBaseAmount: Decimal? {
        guard let rate = currentRate else { return nil }
        let converted = NSDecimalNumber(decimal: amount)
            .dividing(by: NSDecimalNumber(decimal: selectedCurrency.exchangeUnit))
            .multiplying(by: NSDecimalNumber(decimal: rate))
        return converted.decimalValue.roundedToTwoFractionDigits
    }

    var krwToForeignRate: Decimal? {
        guard let rate = currentRate, rate > 0 else { return nil }
        let krwDecimal = NSDecimalNumber(decimal: selectedCurrency.exchangeUnit)
        let rateDecimal = NSDecimalNumber(decimal: rate)
        let result = krwDecimal.dividing(by: rateDecimal)
        return result.decimalValue
    }

    var isCurrentRateStale: Bool {
        currentQuote?.isStale == true
    }

    @MainActor
    func save() async {
        guard !isSaving else {
            return
        }
        if saveSucceeded, amount == 0, memo.isEmpty {
            return
        }

        isSaving = true
        saveError = nil
        saveSucceeded = false
        defer {
            isSaving = false
        }

        do {
            guard let categoryId = selectedCategoryId,
                  let assetId = selectedAssetId
            else {
                throw AddExpenseSaveError.missingSelection
            }

            let transaction = try makeValidatedLocalTransaction(
                categoryId: categoryId,
                assetId: assetId
            )
            try await transactionRepository.insert(transaction)
            amount = 0
            memo = ""
            selectedCurrency = .krw
            currentRate = nil
            selectDefaultCategory(for: selectedTab)
            selectDefaultAsset()
            saveSucceeded = true
        } catch {
            saveError = makeSaveError(for: error)
        }
    }

    func selectCategory(_ category: Category) {
        selectedCategoryId = category.id
    }

    func selectAsset(_ asset: Asset) {
        selectedAssetId = asset.id
    }
}

private extension AddExpenseViewModel {
    static let maximumAmount = Decimal(99_999_999)

    static func isValidAmount(_ amount: Decimal) -> Bool {
        amount > 0
            && amount <= maximumAmount
            && hasScaleAtMostTwoFractionDigits(amount)
    }

    static func hasScaleAtMostTwoFractionDigits(_ amount: Decimal) -> Bool {
        amount.roundedToTwoFractionDigits == amount
    }

    func loadCategoriesIfNeeded(for tab: EntryType) {
        guard !didLoadCategories(for: tab) else {
            return
        }

        switch tab {
        case .expense:
            expenseCategories = catalogProvider.categories(for: .expense)
            didLoadExpenseCategories = true
        case .income:
            incomeCategories = catalogProvider.categories(for: .income)
            didLoadIncomeCategories = true
        }
    }

    func loadAssetsIfNeeded() {
        guard !didLoadAssets else {
            return
        }

        assets = catalogProvider.assets
        didLoadAssets = true
    }

    func didLoadCategories(for tab: EntryType) -> Bool {
        switch tab {
        case .expense:
            didLoadExpenseCategories
        case .income:
            didLoadIncomeCategories
        }
    }

    func categories(for tab: EntryType) -> [Category] {
        switch tab {
        case .expense:
            expenseCategories
        case .income:
            incomeCategories
        }
    }

    func selectDefaultCategory(for tab: EntryType) {
        selectedCategoryId = categories(for: tab).first?.id
    }

    func selectDefaultAsset() {
        selectedAssetId = assets.first?.id
    }

    func transactionType(for tab: EntryType) -> LocalTransaction.TransactionType {
        switch tab {
        case .expense:
            .expense
        case .income:
            .income
        }
    }

    func makeValidatedLocalTransaction(
        categoryId: Int,
        assetId: Int
    ) throws -> LocalTransaction {
        guard Self.isValidAmount(amount) else {
            throw AddExpenseSaveError.invalidAmount
        }

        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMemo.count <= 255 else {
            throw AddExpenseSaveError.memoTooLong
        }

        let transactionDate = ServerDateFormatter.localDate.string(from: date)
        if selectedCurrency != .krw && transactionDate > todayLocalDate() {
            throw AddExpenseSaveError.invalidFutureDate
        }

        return LocalTransaction(
            clientEntryID: UUID(),
            amount: amount,
            currencyCode: selectedCurrency.rawValue,
            categoryID: categoryId,
            assetID: assetId,
            transactionType: transactionType(for: selectedTab),
            transactionDate: transactionDate,
            memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
            pending: true,
            appliedRate: nil,
            rateBaseDate: nil,
            krwAmount: nil
        )
    }

    func todayLocalDate() -> String {
        ServerDateFormatter.localDate.string(from: Date())
    }

    func makeSaveError(for error: Error) -> AddExpenseSaveError {
        if let saveError = error as? AddExpenseSaveError {
            return saveError
        }

        return .system(error.localizedDescription)
    }
}

enum AddExpenseSaveError: Error, Equatable {
    case missingSelection
    case invalidAmount
    case memoTooLong
    case invalidFutureDate
    case system(String)
}
