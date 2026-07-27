import Foundation

public enum SelectableCurrency: String, CaseIterable, Identifiable {
    case krw = "KRW"
    case usd = "USD"
    case eur = "EUR"
    case jpy = "JPY"
    case cny = "CNY"
    case gbp = "GBP"
    case thb = "THB"
    case hkd = "HKD"
    case sgd = "SGD"
    case idr = "IDR"
    case myr = "MYR"
    case aud = "AUD"
    case nzd = "NZD"

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
        case .krw: "대한민국"
        case .usd: "미국"
        case .eur: "유럽"
        case .jpy: "일본"
        case .cny: "중국"
        case .gbp: "영국"
        case .thb: "태국"
        case .hkd: "홍콩"
        case .sgd: "싱가포르"
        case .idr: "인도네시아"
        case .myr: "말레이시아"
        case .aud: "호주"
        case .nzd: "뉴질랜드"
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
        case .thb: "Thailand"
        case .hkd: "Hong Kong"
        case .sgd: "Singapore"
        case .idr: "Indonesia"
        case .myr: "Malaysia"
        case .aud: "Australia"
        case .nzd: "New Zealand"
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
        case .thb: return .thb
        case .hkd: return .hkd
        case .sgd: return .sgd
        case .idr: return .idr
        case .myr: return .myr
        case .aud: return .aud
        case .nzd: return .nzd
        }
    }
}

extension SelectableCurrency {
    static let entryPickerOptions: [SelectableCurrency] = [
        .krw, .jpy, .thb, .cny, .hkd, .sgd, .idr,
        .myr, .usd, .eur, .aud, .nzd, .gbp
    ]

    var exchangeUnit: Decimal {
        switch self {
        case .jpy, .idr:
            Decimal(100)
        case .krw, .usd, .eur, .cny, .gbp, .thb, .hkd, .sgd, .myr, .aud, .nzd:
            Decimal(1)
        }
    }
}
