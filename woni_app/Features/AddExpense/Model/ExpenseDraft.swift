import Foundation

public struct ExpenseDraft {
    public var amount: Decimal
    public var currencyCode: String
    public var date: Date
    public var categoryId: Int?
    public var assetId: Int?
    public var memo: String

    public init(
        amount: Decimal = 0,
        currencyCode: String = "USD",
        date: Date = Date(),
        categoryId: Int? = nil,
        assetId: Int? = nil,
        memo: String = ""
    ) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.categoryId = categoryId
        self.assetId = assetId
        self.memo = memo
    }
}
