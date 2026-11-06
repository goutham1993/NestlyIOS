import Foundation

/// Who and where an entry is being saved for.
public struct EntryContext: Copyable {
    public var familyId: String
    public var profileId: String
    public var caregiverId: String?
    public var timeZone: String
    public var now: EpochMs
    public var newId: () -> String

    public init(familyId: String, profileId: String, caregiverId: String?, timeZone: String, now: EpochMs, newId: @escaping () -> String) {
        self.familyId = familyId
        self.profileId = profileId
        self.caregiverId = caregiverId
        self.timeZone = timeZone
        self.now = now
        self.newId = newId
    }
}

public enum EntryBuilder {
    public static let VITAMIN_D_NAME = "Vitamin D"
    public static let VITAMIN_D_DEFAULT_DOSE = 400.0
    public static let VITAMIN_D_DEFAULT_UNIT = "IU"

    public static func fahrenheitToCelsius(_ f: Double) -> Double { (f - 32) * 5 / 9 }
    public static func celsiusToFahrenheit(_ c: Double) -> Double { c * 9 / 5 + 32 }

    public static func canSave(_ kind: EntryKind, _ d: EntryDraft) -> Bool {
        switch kind {
        case .BREASTFEED: return d.leftSec + d.rightSec > 0
        case .BOTTLE: return d.bottleMl != nil || d.milkType != nil
        case .SOLIDS: return d.mealType != nil || !d.foods.isEmpty
        case .COMBO: return canSave(.BREASTFEED, d) || canSave(.BOTTLE, d)
        case .PUMP: return d.pumpSec > 0 || d.pumpTotalComputed != nil
        case .DIAPER: return d.wet || d.dirty || d.dry
        case .SLEEP:
            guard let end = d.endTime else { return false }
            return end > d.startTime
        case .ROUTINE: return !d.routineName.isNullOrBlank
        case .BABY_FIRST: return !d.babyFirstTitle.isBlank
        case .GROWTH: return d.weightKg != nil || d.heightCm != nil || d.headCm != nil
        case .MILESTONE: return !d.milestoneTitle.isBlank
        case .MEDICAL: return d.temperatureF != nil || !d.medicationName.isNullOrBlank
        case .VACCINE: return !d.vaccines.isEmpty
        case .VITAMIN_D: return true
        }
    }

