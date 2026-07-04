import CoreText
import SwiftUI

enum WoniFontFamily {
    static let regular = "omyu_pretty"

    static func register() {
        guard let url = Bundle.main.url(forResource: regular, withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

enum WoniTypography {
    case h1
    case h2
    case h3
    case h4
    case body1
    case body2
    case body3
    case small1
    case small2

    var fontSize: CGFloat {
        switch self {
        case .h1: return 40
        case .h2: return 36
        case .h3: return 28
        case .h4: return 24
        case .body1: return 20
        case .body2: return 16
        case .body3: return 14
        case .small1: return 12
        case .small2: return 10
        }
    }

    var lineHeightMultiple: CGFloat {
        1.4
    }

    var font: Font {
        .custom(WoniFontFamily.regular, fixedSize: fontSize)
    }

    var lineSpacing: CGFloat {
        fontSize * (lineHeightMultiple - 1)
    }
}

struct WoniTypographyModifier: ViewModifier {
    let style: WoniTypography

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .lineSpacing(style.lineSpacing)
            .padding(.vertical, style.lineSpacing / 2)
    }
}

extension View {
    func woniFont(_ style: WoniTypography) -> some View {
        modifier(WoniTypographyModifier(style: style))
    }
}
