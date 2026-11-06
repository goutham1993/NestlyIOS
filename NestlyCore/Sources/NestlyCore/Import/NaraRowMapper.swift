import Foundation

/// Parsed Nara row, independent of database ids for caregivers.
public enum NaraRecord: Equatable, Sendable {
    case profile(Profile)
    case activity(Activity)

    public struct Profile: Equatable, Sendable {
        public let familyKey: String
        public let profileKey: String
        public let name: String
        public let birthDate: LocalDate?
        public let adjustedBirthDate: LocalDate?
        public let sex: Sex?
        public let profileType: ProfileType
    }

    public struct Activity: Equatable, Sendable, Copyable {
        public var familyKey: String
        public var activityKey: String
        public var profileKey: String?
        public var profileName: String?
        public var type: ActivityType
        public var startTime: EpochMs
        public var endTime: EpochMs?
        public var timeZone: String
        public var note: String?
        public var createdBy: String?
        public var updatedBy: String?
        public var bottle: BottleDetails?
        public var pump: PumpDetails?
        public var breastfeed: BreastfeedDetails?
        public var diaper: DiaperDetails?
        public var growth: GrowthDetails?
        public var milestone: MilestoneDetails?
    }

    public var familyKey: String {
        switch self {
        case let .profile(p): p.familyKey
        case let .activity(a): a.familyKey
        }
    }

    public var asProfile: Profile? { if case let .profile(p) = self { p } else { nil } }
    public var asActivity: Activity? { if case let .activity(a) = self { a } else { nil } }
}

public enum NaraRowMapper {
    static let ML_PER_FLOZ = 29.5735295625
    static let KG_PER_LB = 0.45359237
    static let CM_PER_IN = 2.54
    static let DEFAULT_TIME_ZONE = "UTC"

    /// Returns nil for rows of a type we don't support yet or rows missing required keys.
    public static func map(_ row: [String: String]) -> NaraRecord? {
        guard let familyKey = row["_familyKey"] else { return nil }
        switch row["Type"] {
        case "Profile":
            return mapProfile(familyKey, row).map(NaraRecord.profile)
        case "Bottle Feed":
            return activity(familyKey, row, .BOTTLE_FEED).map { a in .activity(a.with { $0.bottle = bottle(row) }) }
        case "Pump":
            return mapPump(familyKey, row).map(NaraRecord.activity)
        case "Breastfeed":
            return mapBreastfeed(familyKey, row).map(NaraRecord.activity)
        case "Diaper":
            return activity(familyKey, row, .DIAPER).map { a in .activity(a.with { $0.diaper = diaper(row) }) }
        case "Growth":
            return activity(familyKey, row, .GROWTH).map { a in .activity(a.with { $0.growth = growth(row) }) }
        case "Milestone":
            guard let title = row["[Milestone] Milestone"] else { return nil }
            return activity(familyKey, row, .MILESTONE).map { a in .activity(a.with { $0.milestone = MilestoneDetails(title.trimmed) }) }
        default:
            return nil
        }
    }

    private static func mapProfile(_ familyKey: String, _ row: [String: String]) -> NaraRecord.Profile? {
        guard let profileKey = row["_profileKey"] else { return nil }
        return NaraRecord.Profile(
            familyKey: familyKey,
            profileKey: profileKey,
            name: row["Profile Name"] ?? "Baby",
            birthDate: row["[Profile] Birth Date"].flatMap(LocalDate.parse),
            adjustedBirthDate: row["[Profile] Birth Date (Adjusted)"].flatMap(LocalDate.parse),
            sex: row["[Profile] Sex"].flatMap { enumOrNil(Sex.self, $0) },
            profileType: row["[Profile] Type"].flatMap { enumOrNil(ProfileType.self, $0) } ?? .CHILD
        )
    }

    private static func activity(_ familyKey: String, _ row: [String: String], _ type: ActivityType) -> NaraRecord.Activity? {
        guard let key = row["_activityKey"], let start = row["Start Date/time (Epoch)"]?.toLongFlexible() else { return nil }
        return NaraRecord.Activity(
            familyKey: familyKey,
            activityKey: key,
            profileKey: row["_profileKey"],
            profileName: row["Profile Name"],
            type: type,
            startTime: start,
            endTime: nil,
            timeZone: row["Time Zone"] ?? DEFAULT_TIME_ZONE,
            note: row["Note"]?.trimmedNilIfEmpty,
            createdBy: row["Created By Caregiver"],
            updatedBy: row["Last Updated By Caregiver"] ?? row["Created By Caregiver"]
        )
    }

    private static func bottle(_ row: [String: String]) -> BottleDetails {
        let breastMl = volumeMl(row, "[Bottle Feed] Breast Milk Volume")
        let formulaMl = volumeMl(row, "[Bottle Feed] Formula Volume")
        let genericMl = volumeMl(row, "[Bottle Feed] Volume")
        let milkType: MilkType?
        if breastMl != nil && formulaMl != nil {
            milkType = .MIXED
        } else {
            switch row["[Bottle Feed] Type"] {
            case "Breast Milk": milkType = .BREAST_MILK
            case "Formula": milkType = .FORMULA
            case "Mixed": milkType = .MIXED
            default: milkType = nil
            }
        }
        return BottleDetails(milkType, breastMilkMl: breastMl, formulaMl: formulaMl, formulaName: row["[Bottle Feed] Formula Name"], totalMl: genericMl ?? sumOrNil(breastMl, formulaMl))
    }

