import Foundation

public enum ActivityType: String, Codable, CaseIterable, Sendable {
    case BOTTLE_FEED, BREASTFEED, PUMP, DIAPER, GROWTH, MILESTONE, SLEEP, SOLIDS, ROUTINE, BABY_FIRST, MEDICAL, VACCINE, VITAMIN_D
}

public enum MilkType: String, Codable, CaseIterable, Sendable { case BREAST_MILK, FORMULA, MIXED }
public enum BreastSide: String, Codable, CaseIterable, Sendable { case LEFT, RIGHT }
public enum DiaperType: String, Codable, CaseIterable, Sendable { case WET, DIRTY, MIXED, DRY }

public enum StoolColor: String, Codable, CaseIterable, Sendable {
    case YELLOW, GREEN, BROWN, BLACK, RED, WHITE, ORANGE

    public var label: String { rawValue.prefix(1) + rawValue.dropFirst().lowercased() }
}

public enum StoolTexture: String, Codable, CaseIterable, Sendable {
    case RUN, MUSH, SOLID, MUCOUS, SEEDY, HARD

    public var label: String {
        switch self {
        case .RUN: "Runny"
        case .MUSH: "Mushy"
        case .SOLID: "Solid"
        case .MUCOUS: "Mucousy"
        case .SEEDY: "Seedy"
        case .HARD: "Hard"
        }
    }
}

public enum MealType: String, Codable, CaseIterable, Sendable {
    case BREAKFAST, LUNCH, DINNER, SNACK

    public var label: String { rawValue.prefix(1) + rawValue.dropFirst().lowercased() }
}

public enum Sex: String, Codable, CaseIterable, Sendable { case MALE, FEMALE, OTHER }
public enum ProfileType: String, Codable, CaseIterable, Sendable { case CHILD, PREGNANCY }
public enum CaregiverRole: String, Codable, Sendable { case OWNER, MEMBER }

public enum ReminderKind: String, Codable, CaseIterable, Sendable { case FEED, PUMP, DIAPER, SLEEP }

public enum AppointmentReminderLead: CaseIterable, Sendable, Equatable {
    case NONE, AT_TIME, ONE_HOUR, ONE_DAY

    public var leadMinutes: Int? {
        switch self {
        case .NONE: nil
        case .AT_TIME: 0
        case .ONE_HOUR: 60
        case .ONE_DAY: 1440
        }
    }

    public var label: String {
        switch self {
        case .NONE: "No reminder"
        case .AT_TIME: "At appointment time"
        case .ONE_HOUR: "1 hour before"
        case .ONE_DAY: "1 day before"
        }
    }

    public static func fromLeadMinutes(_ minutes: Int?) -> AppointmentReminderLead {
        allCases.first { $0.leadMinutes == minutes } ?? .NONE
    }
}

/// Dashboard cards.
public enum CardKind: String, Codable, CaseIterable, Sendable {
    case FEED, PUMP, DIAPER, SLEEP, ROUTINE, BABY_FIRSTS, GROWTH, HEALTH

    public static let defaultOrder: [CardKind] = [.FEED, .PUMP, .DIAPER, .SLEEP, .ROUTINE, .BABY_FIRSTS, .GROWTH, .HEALTH]
}

public enum FilterOption: String, Codable, CaseIterable, Sendable {
    case NOTES, PHOTOS, FEED, PUMP, DIAPER, SLEEP, ROUTINE, HEALTH

    public var label: String {
        switch self {
        case .NOTES: "Notes"
        case .PHOTOS: "Photos"
        case .FEED: "Feed"
        case .PUMP: "Pump"
        case .DIAPER: "Diaper"
        case .SLEEP: "Sleep"
        case .ROUTINE: "Routine"
        case .HEALTH: "Health"
        }
    }
}

public enum ActivityToggle: String, Codable, CaseIterable, Sendable {
    case BREASTFEEDING, BOTTLE_FEEDING, BOTTLE_BREAST_MILK, BOTTLE_FORMULA, SOLID_FEEDING, COMBO_FEEDING,
         PUMPING, DIAPER_CHANGES, SLEEP, ROUTINES, BABY_FIRSTS, GROWTH, HEALTH

    public var label: String {
        switch self {
        case .BREASTFEEDING: "Breastfeeding"
        case .BOTTLE_FEEDING: "Bottle Feeding"
        case .BOTTLE_BREAST_MILK: "Breast Milk"
        case .BOTTLE_FORMULA: "Formula"
        case .SOLID_FEEDING: "Solid Feeding"
        case .COMBO_FEEDING: "Combo Feeding"
        case .PUMPING: "Pumping"
        case .DIAPER_CHANGES: "Diaper Changes"
        case .SLEEP: "Sleep"
        case .ROUTINES: "Routines"
        case .BABY_FIRSTS: "Baby Firsts"
        case .GROWTH: "Growth"
        case .HEALTH: "Health"
        }
    }

    /// The card a top-level toggle controls; nil for the bottle sub-toggles.
    public var card: CardKind? {
        switch self {
        case .BREASTFEEDING, .BOTTLE_FEEDING, .SOLID_FEEDING, .COMBO_FEEDING: .FEED
        case .BOTTLE_BREAST_MILK, .BOTTLE_FORMULA: nil
        case .PUMPING: .PUMP
        case .DIAPER_CHANGES: .DIAPER
        case .SLEEP: .SLEEP
        case .ROUTINES: .ROUTINE
        case .BABY_FIRSTS: .BABY_FIRSTS
        case .GROWTH: .GROWTH
        case .HEALTH: .HEALTH
        }
    }

    /// A card is visible if any of its top-level toggles is enabled.
    public static func isCardVisible(_ card: CardKind, disabled: Set<ActivityToggle>) -> Bool {
        allCases.contains { $0.card == card && !disabled.contains($0) }
    }
}
