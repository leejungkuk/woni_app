import Foundation

public enum IncomeCategory: String, CaseIterable, Identifiable {
    case salary
    case sideIncome
    case allowance
    case refund
    case taxRefund
    case transfer
    case investment
    case other

    public var id: String {
        rawValue
    }

    public var label: String {
        switch self {
        case .salary: return "💼 Salary"
        case .sideIncome: return "💻 Side Income"
        case .allowance: return "🎁 Allowance"
        case .refund: return "🔄 Refund"
        case .taxRefund: return "🧾 Tax Refund"
        case .transfer: return "💸 Transfer"
        case .investment: return "📈 Investment"
        case .other: return "📥 Other"
        }
    }
}
