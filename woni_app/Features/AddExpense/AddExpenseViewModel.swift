import Foundation
import Observation

@MainActor
protocol LocalWriteSyncTriggering: AnyObject {
    func performLocalWrite(_ operation: @escaping @MainActor () async throws -> Void) async throws
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

            // 탭 전환은 다른 성격의 기록을 새로 시작한다는 신호다. 신규·수정 모두
            // 카테고리·자산을 비워 사용자가 직접 고르게 한다(mode 분기 없음).
            selectedCategoryId = nil
            selectedAssetId = nil

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
    private(set) var currentBaseQuote: RateQuote?

    private let transactionRepository: TransactionRepository
    private let catalogProvider: CatalogProvider
    private let customCategoryStore: CustomCategoryStore
    private let addExpenseRateProvider: any RateProviding
    private let lastUsedCurrencyStore: LastUsedCurrencyStore?
    private let syncTrigger: (any LocalWriteSyncTriggering)?
    private var rateRequestGeneration = 0
    private var didLoadExpenseCategories = false
    private var didLoadIncomeCategories = false
    private var didLoadAssets = false

    let mode: Mode
    let baseCurrency: SelectableCurrency

    /// 커스텀(Store 순서)을 기본 앞에 둔다 — 방금 추가한 카테고리가 그리드 맨 앞에 보이게(2026-08-19 결정).
    var visibleCategories: [Category] {
        customCategories(for: selectedTab) + categories(for: selectedTab)
    }

    /// 선택 카테고리가 현재 목록(기본+커스텀)에서 사라졌는지. 계산 프로퍼티라 수정 진입 후
    /// load뿐 아니라 store 목록 변경 시에도 재평가된다(관리 화면에서 삭제 후 복귀 경로).
    /// 카탈로그 로드 전에는 판정하지 않는다 — 빈 목록을 "삭제됨"으로 오판하면 안 된다.
    var isSelectedCategoryMissing: Bool {
        guard didLoadCategories(for: selectedTab), let resolvedSelectedCategoryID else {
            return false
        }
        return !visibleCategories.contains { $0.id == resolvedSelectedCategoryID }
    }

    var resolvedSelectedCategoryID: Int? {
        selectedCategoryId.map { customCategoryStore.resolvedID(for: $0) }
    }

    func isCategorySelected(id: Int) -> Bool {
        resolvedSelectedCategoryID == id
    }

    /// 카테고리 관리는 세션 종류와 무관하게 로컬 우선으로 열린다.
    var canManageCategories: Bool {
        true
    }

    var currencyOptions: [SelectableCurrency] {
        SelectableCurrency.entryPickerOptions
    }

    var canSave: Bool {
        selectedCategoryId != nil
            && !isSelectedCategoryMissing
            && selectedAssetId != nil
            && Self.isValidAmount(
                amount,
                decimalPlaces: selectedCurrency.decimalPlaces
            )
    }

