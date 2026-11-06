import Foundation

/// Nestly backup CSV: one row per family / caregiver / profile / activity, keyed by `record`.
/// Column names and value formats match the Android export so files move between platforms.
public enum NestlyCsv {
    public static let LIST_SEP = "|"

    public static let HEADER = [
        "record", "id", "familyId", "profileId", "name", "birthDate", "sex", "profileType", "type",
        "startTime", "endTime", "timeZone", "note", "photoUri", "comboGroupId", "createdById", "updatedById",
        "createdAt", "updatedAt",
        "bottle_milkType", "bottle_breastMilkMl", "bottle_formulaMl", "bottle_formulaName", "bottle_totalMl",
        "pump_durationSec", "pump_leftMl", "pump_rightMl", "pump_totalMl",
        "breast_beginSide", "breast_endSide", "breast_leftDurationSec", "breast_rightDurationSec", "breast_isManualEntry",
        "diaper_diaperType", "diaper_color", "diaper_texture", "diaper_detail", "diaper_hasRash",
        "growth_weightKg", "growth_heightCm", "growth_headCm",
        "milestone_title", "milestone_milestoneKey",
        "solids_mealType", "solids_foods",
        "routine_name", "babyFirst_title",
        "medical_temperatureC", "medical_medicationName", "medical_dose", "medical_doseUnit",
        "vaccine_vaccines",
    ]

