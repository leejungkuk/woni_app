import SwiftUI

extension MainAmountTone {
    var foregroundColor: Color {
        switch self {
        case .income:
            Color.Woni.olive100
        case .expense:
            Color.Woni.terracotta100
        }
    }
}
