import Foundation

public enum PaymentMethod: String, CaseIterable, Identifiable {
    case creditCard
    case debitCard
    case cash
    case account
    case check
    case other

    public var id: String {
        rawValue
    }

    public var label: String {
        switch self {
        case .creditCard: return "Credit Card"
        case .debitCard: return "Debit Card"
        case .cash: return "Cash"
        case .account: return "Account"
        case .check: return "Check"
        case .other: return "Other"
        }
    }
}