    public static func escape(_ value: String?) -> String {
        guard let value else { return "" }
        if value.contains(",") || value.contains("\"") || value.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    public static func row(_ values: [String: String?]) -> String {
        HEADER.map { escape(values[$0] ?? nil) }.joined(separator: ",")
    }

    /// Kotlin `Double.toString()` style: "120.0", "29.57".
    static func num(_ d: Double?) -> String? { d.map { "\($0)" } }

    public static func familyRow(_ f: FamilyEntity) -> String {
        row(["record": "FAMILY", "id": f.id, "name": f.name, "createdAt": "\(f.createdAt)", "updatedAt": "\(f.updatedAt)"])
    }

    public static func caregiverRow(_ c: CaregiverEntity) -> String {
        row(["record": "CAREGIVER", "id": c.id, "familyId": c.familyId, "name": c.name, "createdAt": "\(c.createdAt)", "updatedAt": "\(c.updatedAt)"])
    }

    public static func profileRow(_ p: ProfileEntity) -> String {
        row([
            "record": "PROFILE", "id": p.id, "familyId": p.familyId, "name": p.name,
            "birthDate": p.birthDate?.description, "sex": p.sex?.rawValue, "profileType": p.profileType.rawValue,
            "createdAt": "\(p.createdAt)", "updatedAt": "\(p.updatedAt)",
        ])
    }

    public static func activityRow(_ a: ActivityEntity) -> String {
        var m: [String: String?] = [
            "record": "ACTIVITY", "id": a.id, "familyId": a.familyId, "profileId": a.profileId, "type": a.type.rawValue,
            "startTime": "\(a.startTime)", "endTime": a.endTime.map { "\($0)" }, "timeZone": a.timeZone, "note": a.note,
            "photoUri": a.photoUri, "comboGroupId": a.comboGroupId, "createdById": a.createdById, "updatedById": a.updatedById,
            "createdAt": "\(a.createdAt)", "updatedAt": "\(a.updatedAt)",
        ]
        if let b = a.bottle {
            m["bottle_milkType"] = b.milkType?.rawValue
            m["bottle_breastMilkMl"] = num(b.breastMilkMl)
            m["bottle_formulaMl"] = num(b.formulaMl)
            m["bottle_formulaName"] = b.formulaName
            m["bottle_totalMl"] = num(b.totalMl)
        }
        if let p = a.pump {
            m["pump_durationSec"] = "\(p.durationSec)"
            m["pump_leftMl"] = num(p.leftMl)
            m["pump_rightMl"] = num(p.rightMl)
            m["pump_totalMl"] = num(p.totalMl)
        }
        if let b = a.breastfeed {
            m["breast_beginSide"] = b.beginSide?.rawValue
            m["breast_endSide"] = b.endSide?.rawValue
            m["breast_leftDurationSec"] = "\(b.leftDurationSec)"
            m["breast_rightDurationSec"] = "\(b.rightDurationSec)"
            m["breast_isManualEntry"] = "\(b.isManualEntry)"
        }
        if let d = a.diaper {
            m["diaper_diaperType"] = d.diaperType.rawValue
            m["diaper_color"] = d.color?.rawValue
            m["diaper_texture"] = d.texture?.rawValue
            m["diaper_detail"] = d.detail
            m["diaper_hasRash"] = d.hasRash.map { "\($0)" }
        }
        if let g = a.growth {
            m["growth_weightKg"] = num(g.weightKg)
            m["growth_heightCm"] = num(g.heightCm)
            m["growth_headCm"] = num(g.headCm)
        }
        if let ms = a.milestone {
            m["milestone_title"] = ms.title
            m["milestone_milestoneKey"] = ms.milestoneKey
        }
        if let s = a.solids {
            m["solids_mealType"] = s.mealType?.rawValue
            m["solids_foods"] = s.foods.joined(separator: LIST_SEP)
        }
        if let r = a.routine { m["routine_name"] = r.name }
        if let b = a.babyFirst { m["babyFirst_title"] = b.title }
        if let med = a.medical {
            m["medical_temperatureC"] = num(med.temperatureC)
            m["medical_medicationName"] = med.medicationName
            m["medical_dose"] = num(med.dose)
            m["medical_doseUnit"] = med.doseUnit
        }
        if let v = a.vaccine { m["vaccine_vaccines"] = v.vaccines.joined(separator: LIST_SEP) }
        return row(m)
    }

    /// Full file: UTF-8 BOM, header, then rows, LF line endings.
    public static func document(families: [FamilyEntity], caregivers: [CaregiverEntity], profiles: [ProfileEntity], activities: [ActivityEntity]) -> String {
        var out = "\u{FEFF}" + HEADER.joined(separator: ",") + "\n"
        for f in families { out += familyRow(f) + "\n" }
        for c in caregivers { out += caregiverRow(c) + "\n" }
        for p in profiles { out += profileRow(p) + "\n" }
        for a in activities { out += activityRow(a) + "\n" }
        return out
    }

    private static func require(_ row: [String: String], _ key: String) throws -> String {
        guard let v = row[key] else { throw ImportError("Missing column \(key)") }
        return v
    }

    private static func long(_ s: String?) -> Int64? { s.flatMap { Int64($0) } }
    private static func dbl(_ s: String?) -> Double? { s.flatMap { Double($0) } }
    private static func bool(_ s: String?) -> Bool? { s == "true" ? true : (s == "false" ? false : nil) }

    public static func parseFamily(_ row: [String: String], now: EpochMs) throws -> FamilyEntity {
        FamilyEntity(id: try require(row, "id"), name: row["name"], createdAt: long(row["createdAt"]) ?? now, updatedAt: long(row["updatedAt"]) ?? now)
    }

    public static func parseCaregiver(_ row: [String: String], now: EpochMs) throws -> CaregiverEntity {
        CaregiverEntity(id: try require(row, "id"), familyId: try require(row, "familyId"), name: try require(row, "name"), createdAt: long(row["createdAt"]) ?? now, updatedAt: long(row["updatedAt"]) ?? now)
    }

    public static func parseProfile(_ row: [String: String], now: EpochMs) throws -> ProfileEntity {
        var birthDate: LocalDate?
        if let raw = row["birthDate"] {
            guard let parsed = LocalDate.parse(raw) else { throw ImportError("Invalid birthDate \(raw)") }
            birthDate = parsed
        }
        return ProfileEntity(
            id: try require(row, "id"),
            familyId: try require(row, "familyId"),
            name: try require(row, "name"),
            birthDate: birthDate,
            sex: row["sex"].flatMap(Sex.init(rawValue:)),
            profileType: row["profileType"].flatMap(ProfileType.init(rawValue:)) ?? .CHILD,
            createdAt: long(row["createdAt"]) ?? now,
            updatedAt: long(row["updatedAt"]) ?? now
        )
    }

    public static func parseActivity(_ row: [String: String], now: EpochMs) throws -> ActivityEntity {
        let rawType = try require(row, "type")
        guard let type = ActivityType(rawValue: rawType) else { throw ImportError("Unknown activity type \(rawType)") }
        let rawStart = try require(row, "startTime")
        guard let start = Int64(rawStart) else { throw ImportError("Invalid startTime \(rawStart)") }
        return ActivityEntity(
            id: try require(row, "id"),
            familyId: try require(row, "familyId"),
            profileId: row["profileId"],
            type: type,
            startTime: start,
            endTime: long(row["endTime"]),
            timeZone: row["timeZone"] ?? "UTC",
            note: row["note"],
            createdById: row["createdById"],
            updatedById: row["updatedById"],
            bottle: bottleOf(row),
            pump: pumpOf(row),
            breastfeed: breastOf(row),
            diaper: diaperOf(row),
            growth: growthOf(row),
            milestone: row["milestone_title"].map { MilestoneDetails($0, row["milestone_milestoneKey"]) },
            solids: solidsOf(row),
            routine: row["routine_name"].map(RoutineDetails.init),
            babyFirst: row["babyFirst_title"].map(BabyFirstDetails.init),
            medical: medicalOf(row),
            vaccine: row["vaccine_vaccines"].map { VaccineDetails(split($0)) },
            photoUri: row["photoUri"],
            comboGroupId: row["comboGroupId"],
            createdAt: long(row["createdAt"]) ?? now,
            updatedAt: long(row["updatedAt"]) ?? now
        )
    }

    private static func split(_ s: String) -> [String] {
        s.components(separatedBy: LIST_SEP).filter { !$0.isEmpty }
    }

    private static func bottleOf(_ row: [String: String]) -> BottleDetails? {
        guard ["bottle_milkType", "bottle_totalMl", "bottle_breastMilkMl", "bottle_formulaMl"].contains(where: { row[$0] != nil }) else { return nil }
        return BottleDetails(
            row["bottle_milkType"].flatMap(MilkType.init(rawValue:)),
            breastMilkMl: dbl(row["bottle_breastMilkMl"]),
            formulaMl: dbl(row["bottle_formulaMl"]),
            formulaName: row["bottle_formulaName"],
            totalMl: dbl(row["bottle_totalMl"])
        )
    }

    private static func pumpOf(_ row: [String: String]) -> PumpDetails? {
        guard let duration = long(row["pump_durationSec"]) else { return nil }
        return PumpDetails(durationSec: duration, leftMl: dbl(row["pump_leftMl"]), rightMl: dbl(row["pump_rightMl"]), totalMl: dbl(row["pump_totalMl"]))
    }

    private static func breastOf(_ row: [String: String]) -> BreastfeedDetails? {
        guard row["breast_leftDurationSec"] != nil || row["breast_rightDurationSec"] != nil else { return nil }
        return BreastfeedDetails(
            beginSide: row["breast_beginSide"].flatMap(BreastSide.init(rawValue:)),
            endSide: row["breast_endSide"].flatMap(BreastSide.init(rawValue:)),
            leftDurationSec: long(row["breast_leftDurationSec"]) ?? 0,
            rightDurationSec: long(row["breast_rightDurationSec"]) ?? 0,
            isManualEntry: bool(row["breast_isManualEntry"]) ?? false
        )
    }

    private static func diaperOf(_ row: [String: String]) -> DiaperDetails? {
        guard let type = row["diaper_diaperType"].flatMap(DiaperType.init(rawValue:)) else { return nil }
        return DiaperDetails(
            type,
            color: row["diaper_color"].flatMap(StoolColor.init(rawValue:)),
            texture: row["diaper_texture"].flatMap(StoolTexture.init(rawValue:)),
            detail: row["diaper_detail"],
            hasRash: bool(row["diaper_hasRash"])
        )
    }

    private static func growthOf(_ row: [String: String]) -> GrowthDetails? {
        guard ["growth_weightKg", "growth_heightCm", "growth_headCm"].contains(where: { row[$0] != nil }) else { return nil }
        return GrowthDetails(dbl(row["growth_weightKg"]), dbl(row["growth_heightCm"]), dbl(row["growth_headCm"]))
    }

    private static func solidsOf(_ row: [String: String]) -> SolidsDetails? {
        guard row["solids_mealType"] != nil || row["solids_foods"] != nil else { return nil }
        return SolidsDetails(row["solids_mealType"].flatMap(MealType.init(rawValue:)), row["solids_foods"].map(split) ?? [])
    }

    private static func medicalOf(_ row: [String: String]) -> MedicalDetails? {
        guard ["medical_temperatureC", "medical_medicationName", "medical_dose"].contains(where: { row[$0] != nil }) else { return nil }
        return MedicalDetails(
            temperatureC: dbl(row["medical_temperatureC"]),
            medicationName: row["medical_medicationName"],
            dose: dbl(row["medical_dose"]),
            doseUnit: row["medical_doseUnit"]
        )
    }
}