    init(
        transactionRepository: TransactionRepository,
        catalogProvider: CatalogProvider,
        customCategoryStore: CustomCategoryStore,
        addExpenseRateProvider: any RateProviding,
        baseCurrency: SelectableCurrency,
        lastUsedCurrencyStore: LastUsedCurrencyStore? = nil,
        syncTrigger: (any LocalWriteSyncTriggering)? = nil,
        mode: Mode = .create
    ) {
        self.transactionRepository = transactionRepository
        self.catalogProvider = catalogProvider
        self.customCategoryStore = customCategoryStore
        self.addExpenseRateProvider = addExpenseRateProvider
        self.baseCurrency = baseCurrency
        self.lastUsedCurrencyStore = lastUsedCurrencyStore
        self.syncTrigger = syncTrigger
        self.mode = mode

        switch mode {
        case .create:
            selectedTab = .expense
            selectedCurrency = lastUsedCurrencyStore?.lastUsedCurrency ?? baseCurrency
            date = Date()
        case let .edit(original):
            let originalCurrency = SelectableCurrency(rawValue: original.currencyCode) ?? .krw
            selectedTab = Self.entryType(for: original.transactionType)
            amount = original.amount.truncated(scale: originalCurrency.decimalPlaces)
            selectedCurrency = originalCurrency
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

        await fetchRate()
    }

    @MainActor
    func fetchRate() async {
        await fetchRate(generation: rateRequestGeneration)
    }

    func updateCurrency(_ newCurrency: SelectableCurrency) {
        guard selectedCurrency != newCurrency else {
            return
        }

        rateRequestGeneration += 1
        let generation = rateRequestGeneration
        selectedCurrency = newCurrency
        Task {
            await fetchRate(generation: generation)
        }
    }

    @discardableResult
    func updateDate(_ newDate: Date) -> Task<Void, Never> {
        guard date != newDate else {
            return Task {}
        }

        rateRequestGeneration += 1
        let generation = rateRequestGeneration
        date = newDate
        return Task {
            await fetchRate(generation: generation)
        }
    }

    /// currency/date 변경 시 이전 context의 환율 프리뷰를 즉시 비운다.
    /// 새 quote 로드 전까지 잘못된 환산(새 통화 × 이전 rate)이 노출되지 않게 한다.
    private func clearRatePreview() {
        currentRate = nil
        currentQuote = nil
        currentBaseQuote = nil
    }

    @MainActor
    private func fetchRate(generation: Int) async {
        let currency = selectedCurrency
        let transactionDate = date
        let localDate = ServerDateFormatter.localDate.string(from: transactionDate)
        let quote: RateQuote?
        let baseQuote: RateQuote?

        if baseCurrency == .krw {
            quote = await addExpenseRateProvider.quote(for: currency, on: transactionDate)
            baseQuote = nil
        } else {
            async let selectedQuote = addExpenseRateProvider.quote(
                for: currency,
                on: transactionDate
            )
            async let requestedBaseQuote = addExpenseRateProvider.quote(
                for: baseCurrency,
                on: transactionDate
            )
            (quote, baseQuote) = await(selectedQuote, requestedBaseQuote)
        }

        guard generation == rateRequestGeneration,
              selectedCurrency == currency,
              ServerDateFormatter.localDate.string(from: date) == localDate
        else {
            return
        }

        currentQuote = quote
        currentBaseQuote = baseQuote
        currentRate = quote?.tts
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
            guard let categoryId = resolvedSelectedCategoryID,
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
                lastUsedCurrencyStore?.record(selectedCurrency)
                amount = 0
                memo = ""
                clearRatePreview()
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

    /// 추가 화면 완료 콜백의 복귀 연동(2026-08-19 결정). 추가한 타입 탭으로 전환한 뒤
    /// 선택한다 — 전환(didSet)이 선택을 비우므로 순서를 바꾸면 선택이 사라진다.
    func adoptCreatedCategory(id: Int, type: EntryType) {
        selectedTab = type
        selectCategory(id: id)
    }

    /// 추가 화면 완료 콜백의 자동 선택(결정 10). 현재 목록에 없는 id는 무시한다 —
    /// 폐기된 id를 선택 상태로 만들지 않는다(store stale-operation 계약과 짝).
    func selectCategory(id: Int) {
        let resolvedID = customCategoryStore.resolvedID(for: id)
        guard visibleCategories.contains(where: { $0.id == resolvedID }) else {
            return
        }
        selectedCategoryId = resolvedID
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

extension AddExpenseViewModel {
    /// 저장 검증과 금액 입력 차단(AmountInputSection)이 공유하는 상한.
    static let maximumAmount = Decimal(99_999_999)

    /// 상한 안내 문구용 표기("99,999,999"). 검증 기준에서 파생해 문구와 기준이 어긋나지 않는다.
    /// 상한은 정수라 0자리 통화(KRW) 표기로 천 단위 콤마를 그대로 얻는다.
    static let maximumAmountLabel = CurrencyFormat.string(maximumAmount, currencyCode: "KRW")
}

private extension AddExpenseViewModel {
    static func isValidAmount(_ amount: Decimal, decimalPlaces: Int) -> Bool {
        amount > 0
            && amount <= maximumAmount
            && amount.truncated(scale: decimalPlaces) == amount
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

    /// 정렬은 Store가 `isOrderedBefore`로 이미 끝냈다 — 여기서 다시 정렬하면 관리 화면에서
    /// 확정한 재배치 순서를 덮어쓴다.
    func customCategories(for tab: EntryType) -> [Category] {
        switch tab {
        case .expense:
            customCategoryStore.categories(for: .expense)
        case .income:
            customCategoryStore.categories(for: .income)
        }
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
        guard Self.isValidAmount(
            amount,
            decimalPlaces: selectedCurrency.decimalPlaces
        ) else {
            throw AddExpenseSaveError.invalidAmount
        }

        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMemo.count <= 255 else {
            throw AddExpenseSaveError.memoTooLong
        }

        let transactionDate = ServerDateFormatter.localDate.string(from: date)
        if TransactionDatePolicy.isBeyondFutureLimit(transactionDate, now: Date()) {
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
