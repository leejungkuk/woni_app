import Foundation
import Observation

@MainActor
protocol LocalWriteSyncTriggering: AnyObject {
    func performLocalWrite(_ operation: @escaping () async throws -> Void) async throws
}

@Observable
final class AddExpenseViewModel {
    enum Mode: Equatable {
        case create
        case edit(original: LocalTransaction)
    }

    /// didSet이 붙은 프리필 대상 프로퍼티는 선언부 기본값을 두지 않는다: @Observable에서는
    /// 기본값이 있으면 init 대입이 재대입으로 setter를 타 didSet이 발동한다(기본값 없는
    /// 첫 대입만 초기화로 처리되어 옵저버를 건너뛴다). 기본값은 init에서 모드별로 넣는다.
    var selectedTab: EntryType {
        didSet {
            guard selectedTab != oldValue else {
                return
            }

            if !didLoadCategories(for: selectedTab) || !didLoadAssets {
                Task {
                    await load()
                }
            } else {
                selectDefaultCategoryIfNeeded(for: selectedTab)
                selectDefaultAssetIfNeeded()
                // 현재 탭 데이터가 이미 캐시됨 → 이전 탭의 in-flight load가
                // selectedTab != loadingTab 분기로 끝나도 로딩 상태에 갇히지 않게 해제.
                isLoadingCatalog = false
                catalogError = nil
            }
        }
    }

    var amount: Decimal = 0
    var selectedCurrency: SelectableCurrency {
        didSet {
            guard selectedCurrency != oldValue else {
                return
            }

            clearRatePreview()
        }
    }

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
    var isDeleting = false
    var deleteError: AddExpenseDeleteError?
    var memo: String = ""
    var date: Date {
        didSet {
            guard date != oldValue else {
                return
            }

            clearRatePreview()
        }
    }

    var currentRate: Decimal?
    private(set) var currentQuote: RateQuote?

    private let transactionRepository: TransactionRepository
    private let catalogProvider: CatalogProvider
    private let addExpenseRateProvider: any RateProviding
    private let syncTrigger: (any LocalWriteSyncTriggering)?
    private var didLoadExpenseCategories = false
    private var didLoadIncomeCategories = false
    private var didLoadAssets = false

    let mode: Mode

    var visibleCategories: [Category] {
        categories(for: selectedTab)
    }

    var currencyOptions: [SelectableCurrency] {
        let originalCurrency: SelectableCurrency?
        switch mode {
        case .create:
            originalCurrency = nil
        case let .edit(original):
            originalCurrency = SelectableCurrency(rawValue: original.currencyCode)
        }
        return SelectableCurrency.entryPickerOptions(including: originalCurrency)
    }

    var canSave: Bool {
        selectedCategoryId != nil
            && selectedAssetId != nil
            && Self.isValidAmount(amount)
    }

    init(
        transactionRepository: TransactionRepository,
        catalogProvider: CatalogProvider,
        addExpenseRateProvider: any RateProviding,
        syncTrigger: (any LocalWriteSyncTriggering)? = nil,
        mode: Mode = .create
    ) {
        self.transactionRepository = transactionRepository
        self.catalogProvider = catalogProvider
        self.addExpenseRateProvider = addExpenseRateProvider
        self.syncTrigger = syncTrigger
        self.mode = mode

        switch mode {
        case .create:
            selectedTab = .expense
            selectedCurrency = .krw
            date = Date()
        case let .edit(original):
            selectedTab = Self.entryType(for: original.transactionType)
            amount = original.amount
            selectedCurrency = SelectableCurrency(rawValue: original.currencyCode) ?? .krw
            selectedCategoryId = original.categoryID
            selectedAssetId = original.assetID
            date = ServerDateFormatter.localDate.date(from: original.transactionDate) ?? Date()
            memo = original.memo ?? ""
        }
    }

    @MainActor
    func load() async {
        catalogError = nil
        isLoadingCatalog = false
        loadCategoriesIfNeeded(for: .expense)
        loadCategoriesIfNeeded(for: .income)
        loadAssetsIfNeeded()
        selectDefaultCategoryIfNeeded(for: selectedTab)
        selectDefaultAssetIfNeeded()

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
        return makeConvertedBaseAmount(rate: rate)
    }

    var krwToForeignRate: Decimal? {
        guard let rate = currentRate, rate > 0 else { return nil }
        let krwDecimal = NSDecimalNumber(decimal: selectedCurrency.exchangeUnit)
        let rateDecimal = NSDecimalNumber(decimal: rate)
        let result = krwDecimal.dividing(by: rateDecimal)
        return result.decimalValue
    }

    var isCurrentRateStale: Bool {
        currentQuote?.source != .seed && currentQuote?.isStale == true
    }

