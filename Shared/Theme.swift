import NestlyCore
import SwiftUI
import UIKit

// MARK: - Palette

/// Calm, low-saturation colors with separate light and dark values. One warm accent; one tint per activity.
enum Palette {
    static let accent = dynamic(0xC0664A, 0xE08B6E)
    static let feed = dynamic(0xD9884F, 0xEBA06C)
    static let pump = dynamic(0x8E76C4, 0xAD98E0)
    static let diaper = dynamic(0x4A93BB, 0x6EB1D6)
    static let sleep = dynamic(0x5A68AE, 0x8B97D8)
    static let routine = dynamic(0x5B9877, 0x7FBA97)
    static let firsts = dynamic(0xC8962F, 0xE0B356)
    static let growth = dynamic(0x3D958C, 0x5EB7AD)
    static let health = dynamic(0xC75A6B, 0xE2808E)
    static let warning = dynamic(0xC98A2E, 0xE2A94F)
    static let critical = dynamic(0xC2493F, 0xE06A60)

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typography

extension Font {
    /// Rounded display type for titles, big numbers and timers.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

// MARK: - Icons

/// An activity/content icon: a bundled Material Symbols Rounded asset, or an SF Symbol when none fits.
enum NestlyIcon: Hashable {
    case asset(String)
    case system(String)

    static let bottle = NestlyIcon.asset("bottle")
    static let breastfeed = NestlyIcon.asset("breastfeed")
    static let solids = NestlyIcon.asset("solids")
    static let pump = NestlyIcon.asset("pump")
    static let diaper = NestlyIcon.asset("diaper")
    static let sleep = NestlyIcon.asset("sleep")
    static let routine = NestlyIcon.asset("routine")
    static let firsts = NestlyIcon.asset("firsts")
    static let height = NestlyIcon.asset("height")
    static let weight = NestlyIcon.asset("weight")
    static let milestone = NestlyIcon.asset("milestone")
    static let health = NestlyIcon.asset("health")
    static let thermometer = NestlyIcon.asset("thermometer")
    static let medication = NestlyIcon.asset("medication")
    static let vaccine = NestlyIcon.asset("vaccine")
    static let vitaminD = NestlyIcon.asset("vitamin-d")
    static let child = NestlyIcon.asset("child")
    static let stroller = NestlyIcon.asset("stroller")
    static let crib = NestlyIcon.asset("crib")
    static let note = NestlyIcon.asset("note")
    static let family = NestlyIcon.asset("family")
    static let calendar = NestlyIcon.asset("calendar")
    static let reminder = NestlyIcon.asset("reminder")

    var image: Image {
        switch self {
        case let .asset(name): Image(name).renderingMode(.template)
        case let .system(name): Image(systemName: name)
        }
    }
}

extension CardKind {
    var color: Color {
        switch self {
        case .FEED: Palette.feed
        case .PUMP: Palette.pump
        case .DIAPER: Palette.diaper
        case .SLEEP: Palette.sleep
        case .ROUTINE: Palette.routine
        case .BABY_FIRSTS: Palette.firsts
        case .GROWTH: Palette.growth
        case .HEALTH: Palette.health
        }
    }

    var icon: NestlyIcon {
        switch self {
        case .FEED: .bottle
        case .PUMP: .pump
        case .DIAPER: .diaper
        case .SLEEP: .sleep
        case .ROUTINE: .routine
        case .BABY_FIRSTS: .firsts
        case .GROWTH: .height
        case .HEALTH: .health
        }
    }
}

extension ActivityType {
    var color: Color { card.color }

    var icon: NestlyIcon {
        switch self {
        case .BOTTLE_FEED: .bottle
        case .BREASTFEED: .breastfeed
        case .SOLIDS: .solids
        case .PUMP: .pump
        case .DIAPER: .diaper
        case .SLEEP: .sleep
        case .ROUTINE: .routine
        case .BABY_FIRST: .firsts
        case .GROWTH: .height
        case .MILESTONE: .milestone
        case .MEDICAL: .thermometer
        case .VACCINE: .vaccine
        case .VITAMIN_D: .vitaminD
        }
    }
}

extension EntryKind {
    var color: Color { card.color }

    var icon: NestlyIcon {
        switch self {
        case .BREASTFEED: .breastfeed
        case .BOTTLE, .COMBO: .bottle
        case .SOLIDS: .solids
        case .PUMP: .pump
        case .DIAPER: .diaper
        case .SLEEP: .sleep
        case .ROUTINE: .routine
        case .BABY_FIRST: .firsts
        case .GROWTH: .height
        case .MILESTONE: .milestone
        case .MEDICAL: .thermometer
        case .VACCINE: .vaccine
        case .VITAMIN_D: .vitaminD
        }
    }
}

extension TimerGroup {
    var icon: NestlyIcon {
        switch self {
        case .BREASTFEED: .breastfeed
        case .PUMP: .pump
        case .SLEEP: .sleep
        }
    }

    var color: Color {
        switch self {
        case .BREASTFEED: Palette.feed
        case .PUMP: Palette.pump
        case .SLEEP: Palette.sleep
        }
    }
}

extension StoolColor {
    var swatch: Color {
        switch self {
        case .YELLOW: Color(red: 0.93, green: 0.78, blue: 0.30)
        case .GREEN: Color(red: 0.47, green: 0.60, blue: 0.30)
        case .BROWN: Color(red: 0.52, green: 0.36, blue: 0.22)
        case .BLACK: Color(white: 0.15)
        case .RED: Color(red: 0.74, green: 0.25, blue: 0.22)
        case .WHITE: Color(white: 0.93)
        case .ORANGE: Color(red: 0.90, green: 0.55, blue: 0.25)
        }
    }
}

// MARK: - Icon tile

/// A category icon on a soft tinted rounded square. Scales with Dynamic Type.
struct IconTile: View {
    let icon: NestlyIcon
    var tint: Color = Palette.accent
    var size: CGFloat = 32
    var filled = false

    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 1.6)
        icon.image
            .resizable()
            .scaledToFit()
            .frame(width: side * 0.58, height: side * 0.58)
            .foregroundStyle(filled ? Color.white : tint)
            .frame(width: side, height: side)
            .background(filled ? tint : tint.opacity(0.15), in: RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}
