import SwiftUI

enum WoniColor {
    static let base10 = Color(hex: 0xFDFAF6)
    static let base20 = Color(hex: 0xEDE3D5)
    static let base30 = Color(hex: 0xD6CBBF)

    static let gray00 = Color(hex: 0xFFFFFF)
    static let gray05 = Color(hex: 0xF4F4F3)
    static let gray10 = Color(hex: 0xE9E8E8)
    static let gray20 = Color(hex: 0xD4D2D0)
    static let gray40 = Color(hex: 0xA8A5A1)
    static let gray60 = Color(hex: 0x7D7873)
    static let gray80 = Color(hex: 0x524B44)
    static let gray100 = Color(hex: 0x261E15)

    static let terracotta10 = Color(hex: 0xFBEFEA)
    static let terracotta20 = Color(hex: 0xF6DFD6)
    static let terracotta40 = Color(hex: 0xEEBFAC)
    static let terracotta70 = Color(hex: 0xE18E6E)
    static let terracotta100 = Color(hex: 0xD45E30)
    static let terracotta110 = Color(hex: 0xBB4A1E)

    static let olive10 = Color(hex: 0xF1F4EB)
    static let olive20 = Color(hex: 0xE2EAD7)
    static let olive40 = Color(hex: 0xC5D4AF)
    static let olive70 = Color(hex: 0x9AB474)
    static let olive100 = Color(hex: 0x6E9438)
    static let olive110 = Color(hex: 0x4D7119)
}

struct WoniShadow {
    let color: Color
    let opacity: Double
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    static let shadow1 = WoniShadow(color: WoniColor.olive20, opacity: 0.6, radius: 16, x: 0, y: 0)
    static let shadow2 = WoniShadow(color: WoniColor.gray100, opacity: 0.16, radius: 8, x: 0, y: 2)
}

extension View {
    func woniShadow(_ shadow: WoniShadow) -> some View {
        self.shadow(color: shadow.color.opacity(shadow.opacity), radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