    /// Builds the rows to upsert. [existing] is the row being edited (its id and audit fields are
    /// kept). Combo Feed can produce two rows linked by a shared group id.
    public static func build(_ kind: EntryKind, _ d: EntryDraft, _ ctx: EntryContext, existing: ActivityEntity? = nil) -> [ActivityEntity] {
        if kind == .COMBO {
            var parts: [EntryKind] = []
            if canSave(.BREASTFEED, d) { parts.append(.BREASTFEED) }
            if canSave(.BOTTLE, d) { parts.append(.BOTTLE) }
            let group = parts.count > 1 ? ctx.newId() : nil
            return parts.flatMap { build($0, d, ctx) }.map { $0.with { $0.comboGroupId = group } }
        }

        let base = existing ?? ActivityEntity(
            id: ctx.newId(),
            familyId: ctx.familyId,
            profileId: kind == .PUMP ? nil : ctx.profileId,
            type: typeOf(kind),
            startTime: d.startTime,
            timeZone: ctx.timeZone,
            createdById: ctx.caregiverId,
            createdAt: ctx.now,
            updatedAt: ctx.now
        )
        var row = base.with {
            $0.startTime = d.startTime
            $0.endTime = nil
            $0.note = d.note.trimmedNilIfEmpty
            $0.photoUri = d.photoPath
            $0.updatedById = ctx.caregiverId ?? base.updatedById
        }
        switch kind {
        case .BREASTFEED:
            row.endTime = d.startTime + (d.leftSec + d.rightSec) * 1000
            row.breastfeed = BreastfeedDetails(
                beginSide: d.beginSide ?? defaultSide(d),
                endSide: d.endSide ?? defaultSide(d),
                leftDurationSec: d.leftSec,
                rightDurationSec: d.rightSec,
                isManualEntry: existing?.breastfeed?.isManualEntry ?? false
            )
        case .BOTTLE:
            row.bottle = BottleDetails(
                d.milkType,
                breastMilkMl: d.milkType == .BREAST_MILK ? d.bottleMl : nil,
                formulaMl: d.milkType == .FORMULA ? d.bottleMl : nil,
                formulaName: d.milkType == .FORMULA ? d.formulaName : nil,
                totalMl: d.bottleMl
            )
        case .SOLIDS:
            row.solids = SolidsDetails(d.mealType, d.foods)
        case .PUMP:
            row.endTime = d.startTime + d.pumpSec * 1000
            row.pump = PumpDetails(
                durationSec: d.pumpSec,
                leftMl: d.pumpMode == .LEFT_RIGHT ? d.pumpLeftMl : nil,
                rightMl: d.pumpMode == .LEFT_RIGHT ? d.pumpRightMl : nil,
                totalMl: d.pumpTotalComputed
            )
        case .DIAPER:
            let type: DiaperType = d.wet && d.dirty ? .MIXED : d.dirty ? .DIRTY : d.wet ? .WET : .DRY
            row.diaper = DiaperDetails(
                type,
                color: d.dirty ? d.stoolColor : nil,
                texture: d.dirty ? d.stoolTexture : nil,
                hasRash: d.rash
            )
        case .SLEEP:
            row.endTime = d.endTime
        case .ROUTINE:
            row.routine = RoutineDetails((d.routineName ?? "").trimmed)
        case .BABY_FIRST:
            row.babyFirst = BabyFirstDetails(d.babyFirstTitle.trimmed)
        case .GROWTH:
            row.growth = GrowthDetails(d.weightKg, d.heightCm, d.headCm)
        case .MILESTONE:
            row.milestone = MilestoneDetails(d.milestoneTitle, d.milestoneKey)
        case .MEDICAL:
            row.medical = MedicalDetails(
                temperatureC: d.temperatureF.map(fahrenheitToCelsius),
                medicationName: d.medicationName?.trimmedNilIfEmpty,
                dose: d.dose,
                doseUnit: d.doseUnit
            )
        case .VACCINE:
            row.vaccine = VaccineDetails(d.vaccines)
        case .VITAMIN_D:
            row.medical = MedicalDetails(
                medicationName: VITAMIN_D_NAME,
                dose: d.dose,
                doseUnit: d.dose != nil ? d.doseUnit : nil
            )
        case .COMBO:
            fatalError("handled above")
        }
        return [row]
    }

    /// Editing a saved combo: rebuilds each part onto its existing row (keeping ids/audit fields),
    /// creates a missing part, and reports parts that were cleared so the caller can delete them.
    public static func buildComboEdit(_ d: EntryDraft, _ ctx: EntryContext, existing: [ActivityEntity]) -> (rows: [ActivityEntity], removed: [ActivityEntity]) {
        let oldBreast = existing.first { $0.type == .BREASTFEED }
        let oldBottle = existing.first { $0.type == .BOTTLE_FEED }
        var rows: [ActivityEntity] = []
        var removed: [ActivityEntity] = []
        if canSave(.BREASTFEED, d) {
            rows += build(.BREASTFEED, d, ctx, existing: oldBreast)
        } else if let oldBreast {
            removed.append(oldBreast)
        }
        if canSave(.BOTTLE, d) {
            rows += build(.BOTTLE, d, ctx, existing: oldBottle)
        } else if let oldBottle {
            removed.append(oldBottle)
        }
        let group = rows.count > 1 ? (existing.compactMap(\.comboGroupId).first ?? ctx.newId()) : nil
        return (rows.map { $0.with { $0.comboGroupId = group } }, removed)
    }

