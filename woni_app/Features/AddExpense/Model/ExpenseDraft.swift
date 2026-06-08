import Foundation

public struct ExpenseDraft {
    public var amount: Decimal
    public var currencyCode: String
    public var date: Date
    public var category: ExpenseCategory?
    public var paymentMethod: PaymentMethod?
    public var memo: String

    public init(
        amount: Decimal = 0,
        currencyCode: String = "USD",
        date: Date = Date(),
        category: ExpenseCategory? = nil,
        paymentMethod: PaymentMethod? = nil,
        memo: String = ""
    ) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.category = category
        self.paymentMethod = paymentMethod
        self.memo = memo
    }
}
