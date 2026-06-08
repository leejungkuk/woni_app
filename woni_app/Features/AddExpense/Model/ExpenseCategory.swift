import Foundation

public enum ExpenseCategory: String, CaseIterable, Identifiable {
    case foodDining
    case cafeDrinks
    case travel
    case transport
    case shopping
    case groceries
    case beauty
    case education
    case subscriptions
    case entertainment
    case accommodation
    case other

    public var id: String {
        rawValue
    }

    public var label: String {
        switch self {
        case .foodDining: return "🍽️ Food & Dining"
        case .cafeDrinks: return "☕ Café & Drinks"
        case .travel: return "✈️ Travel"
        case .transport: return "🚌 Transport"
        case .shopping: return "🛍️ Shopping"
        case .groceries: return "🛒 Groceries"
        case .beauty: return "💇 Beauty"
        case .education: return "📚 Education"
        case .subscriptions: return "📱 Subscriptions"
        case .entertainment: return "🎭 Entertainment"
        case .accommodation: return "🏨 Accommodation"
        case .other: return "📦 Other"
        }
    }
}