    /// Fills a draft from a saved row, for editing.
    public static func draftOf(_ a: ActivityEntity) -> EntryDraft {
        EntryDraft(
            startTime: a.startTime,
            endTime: a.endTime,
            note: a.note ?? "",
            photoPath: a.photoUri,
            milkType: a.bottle?.milkType,
            bottleMl: a.bottle?.totalMl ?? a.bottle?.breastMilkMl ?? a.bottle?.formulaMl,
            formulaName: a.bottle?.formulaName,
            leftSec: a.breastfeed?.leftDurationSec ?? 0,
            rightSec: a.breastfeed?.rightDurationSec ?? 0,
            beginSide: a.breastfeed?.beginSide,
            endSide: a.breastfeed?.endSide,
            mealType: a.solids?.mealType,
            foods: a.solids?.foods ?? [],
            pumpMode: (a.pump?.leftMl != nil || a.pump?.rightMl != nil) ? .LEFT_RIGHT : .TOTAL,
            pumpSec: a.pump?.durationSec ?? 0,
            pumpLeftMl: a.pump?.leftMl,
            pumpRightMl: a.pump?.rightMl,
            pumpTotalMl: a.pump?.totalMl,
            wet: a.diaper?.diaperType == .WET || a.diaper?.diaperType == .MIXED,
            dirty: a.diaper?.diaperType == .DIRTY || a.diaper?.diaperType == .MIXED,
            dry: a.diaper?.diaperType == .DRY,
            stoolColor: a.diaper?.color,
            stoolTexture: a.diaper?.texture,
            rash: a.diaper?.hasRash ?? false,
            routineName: a.routine?.name,
            babyFirstTitle: a.babyFirst?.title ?? "",
            weightKg: a.growth?.weightKg,
            heightCm: a.growth?.heightCm,
            headCm: a.growth?.headCm,
            milestoneKey: a.milestone?.milestoneKey,
            milestoneTitle: a.milestone?.title ?? "",
            temperatureF: a.medical?.temperatureC.map(celsiusToFahrenheit),
            medicationName: a.medical?.medicationName,
            dose: a.medical?.dose,
            doseUnit: a.medical?.doseUnit,
            vaccines: a.vaccine?.vaccines ?? []
        )
    }

    /// Draft for a saved combo (breastfeed + bottle rows sharing a group id).
    public static func draftOfCombo(_ rows: [ActivityEntity]) -> EntryDraft {
        let breast = rows.first { $0.type == .BREASTFEED }
        let bottle = rows.first { $0.type == .BOTTLE_FEED }
        var d = draftOf(breast ?? bottle ?? rows[0])
        if let bottle, breast != nil {
            let b = draftOf(bottle)
            d.milkType = b.milkType
            d.bottleMl = b.bottleMl
            d.formulaName = b.formulaName
            if d.note.isEmpty { d.note = b.note }
            if d.photoPath == nil { d.photoPath = b.photoPath }
        }
        return d
    }

    public static func typeOf(_ kind: EntryKind) -> ActivityType {
        switch kind {
        case .BREASTFEED: .BREASTFEED
        case .BOTTLE: .BOTTLE_FEED
        case .SOLIDS: .SOLIDS
        case .COMBO: .BREASTFEED
        case .PUMP: .PUMP
        case .DIAPER: .DIAPER
        case .SLEEP: .SLEEP
        case .ROUTINE: .ROUTINE
        case .BABY_FIRST: .BABY_FIRST
        case .GROWTH: .GROWTH
        case .MILESTONE: .MILESTONE
        case .MEDICAL: .MEDICAL
        case .VACCINE: .VACCINE
        case .VITAMIN_D: .VITAMIN_D
        }
    }

    private static func defaultSide(_ d: EntryDraft) -> BreastSide? {
        if d.leftSec > 0 && d.rightSec == 0 { return .LEFT }
        if d.rightSec > 0 && d.leftSec == 0 { return .RIGHT }
        if d.leftSec > 0 { return .LEFT }
        return nil
    }
}
