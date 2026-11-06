import Foundation

public extension ActivityType {
    var card: CardKind {
        switch self {
        case .BOTTLE_FEED, .BREASTFEED, .SOLIDS: .FEED
        case .PUMP: .PUMP
        case .DIAPER: .DIAPER
        case .SLEEP: .SLEEP
        case .ROUTINE: .ROUTINE
        case .BABY_FIRST: .BABY_FIRSTS
        case .GROWTH, .MILESTONE: .GROWTH
        case .MEDICAL, .VACCINE, .VITAMIN_D: .HEALTH
        }
    }

    var displayName: String {
        switch self {
        case .BOTTLE_FEED: "Bottle Feed"
        case .BREASTFEED: "Breastfeed"
        case .PUMP: "Pump"
        case .DIAPER: "Diaper"
        case .GROWTH: "Growth"
        case .MILESTONE: "Milestone"
        case .SLEEP: "Sleep"
        case .SOLIDS: "Solids"
        case .ROUTINE: "Routine"
        case .BABY_FIRST: "Baby First"
        case .MEDICAL: "Medical"
        case .VACCINE: "Vaccine"
        case .VITAMIN_D: "Vitamin D"
        }
    }
}

public extension CardKind {
    var types: [ActivityType] { ActivityType.allCases.filter { $0.card == self } }

    var title: String {
        switch self {
        case .FEED: "Feed"
        case .PUMP: "Pump"
        case .DIAPER: "Diaper"
        case .SLEEP: "Sleep"
        case .ROUTINE: "Routine"
        case .BABY_FIRSTS: "Baby Firsts"
        case .GROWTH: "Growth"
        case .HEALTH: "Health"
        }
    }
}

public func diaperLabel(_ type: DiaperType) -> String {
    switch type {
    case .WET: "Wet"
    case .DIRTY: "Dirty"
    case .MIXED: "Wet + Dirty"
    case .DRY: "Dry"
    }
}

public extension ActivityEntity {
    /// Short label shown after the time in list rows, e.g. "Breast Milk".
    var label: String {
        switch type {
        case .BOTTLE_FEED:
            switch bottle?.milkType {
            case .BREAST_MILK: return "Breast Milk"
            case .FORMULA: return "Formula"
            case .MIXED: return "Mixed"
            case nil: return "Bottle"
            }
        case .BREASTFEED: return "Breastfeed"
        case .SOLIDS: return solids?.mealType?.label ?? "Solids"
        case .PUMP: return ""
        case .DIAPER: return diaper.map { diaperLabel($0.diaperType) } ?? "Diaper"
        case .SLEEP: return "Sleep"
        case .ROUTINE: return routine?.name ?? "Routine"
        case .BABY_FIRST: return babyFirst?.title ?? "Baby First"
        case .GROWTH: return "Growth"
        case .MILESTONE: return milestone?.title ?? "Milestone"
        case .MEDICAL: return medical?.medicationName ?? "Medical"
        case .VACCINE: return vaccine?.vaccines.joined(separator: ", ") ?? "Vaccine"
        case .VITAMIN_D: return "Vitamin D"
        }
    }

    /// Value next to the bar, e.g. "150 mL" or "L 10m  R 5m".
    func detailText(_ prefs: UnitPrefs = .DEFAULT) -> String? {
        switch type {
        case .BOTTLE_FEED: return bottle?.totalMl.map { Format.volume($0, prefs) }
        case .PUMP: return pump?.totalMl.map { Format.volume($0, prefs) }
        case .BREASTFEED:
            guard let b = breastfeed else { return nil }
            var parts: [String] = []
            if b.leftDurationSec > 0 { parts.append("L \(Format.duration(b.leftDurationSec))") }
            if b.rightDurationSec > 0 { parts.append("R \(Format.duration(b.rightDurationSec))") }
            let text = parts.joined(separator: "  ")
            return text.isEmpty ? nil : text
        case .SLEEP: return durationSec.map(Format.duration)
        case .SOLIDS:
            let text = solids?.foods.joined(separator: ", ") ?? ""
            return text.isEmpty ? nil : text
        case .MEDICAL: return medical?.temperatureC.map { Format.temp($0, prefs) }
        case .VITAMIN_D:
            guard let dose = medical?.dose else { return nil }
            return [Format.number(dose), medical?.doseUnit].compactMap { $0 }.joined(separator: " ")
        default: return nil
        }
    }

    /// Magnitude used to size the bar in list rows; nil for rows without a bar.
    var barValue: Double? {
        switch type {
        case .BOTTLE_FEED: return bottle?.totalMl
        case .PUMP: return pump?.totalMl
        case .BREASTFEED: return breastfeed.map { Double($0.leftDurationSec + $0.rightDurationSec) }
        case .SLEEP: return durationSec.map(Double.init)
        default: return nil
        }
    }

