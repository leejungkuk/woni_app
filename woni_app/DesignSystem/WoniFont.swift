import CoreText
import SwiftUI

public enum WoniFont {
    public static let fontName = "omyu_pretty"

    /// 번들에 포함된 omyu pretty(.ttf)를 런타임 등록한다.
    /// 생성형 Info.plist 환경이라 UIAppFonts 대신 코드로 등록. 파일이 없으면 조용히 통과 →
    /// `Font.custom` 이 시스템 폰트로 폴백한다. (앱 기동 시 1회 호출)
    public static func registerFonts() {
        guard let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    public enum Style {
        case h2
        case body1
        case body2
        case body3
        case small1

        var size: CGFloat {
            switch self {
            case .h2: return 36
            case .body1: return 20
            case .body2: return 16
            case .body3: return 14
            case .small1: return 12
            }
        }
    }

    public static func custom(_ style: Style) -> Font {
        // Font.custom will fallback to system font if "omyu_pretty" is not found
        return Font.custom(fontName, size: style.size)
    }
}

public extension Font {
    static func woni(_ style: WoniFont.Style) -> Font {
        return WoniFont.custom(style)
    }
}
