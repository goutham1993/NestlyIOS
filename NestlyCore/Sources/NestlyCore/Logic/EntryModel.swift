import Foundation

public enum EntryKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case BREASTFEED, BOTTLE, SOLIDS, COMBO, PUMP, DIAPER, SLEEP, ROUTINE, BABY_FIRST, GROWTH, MILESTONE, MEDICAL, VACCINE, VITAMIN_D

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .BREASTFEED: "Breastfeed"
        case .BOTTLE: "Bottle Feed"
        case .SOLIDS: "Solids"
        case .COMBO: "Combo Feed"
        case .PUMP: "Pump"
        case .DIAPER: "Diaper"
        case .SLEEP: "Sleep"
        case .ROUTINE: "Routine"
        case .BABY_FIRST: "Baby First"
        case .GROWTH: "Growth"
        case .MILESTONE: "Milestone"
        case .MEDICAL: "Medical"
        case .VACCINE: "Vaccine"
        case .VITAMIN_D: "Vitamin D"
        }
    }

    public var card: CardKind {
        switch self {
        case .BREASTFEED, .BOTTLE, .SOLIDS, .COMBO: .FEED
        case .PUMP: .PUMP
        case .DIAPER: .DIAPER
        case .SLEEP: .SLEEP
        case .ROUTINE: .ROUTINE
        case .BABY_FIRST: .BABY_FIRSTS
        case .GROWTH, .MILESTONE: .GROWTH
        case .MEDICAL, .VACCINE, .VITAMIN_D: .HEALTH
        }
    }

    /// New entries of these kinds keep their durations in the persistent timers.
    public var isTimed: Bool { [.BREASTFEED, .COMBO, .PUMP, .SLEEP].contains(self) }

    public static func of(_ type: ActivityType) -> EntryKind {
        switch type {
        case .BOTTLE_FEED: .BOTTLE
        case .BREASTFEED: .BREASTFEED
        case .PUMP: .PUMP
        case .DIAPER: .DIAPER
        case .GROWTH: .GROWTH
        case .MILESTONE: .MILESTONE
        case .SLEEP: .SLEEP
        case .SOLIDS: .SOLIDS
        case .ROUTINE: .ROUTINE
        case .BABY_FIRST: .BABY_FIRST
        case .MEDICAL: .MEDICAL
        case .VACCINE: .VACCINE
        case .VITAMIN_D: .VITAMIN_D
        }
    }
}

public enum EntryRequest: Equatable, Hashable, Sendable, Identifiable {
    case new(kind: EntryKind, milestone: Milestone? = nil, vaccines: [String] = [])
    case edit(activityId: String)

    public var id: String {
        switch self {
        case let .new(kind, milestone, vaccines): "new-\(kind.rawValue)-\(milestone?.key ?? "")-\(vaccines.joined(separator: ","))"
        case let .edit(activityId): "edit-\(activityId)"
        }
    }
}

public enum PumpMode: String, Sendable { case LEFT_RIGHT, TOTAL }

/// Everything any sheet can edit. Only the fields for the current [EntryKind] are used on save.
public struct EntryDraft: Equatable, Sendable, Copyable {
    public var startTime: EpochMs
    /// False until the user picks a start time or a timer runs; the row then shows "Add".
    public var startTimeSet: Bool = true
    public var endTime: EpochMs? = nil
    public var note: String = ""
    public var photoPath: String? = nil

    public var milkType: MilkType? = nil
    public var bottleMl: Double? = nil
    public var formulaName: String? = nil

    public var leftSec: Int64 = 0
    public var rightSec: Int64 = 0
    public var beginSide: BreastSide? = nil
    public var endSide: BreastSide? = nil

    public var mealType: MealType? = nil
    public var foods: [String] = []

    public var pumpMode: PumpMode = .TOTAL
    public var pumpSec: Int64 = 0
    public var pumpLeftMl: Double? = nil
    public var pumpRightMl: Double? = nil
    public var pumpTotalMl: Double? = nil

