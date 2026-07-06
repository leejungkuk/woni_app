import Foundation

public enum SelectableCurrency: String, CaseIterable, Identifiable {
    case krw = "KRW"
    case usd = "USD"
    case eur = "EUR"
    case jpy = "JPY"
    case cny = "CNY"
    case gbp = "GBP"

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .krw: return "대한민국 원"
        case .usd: return "미국 달러"
        case .eur: return "유로"
        case .jpy: return "일본 엔"
        case .cny: return "중국 위안"
        case .gbp: return "영국 파운드"
        }
    }

    public var flag: String {
        switch self {
        case .krw: return "🇰🇷"
        case .usd: return "🇺🇸"
        case .eur: return "🇪🇺"
        case .jpy: return "🇯🇵"
        case .cny: return "🇨🇳"
        case .gbp: return "🇬🇧"
        }
    }

    var exchangeCode: CurrencyCode? {
        switch self {
        case .krw: return nil
        case .usd: return .usd
        case .eur: return .eur
        case .jpy: return .jpy
        case .cny: return .cny
        case .gbp: return .gbp
        }
    }
}

extension SelectableCurrency {
    static let entryPickerOptions: [SelectableCurrency] = [.krw, .usd, .eur, .jpy, .gbp]

    var exchangeUnit: Decimal {
        switch self {
        case .jpy:
            Decimal(100)
        case .krw, .usd, .eur, .cny, .gbp:
            Decimal(1)
        }
    }
}
