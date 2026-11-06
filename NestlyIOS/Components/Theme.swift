import NestlyCore
import SwiftUI

extension CardKind {
    var color: Color {
        switch self {
        case .FEED: Color(red: 0.95, green: 0.55, blue: 0.35)
        case .PUMP: Color(red: 0.62, green: 0.45, blue: 0.85)
        case .DIAPER: Color(red: 0.35, green: 0.70, blue: 0.85)
        case .SLEEP: Color(red: 0.35, green: 0.42, blue: 0.80)
        case .ROUTINE: Color(red: 0.40, green: 0.72, blue: 0.55)
        case .BABY_FIRSTS: Color(red: 0.92, green: 0.70, blue: 0.25)
        case .GROWTH: Color(red: 0.30, green: 0.65, blue: 0.45)
        case .HEALTH: Color(red: 0.88, green: 0.36, blue: 0.45)
        }
    }

    var symbol: String {
        switch self {
        case .FEED: "drop.fill"
        case .PUMP: "drop.triangle.fill"
        case .DIAPER: "humidity.fill"
        case .SLEEP: "moon.zzz.fill"
        case .ROUTINE: "checklist"
        case .BABY_FIRSTS: "star.fill"
        case .GROWTH: "ruler.fill"
        case .HEALTH: "cross.case.fill"
        }
    }
}

extension ActivityType {
    var color: Color { card.color }

    var symbol: String {
        switch self {
        case .BOTTLE_FEED: "waterbottle.fill"
        case .BREASTFEED: "heart.fill"
        case .SOLIDS: "fork.knife"
        case .PUMP: "drop.triangle.fill"
        case .DIAPER: "humidity.fill"
        case .SLEEP: "moon.zzz.fill"
        case .ROUTINE: "checklist"
        case .BABY_FIRST: "star.fill"
        case .GROWTH: "ruler.fill"
        case .MILESTONE: "flag.fill"
        case .MEDICAL: "thermometer.medium"
        case .VACCINE: "syringe.fill"
        case .VITAMIN_D: "sun.max.fill"
        }
    }
}

extension EntryKind {
    var symbol: String { EntryBuilder.typeOf(self).symbol }
    var color: Color { card.color }
}

extension StoolColor {
    var swatch: Color {
        switch self {
        case .YELLOW: .yellow
        case .GREEN: .green
        case .BROWN: .brown
        case .BLACK: .black
        case .RED: .red
        case .WHITE: Color(white: 0.92)
        case .ORANGE: .orange
        }
    }
}
