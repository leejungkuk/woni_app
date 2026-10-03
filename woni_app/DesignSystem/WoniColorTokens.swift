import SwiftUI

enum WoniColor {
    static let base10 = Color(hex: 0xFDFAF6)
    static let base15 = Color(hex: 0xF6EFE4)
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

    static let category01 = Color(hex: 0x3F8C84)
    static let category02 = Color(hex: 0xB8801F)
    static let category03 = Color(hex: 0x63769E)
    static let category04 = Color(hex: 0xBA5661)
    static let category05 = Color(hex: 0x296B88)
    static let category06 = Color(hex: 0x359B75)
    static let category07 = Color(hex: 0x7A4A2E)
    static let category08 = Color(hex: 0x9C963E)
    private static let categoryMiddle = [
        category01, category02, category03, category04,
        category05, category06, category07, category08
    ]
    private static let expenseCategoryPalette = [terracotta100] + categoryMiddle + [olive100]
    private static let incomeCategoryPalette = [olive100] + categoryMiddle + [terracotta100]

    static func categoryColor(rank: Int, type: CatalogTransactionType) -> Color {
        let palette = switch type {
        case .expense: expenseCategoryPalette
        case .income: incomeCategoryPalette
        }
        return palette[rank % palette.count]
    }

    /// 카테고리 색 01~08 의 70 단계(OKLCH 밝기 0.73 · 채도 ×0.69). Figma `ai_Category/Category 0N · 70`.
    static let category01Step70 = Color(hex: 0x82B3AD)
    static let category02Step70 = Color(hex: 0xC8A069)
    static let category03Step70 = Color(hex: 0x9AA8C5)
    static let category04Step70 = Color(hex: 0xDA9195)
    static let category05Step70 = Color(hex: 0x84AFC4)
    static let category06Step70 = Color(hex: 0x79B79B)
    static let category07Step70 = Color(hex: 0xC49F8A)
    static let category08Step70 = Color(hex: 0xAEAB72)
    private static let budgetCategoryBarPalette = [terracotta70] + [
        category01Step70, category02Step70, category03Step70, category04Step70,
        category05Step70, category06Step70, category07Step70, category08Step70
    ] + [olive70]

    /// 예산 카테고리 막대 색 — 지출 순서 색(`categoryColor(rank:type: .expense)`)의 70 단계.
    /// 순위는 예산 탭 안의 쓴 돈 순위(0 부터)이고 10색마다 처음으로 돌아간다.
    static func budgetCategoryBarColor(rank: Int) -> Color {
        budgetCategoryBarPalette[rank % budgetCategoryBarPalette.count]
    }
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
