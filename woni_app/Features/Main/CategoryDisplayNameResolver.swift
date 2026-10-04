//
//  CategoryDisplayNameResolver.swift
//  woni_app
//

enum CategoryDisplayNameResolver {
    static func displayName(
        for transaction: LocalTransaction,
        categoriesByID: [Int: Category],
        customCategoryStore: CustomCategoryStore,
        language: AppLanguage
    ) -> String {
        if let category = categoriesByID[transaction.categoryID] {
            return localizedDisplayName(for: category, language: language)
        }

        let type: CatalogTransactionType = transaction.transactionType == .expense ? .expense : .income
        // SwiftFormat의 wrapMultilineStatementBraces와 SwiftLint opening_brace가 충돌하는 다중행 조건이다.
        // swiftlint:disable opening_brace
        if let category = customCategoryStore.categories(for: type)
            .first(where: { $0.id == transaction.categoryID })
        {
            return localizedDisplayName(for: category, language: language)
        }
        // swiftlint:enable opening_brace

        return transaction.categorySnapshot ?? WoniStrings.uncategorized(language)
    }

    static func localizedDisplayName(
        for category: Category,
        language: AppLanguage
    ) -> String {
        let name = localizedName(for: category, language: language)
        return category.icon.map { "\($0) \(name)" } ?? name
    }

    /// 아이콘 없는 이름 — VoiceOver 가 이모지 이름까지 읽지 않게 할 때 쓴다.
    static func localizedName(for category: Category, language: AppLanguage) -> String {
        language == .ko ? category.displayNameKo : category.displayNameEn
    }
}