    var durationSec: Int64? {
        endTime.map { max(($0 - startTime) / 1000, 0) }
    }

    var hasPhoto: Bool { !(photoUri ?? "").isBlank }
    var hasNote: Bool { !(note ?? "").isBlank }
}

/// Applies the History Filters sheet to an activity list. An empty set means show everything.
public enum ActivityFilters {
    public static func matches(_ entry: ActivityEntity, _ filters: Set<FilterOption>) -> Bool {
        if filters.isEmpty { return true }
        let typeFilters = filters.filter { $0.isTypeFilter }
        let typeOk = typeFilters.isEmpty || typeFilters.contains { $0.types.contains(entry.type) }
        if !typeOk { return false }
        if filters.contains(.NOTES) && entry.note.isNullOrBlank { return false }
        if filters.contains(.PHOTOS) && entry.photoUri.isNullOrBlank { return false }
        return true
    }

    public static func filter(_ entries: [ActivityEntity], _ filters: Set<FilterOption>) -> [ActivityEntity] {
        entries.filter { matches($0, filters) }
    }
}

public extension FilterOption {
    var isTypeFilter: Bool { self != .NOTES && self != .PHOTOS }

    var types: [ActivityType] {
        switch self {
        case .FEED: [.BOTTLE_FEED, .BREASTFEED, .SOLIDS]
        case .PUMP: [.PUMP]
        case .DIAPER: [.DIAPER]
        case .SLEEP: [.SLEEP]
        case .ROUTINE: [.ROUTINE, .BABY_FIRST]
        case .HEALTH: [.MEDICAL, .VACCINE, .VITAMIN_D]
        case .NOTES, .PHOTOS: []
        }
    }
}

public struct SummaryLine: Equatable, Sendable {
    public let type: ActivityType
    public let count: Int
    public let details: [String]
}

public enum Summary {
    /// One line per activity type that has entries in [from, to), in dashboard order.
    public static func summarize(_ entries: [ActivityEntity], from: EpochMs, to: EpochMs, prefs: UnitPrefs = .DEFAULT) -> [SummaryLine] {
        let inRange = entries.filter { $0.deletedAt == nil && $0.startTime >= from && $0.startTime < to }
        return order.compactMap { type in
            let items = inRange.filter { $0.type == type }
            return items.isEmpty ? nil : SummaryLine(type: type, count: items.count, details: details(type, items, prefs))
        }
    }

    private static func details(_ type: ActivityType, _ items: [ActivityEntity], _ prefs: UnitPrefs) -> [String] {
        switch type {
        case .BOTTLE_FEED:
            let total = items.reduce(0.0) { $0 + ($1.bottle?.totalMl ?? 0) }
            let breast = items.reduce(0.0) { $0 + ($1.bottle?.breastMilkMl ?? 0) }
            let formula = items.reduce(0.0) { $0 + ($1.bottle?.formulaMl ?? 0) }
            var lines = ["\(Format.volume(total, prefs)) total"]
            if breast > 0 { lines.append("\(Format.volume(breast, prefs)) breast milk") }
            if formula > 0 { lines.append("\(Format.volume(formula, prefs)) formula") }
            return lines
        case .PUMP:
            return ["\(Format.volume(items.reduce(0.0) { $0 + ($1.pump?.totalMl ?? 0) }, prefs)) total"]
        case .BREASTFEED:
            let left = items.reduce(Int64(0)) { $0 + ($1.breastfeed?.leftDurationSec ?? 0) }
            let right = items.reduce(Int64(0)) { $0 + ($1.breastfeed?.rightDurationSec ?? 0) }
            return ["\(Format.duration(left + right)) total", "L \(Format.duration(left))  R \(Format.duration(right))"]
        case .DIAPER:
            let wet = items.filter { $0.diaper?.diaperType == .WET || $0.diaper?.diaperType == .MIXED }.count
            let dirty = items.filter { $0.diaper?.diaperType == .DIRTY || $0.diaper?.diaperType == .MIXED }.count
            return ["\(wet) wet, \(dirty) dirty"]
        case .SLEEP:
            return ["\(Format.duration(items.reduce(Int64(0)) { $0 + ($1.durationSec ?? 0) })) total"]
        default:
            return []
        }
    }

    static let order: [ActivityType] = [
        .BREASTFEED, .BOTTLE_FEED, .SOLIDS, .PUMP, .DIAPER, .SLEEP, .ROUTINE, .BABY_FIRST, .GROWTH, .MILESTONE, .MEDICAL, .VACCINE, .VITAMIN_D,
    ]
}
