import SwiftUI

enum AmountTone: Equatable {
    case expense
    case income

    var foregroundColor: Color {
        switch self {
        case .expense:
            WoniColor.terracotta100
        case .income:
            WoniColor.olive100
        }
    }
}
