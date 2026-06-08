import SwiftUI

public extension Color {
    enum Woni {
        public static let base10 = Color(hex: "#FDFAF6")
        public static let base20 = Color(hex: "#EDE3D5")
        public static let gray00 = Color(hex: "#FFFFFF")
        public static let gray20 = Color(hex: "#D4D2D0")
        public static let gray40 = Color(hex: "#A8A5A1")
        public static let gray60 = Color(hex: "#7D7873")
        public static let gray80 = Color(hex: "#524B44")
        public static let gray100 = Color(hex: "#261E15")

        // Terracotta (Expense)
        public static let terracotta10 = Color(hex: "#FBEFEA")
        public static let terracotta20 = Color(hex: "#F6DFD6")
        public static let terracotta70 = Color(hex: "#E18E6E")
        public static let terracotta100 = Color(hex: "#D45E30")
        public static let terracotta110 = Color(hex: "#BB4A1E")

        // Olive (Income)
        public static let olive10 = Color(hex: "#F1F4EB")
        public static let olive20 = Color(hex: "#E2EAD7")
        public static let olive70 = Color(hex: "#9AB474")
        public static let olive100 = Color(hex: "#6E9438")
        public static let olive110 = Color(hex: "#4D7119")
    }
}

public struct AccentPalette {
    public let bg10: Color
    public let bg20: Color
    public let border70: Color
    public let primary100: Color
    public let text110: Color

    public static let terracotta = AccentPalette(
        bg10: Color.Woni.terracotta10,
        bg20: Color.Woni.terracotta20,
        border70: Color.Woni.terracotta70,
        primary100: Color.Woni.terracotta100,
        text110: Color.Woni.terracotta110
    )

    public static let olive = AccentPalette(
        bg10: Color.Woni.olive10,
        bg20: Color.Woni.olive20,
        border70: Color.Woni.olive70,
        primary100: Color.Woni.olive100,
        text110: Color.Woni.olive110
    )
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var intVal: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&intVal)
        let alphaVal, redVal, greenVal, blueVal: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            alphaVal = 255
            redVal = (intVal >> 8) * 17
            greenVal = (intVal >> 4 & 0xF) * 17
            blueVal = (intVal & 0xF) * 17
        case 6: // RGB (24-bit)
            alphaVal = 255
            redVal = intVal >> 16
            greenVal = intVal >> 8 & 0xFF
            blueVal = intVal & 0xFF
        case 8: // ARGB (32-bit)
            alphaVal = intVal >> 24
            redVal = intVal >> 16 & 0xFF
            greenVal = intVal >> 8 & 0xFF
            blueVal = intVal & 0xFF
        default:
            (alphaVal, redVal, greenVal, blueVal) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(redVal) / 255,
            green: Double(greenVal) / 255,
            blue: Double(blueVal) / 255,
            opacity: Double(alphaVal) / 255
        )
    }
}
