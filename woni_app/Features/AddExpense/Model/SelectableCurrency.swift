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

    func displayName(_ language: AppLanguage) -> String {
        switch language {
        case .ko:
            koreanDisplayName
        case .en:
            englishDisplayName
        }
    }

    private var koreanDisplayName: String {
        switch self {
        case .krw: "대한민국 원"
        case .usd: "미국 달러"
        case .eur: "유로"
        case .jpy: "일본 엔"
        case .cny: "중국 위안"
        case .gbp: "영국 파운드"
        }
    }

    private var englishDisplayName: String {
        switch self {
        case .krw: "South Korea"
        case .usd: "United States"
        case .eur: "Europe"
        case .jpy: "Japan"
        case .cny: "China"
        case .gbp: "United Kingdom"
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

    static func entryPickerOptions(including original: SelectableCurrency?) -> [SelectableCurrency] {
        guard let original, !entryPickerOptions.contains(original) else {
            return entryPickerOptions
        }
        return entryPickerOptions + [original]
    }

    var exchangeUnit: Decimal {
        switch self {
        case .jpy:
            Decimal(100)
        case .krw, .usd, .eur, .cny, .gbp:
            Decimal(1)
        }
    }
}