    private static func mapPump(_ familyKey: String, _ row: [String: String]) -> NaraRecord.Activity? {
        guard let base = activity(familyKey, row, .PUMP) else { return nil }
        let left = volumeMl(row, "[Pump] Left Volume")
        let right = volumeMl(row, "[Pump] Right Volume")
        let total = volumeMl(row, "[Pump] Total Volume") ?? sumOrNil(left, right)
        let end = row["[Pump] End Date/time (Epoch)"]?.toLongFlexible().map { max($0, base.startTime) }
        let duration = max(row["[Pump] Duration (Seconds)"]?.toLongFlexible() ?? 0, 0)
        return base.with {
            $0.endTime = end
            $0.pump = PumpDetails(durationSec: duration, leftMl: left, rightMl: right, totalMl: total)
        }
    }

    private static func mapBreastfeed(_ familyKey: String, _ row: [String: String]) -> NaraRecord.Activity? {
        guard let base = activity(familyKey, row, .BREASTFEED) else { return nil }
        let rawEnd = row["[Breastfeed] End Side"]
        let left = max(row["[Breastfeed] Left Duration (Seconds)"]?.toLongFlexible() ?? 0, 0)
        let right = max(row["[Breastfeed] Right Duration (Seconds)"]?.toLongFlexible() ?? 0, 0)
        return base.with {
            $0.endTime = base.startTime + (left + right) * 1000
            $0.breastfeed = BreastfeedDetails(
                beginSide: row["[Breastfeed] Begin Side"].flatMap(side),
                endSide: rawEnd.flatMap(side),
                leftDurationSec: left,
                rightDurationSec: right,
                isManualEntry: rawEnd?.hasSuffix(".nonTimer") == true
            )
        }
    }

    private static func diaper(_ row: [String: String]) -> DiaperDetails {
        let type = row["[Diaper] Type"] ?? ""
        let dirty = type.range(of: "Dirty", options: .caseInsensitive) != nil
        let wet = type.range(of: "Wet", options: .caseInsensitive) != nil
        let diaperType: DiaperType = dirty && wet ? .MIXED : dirty ? .DIRTY : wet ? .WET : .DRY
        return DiaperDetails(
            diaperType,
            color: row["[Diaper] Dirty Color"].flatMap { enumOrNil(StoolColor.self, $0) },
            texture: row["[Diaper] Dirty Texture"].flatMap { enumOrNil(StoolTexture.self, $0) },
            detail: row["[Diaper] Detail"]
        )
    }

    private static func growth(_ row: [String: String]) -> GrowthDetails {
        GrowthDetails(
            row["[Growth] Weight"].flatMap(Double.init).map { toKg($0, row["[Growth] Weight Unit"]) },
            row["[Growth] Height"].flatMap(Double.init).map { toCm($0, row["[Growth] Height Unit"]) },
            row["[Growth] Head Size"].flatMap(Double.init).map { toCm($0, row["[Growth] Head Size Unit"]) }
        )
    }

    private static func volumeMl(_ row: [String: String], _ column: String) -> Double? {
        guard let value = row[column].flatMap(Double.init) else { return nil }
        return toMl(value, row["\(column) Unit"])
    }

    static func toMl(_ value: Double, _ unit: String?) -> Double {
        switch unit?.uppercased() {
        case "FLOZ", "OZ": value * ML_PER_FLOZ
        case "L": value * 1000
        default: value
        }
    }

    static func toKg(_ value: Double, _ unit: String?) -> Double {
        switch unit?.uppercased() {
        case "LB", "LBS": value * KG_PER_LB
        case "OZ": value * KG_PER_LB / 16
        case "G": value / 1000
        default: value
        }
    }

    static func toCm(_ value: Double, _ unit: String?) -> Double {
        switch unit?.uppercased() {
        case "IN": value * CM_PER_IN
        case "MM": value / 10
        case "M": value * 100
        default: value
        }
    }

    private static func sumOrNil(_ a: Double?, _ b: Double?) -> Double? {
        a == nil && b == nil ? nil : (a ?? 0) + (b ?? 0)
    }

    private static func side(_ raw: String) -> BreastSide? {
        enumOrNil(BreastSide.self, String(raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""))
    }

    static func enumOrNil<T: CaseIterable & RawRepresentable>(_ type: T.Type, _ raw: String) -> T? where T.RawValue == String {
        let t = raw.trimmed.uppercased()
        return T.allCases.first { $0.rawValue.uppercased() == t }
    }
}

/// Deterministic UUIDs for Nara rows, so re-importing the same export upserts in place.
public enum NaraIds {
    private static func uuid(_ namespace: String, _ key: String) -> String {
        nameUUIDFromBytes(Array("nara:\(namespace):\(key)".utf8))
    }

    public static func profile(_ profileKey: String) -> String { uuid("profile", profileKey) }

    public static func activity(_ activityKey: String) -> String { uuid("activity", activityKey) }

    /// Scoped to the family so the same name in two families never collides.
    public static func caregiver(_ familyId: String, _ name: String) -> String {
        uuid("caregiver", "\(familyId):\(normalizeName(name))")
    }

    public static func normalizeName(_ name: String) -> String {
        name.trimmed.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

/// Decides whether a Nara child is the same as an existing Nestly profile.
public enum NaraProfileMatcher {
    public static func match(_ name: String, _ birthDate: LocalDate?, _ existing: [ProfileEntity]) -> ProfileEntity? {
        let n = NaraIds.normalizeName(name)
        let candidates = existing.filter { NaraIds.normalizeName($0.name) == n }
        if candidates.isEmpty { return nil }
        if let birthDate, let exact = candidates.first(where: { $0.birthDate == birthDate }) { return exact }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