    var isCurrentRateEstimated: Bool {
        currentQuote?.source == .seed
    }

    @MainActor
    func save() async {
        guard !isSaving, !isDeleting else {
            return
        }
        if case .create = mode, saveSucceeded, amount == 0, memo.isEmpty {
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
            switch mode {
            case .create:
                if let syncTrigger {
                    try await syncTrigger.performLocalWrite {
                        try await self.transactionRepository.insert(transaction)
                    }
                } else {
                    try await transactionRepository.insert(transaction)
                }
                amount = 0
                memo = ""
                selectedCurrency = .krw
                clearRatePreview()
                selectDefaultCategory(for: selectedTab)
                selectDefaultAsset()
            case .edit:
                if let syncTrigger {
                    try await syncTrigger.performLocalWrite {
                        guard try await self.transactionRepository.update(transaction) else {
                            throw AddExpenseSaveError.transactionNotFound
                        }
                    }
                } else {
                    guard try await transactionRepository.update(transaction) else {
                        throw AddExpenseSaveError.transactionNotFound
                    }
                }
            }
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

    func deleteEntry() async -> Bool {
        guard case let .edit(original) = mode, !isDeleting, !isSaving else {
            return false
        }

        isDeleting = true
        deleteError = nil
        defer {
            isDeleting = false
        }

        do {
            if let syncTrigger {
                try await syncTrigger.performLocalWrite {
                    try await self.transactionRepository.delete(
                        clientEntryID: original.clientEntryID
                    )
                }
            } else {
                try await transactionRepository.delete(clientEntryID: original.clientEntryID)
            }
            return true
        } catch {
            deleteError = .system(error.localizedDescription)
            return false
        }
    }
}

private extension AddExpenseViewModel {
    struct PersistedRateFields {
        let appliedRate: Decimal?
        let rateBaseDate: String?
        let krwAmount: Decimal?
    }

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

    func selectDefaultCategoryIfNeeded(for tab: EntryType) {
        let availableCategoryIDs = categories(for: tab).map(\.id)
        guard selectedCategoryId.map(availableCategoryIDs.contains) != true else {
            return
        }
        selectDefaultCategory(for: tab)
    }

    func selectDefaultAsset() {
        selectedAssetId = assets.first?.id
    }

    func selectDefaultAssetIfNeeded() {
        let availableAssetIDs = assets.map(\.id)
        guard selectedAssetId.map(availableAssetIDs.contains) != true else {
            return
        }
        selectDefaultAsset()
    }

    static func entryType(for transactionType: LocalTransaction.TransactionType) -> EntryType {
        switch transactionType {
        case .expense:
            .expense
        case .income:
            .income
        }
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

        let persistedRateFields = makePersistedRateFields()
        let original: LocalTransaction?
        switch mode {
        case .create:
            original = nil
        case let .edit(editOriginal):
            original = editOriginal
        }

        return LocalTransaction(
            id: original?.id,
            clientEntryID: original?.clientEntryID ?? UUID(),
            amount: amount,
            currencyCode: selectedCurrency.rawValue,
            categoryID: categoryId,
            assetID: assetId,
            transactionType: transactionType(for: selectedTab),
            transactionDate: transactionDate,
            memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
            pending: true,
            appliedRate: persistedRateFields.appliedRate,
            rateBaseDate: persistedRateFields.rateBaseDate,
            krwAmount: persistedRateFields.krwAmount,
            createdAt: original?.createdAt,
            updatedAt: original?.updatedAt,
            syncState: .pendingPush
        )
    }

    func makePersistedRateFields() -> PersistedRateFields {
        guard selectedCurrency != .krw else {
            return PersistedRateFields(
                appliedRate: nil,
                rateBaseDate: nil,
                krwAmount: amount
            )
        }

        guard let currentQuote else {
            return PersistedRateFields(
                appliedRate: nil,
                rateBaseDate: nil,
                krwAmount: nil
            )
        }

        let krwAmount = makeConvertedBaseAmount(rate: currentQuote.tts)
        let rateBaseDate = currentQuote.baseDate.map {
            ServerDateFormatter.localDate.string(from: $0)
        }

        return PersistedRateFields(
            appliedRate: currentQuote.tts,
            rateBaseDate: rateBaseDate,
            krwAmount: krwAmount
        )
    }

    func makeConvertedBaseAmount(rate: Decimal) -> Decimal {
        NSDecimalNumber(decimal: amount)
            .dividing(by: NSDecimalNumber(decimal: selectedCurrency.exchangeUnit))
            .multiplying(by: NSDecimalNumber(decimal: rate))
            .decimalValue
            .roundedToTwoFractionDigits
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
    case transactionNotFound
    case system(String)
}

enum AddExpenseDeleteError: Error, Equatable {
    case system(String)
}