    public var wet: Bool = false
    public var dirty: Bool = false
    public var dry: Bool = false
    public var stoolColor: StoolColor? = nil
    public var stoolTexture: StoolTexture? = nil
    public var rash: Bool = false

    public var routineName: String? = nil
    public var babyFirstTitle: String = ""

    public var weightKg: Double? = nil
    public var heightCm: Double? = nil
    public var headCm: Double? = nil

    public var milestoneKey: String? = nil
    public var milestoneTitle: String = ""

    public var temperatureF: Double? = nil
    public var medicationName: String? = nil
    public var dose: Double? = nil
    public var doseUnit: String? = nil

    public var vaccines: [String] = []

    /// 0 = Breastfeed tab, 1 = Bottle Feed tab.
    public var comboTab: Int = 0

    public init(
        startTime: EpochMs,
        startTimeSet: Bool = true,
        endTime: EpochMs? = nil,
        note: String = "",
        photoPath: String? = nil,
        milkType: MilkType? = nil,
        bottleMl: Double? = nil,
        formulaName: String? = nil,
        leftSec: Int64 = 0,
        rightSec: Int64 = 0,
        beginSide: BreastSide? = nil,
        endSide: BreastSide? = nil,
        mealType: MealType? = nil,
        foods: [String] = [],
        pumpMode: PumpMode = .TOTAL,
        pumpSec: Int64 = 0,
        pumpLeftMl: Double? = nil,
        pumpRightMl: Double? = nil,
        pumpTotalMl: Double? = nil,
        wet: Bool = false,
        dirty: Bool = false,
        dry: Bool = false,
        stoolColor: StoolColor? = nil,
        stoolTexture: StoolTexture? = nil,
        rash: Bool = false,
        routineName: String? = nil,
        babyFirstTitle: String = "",
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        headCm: Double? = nil,
        milestoneKey: String? = nil,
        milestoneTitle: String = "",
        temperatureF: Double? = nil,
        medicationName: String? = nil,
        dose: Double? = nil,
        doseUnit: String? = nil,
        vaccines: [String] = [],
        comboTab: Int = 0
    ) {
        self.startTime = startTime
        self.startTimeSet = startTimeSet
        self.endTime = endTime
        self.note = note
        self.photoPath = photoPath
        self.milkType = milkType
        self.bottleMl = bottleMl
        self.formulaName = formulaName
        self.leftSec = leftSec
        self.rightSec = rightSec
        self.beginSide = beginSide
        self.endSide = endSide
        self.mealType = mealType
        self.foods = foods
        self.pumpMode = pumpMode
        self.pumpSec = pumpSec
        self.pumpLeftMl = pumpLeftMl
        self.pumpRightMl = pumpRightMl
        self.pumpTotalMl = pumpTotalMl
        self.wet = wet
        self.dirty = dirty
        self.dry = dry
        self.stoolColor = stoolColor
        self.stoolTexture = stoolTexture
        self.rash = rash
        self.routineName = routineName
        self.babyFirstTitle = babyFirstTitle
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.headCm = headCm
        self.milestoneKey = milestoneKey
        self.milestoneTitle = milestoneTitle
        self.temperatureF = temperatureF
        self.medicationName = medicationName
        self.dose = dose
        self.doseUnit = doseUnit
        self.vaccines = vaccines
        self.comboTab = comboTab
    }

    public var pumpTotalComputed: Double? {
        switch pumpMode {
        case .TOTAL: return pumpTotalMl
        case .LEFT_RIGHT:
            if pumpLeftMl == nil && pumpRightMl == nil { return nil }
            return (pumpLeftMl ?? 0) + (pumpRightMl ?? 0)
        }
    }
}

/// Whether manually entering [newMl] in a new (not edited) entry should offer to update the stored
/// default. Tolerates the small drift from mL ⇄ oz display rounding.
public func shouldOfferDefaultBottleUpdate(isEditing: Bool, newMl: Double?, defaultMl: Double?) -> Bool {
    guard !isEditing, let newMl else { return false }
    guard let defaultMl else { return true }
    return abs(newMl - defaultMl) > 0.5
}
