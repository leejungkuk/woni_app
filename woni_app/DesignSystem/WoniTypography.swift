import CoreText
import SwiftUI

enum WoniFontFamily {
    static let regular = "omyu_pretty"

    static func register() {
        guard let url = Bundle.main.url(forResource: regular, withExtension: "ttf") else {
            assertionFailure("폰트 리소스 \(regular).ttf를 번들에서 찾지 못했습니다. 시스템 폰트로 폴백됩니다.")
            return
        }
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !registered {
            // 이미 등록된 경우(.alreadyRegistered)는 무해하므로 허용하고, 그 외 실패만 DEBUG에서 표면화한다.
            let cfError = error?.takeRetainedValue()
            let code = cfError.map { CFErrorGetCode($0) }
            if code != CTFontManagerError.alreadyRegistered.rawValue {
                assertionFailure("폰트 \(regular) 등록 실패. 시스템 폰트로 조용히 폴백됩니다.")
            }
        }
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
