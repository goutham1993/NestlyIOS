import Foundation

public protocol Copyable {}
public extension Copyable {
    func with(_ change: (inout Self) -> Void) -> Self {
        var copy = self
        change(&copy)
        return copy
    }
}

public struct BottleDetails: Equatable, Hashable, Sendable, Copyable {
    public var milkType: MilkType?
    public var breastMilkMl: Double?
    public var formulaMl: Double?
    public var formulaName: String?
    public var totalMl: Double?

    public init(_ milkType: MilkType? = nil, breastMilkMl: Double? = nil, formulaMl: Double? = nil, formulaName: String? = nil, totalMl: Double? = nil) {
        self.milkType = milkType
        self.breastMilkMl = breastMilkMl
        self.formulaMl = formulaMl
        self.formulaName = formulaName
        self.totalMl = totalMl
    }
}

public struct PumpDetails: Equatable, Hashable, Sendable, Copyable {
    public var durationSec: Int64
    public var leftMl: Double?
    public var rightMl: Double?
    public var totalMl: Double?

    public init(durationSec: Int64, leftMl: Double? = nil, rightMl: Double? = nil, totalMl: Double? = nil) {
        self.durationSec = durationSec
        self.leftMl = leftMl
        self.rightMl = rightMl
        self.totalMl = totalMl
    }
}

public struct BreastfeedDetails: Equatable, Hashable, Sendable, Copyable {
    public var beginSide: BreastSide?
    public var endSide: BreastSide?
    public var leftDurationSec: Int64
    public var rightDurationSec: Int64
    public var isManualEntry: Bool

    public init(beginSide: BreastSide? = nil, endSide: BreastSide? = nil, leftDurationSec: Int64 = 0, rightDurationSec: Int64 = 0, isManualEntry: Bool = false) {
        self.beginSide = beginSide
        self.endSide = endSide
        self.leftDurationSec = leftDurationSec
        self.rightDurationSec = rightDurationSec
        self.isManualEntry = isManualEntry
    }
}

public struct DiaperDetails: Equatable, Hashable, Sendable, Copyable {
    public var diaperType: DiaperType
    public var color: StoolColor?
    public var texture: StoolTexture?
    public var detail: String?
    public var hasRash: Bool?

    public init(_ diaperType: DiaperType, color: StoolColor? = nil, texture: StoolTexture? = nil, detail: String? = nil, hasRash: Bool? = nil) {
        self.diaperType = diaperType
        self.color = color
        self.texture = texture
        self.detail = detail
        self.hasRash = hasRash
    }
}

public struct GrowthDetails: Equatable, Hashable, Sendable {
    public var weightKg: Double?
    public var heightCm: Double?
    public var headCm: Double?

    public init(_ weightKg: Double? = nil, _ heightCm: Double? = nil, _ headCm: Double? = nil) {
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.headCm = headCm
    }
}

public struct MilestoneDetails: Equatable, Hashable, Sendable {
    public var title: String
    public var milestoneKey: String?

    public init(_ title: String, _ milestoneKey: String? = nil) {
        self.title = title
        self.milestoneKey = milestoneKey
    }
}

public struct SolidsDetails: Equatable, Hashable, Sendable {
    public var mealType: MealType?
    public var foods: [String]
    /// When true, this solids entry anchors next-feed / FEED reminders like milk.
    public var resetsFeedSchedule: Bool

    public init(_ mealType: MealType?, _ foods: [String] = [], resetsFeedSchedule: Bool = true) {
        self.mealType = mealType
        self.foods = foods
        self.resetsFeedSchedule = resetsFeedSchedule
    }
}

public struct RoutineDetails: Equatable, Hashable, Sendable {
    public var name: String
    public init(_ name: String) { self.name = name }
}

public struct BabyFirstDetails: Equatable, Hashable, Sendable {
    public var title: String
    public init(_ title: String) { self.title = title }
}

/// Also used by VITAMIN_D rows.
public struct MedicalDetails: Equatable, Hashable, Sendable {
    public var temperatureC: Double?
    public var medicationName: String?
    public var dose: Double?
    public var doseUnit: String?

    public init(temperatureC: Double? = nil, medicationName: String? = nil, dose: Double? = nil, doseUnit: String? = nil) {
        self.temperatureC = temperatureC
        self.medicationName = medicationName
        self.dose = dose
        self.doseUnit = doseUnit
    }
}

public struct VaccineDetails: Equatable, Hashable, Sendable {
    public var vaccines: [String]
    public init(_ vaccines: [String]) { self.vaccines = vaccines }
}

public struct ActivityEntity: Equatable, Hashable, Identifiable, Sendable, Copyable {
    public var id: String
    public var familyId: String
    public var profileId: String?
    public var type: ActivityType
    public var startTime: EpochMs
    public var endTime: EpochMs?
    public var timeZone: String
    public var note: String?
    public var createdById: String?
    public var updatedById: String?
    public var bottle: BottleDetails?
    public var pump: PumpDetails?
    public var breastfeed: BreastfeedDetails?
    public var diaper: DiaperDetails?
    public var growth: GrowthDetails?
    public var milestone: MilestoneDetails?
    public var solids: SolidsDetails?
    public var routine: RoutineDetails?
    public var babyFirst: BabyFirstDetails?
    public var medical: MedicalDetails?
    public var vaccine: VaccineDetails?
    /// Storage object path (`{family}/{activity}/{file}`) or, before upload, an absolute local file path.
    public var photoUri: String?
    public var comboGroupId: String?
    public var createdAt: EpochMs
    public var updatedAt: EpochMs
    public var deletedAt: EpochMs?
    public var version: Int

    public init(
        id: String,
        familyId: String,
        profileId: String?,
        type: ActivityType,
        startTime: EpochMs,
        endTime: EpochMs? = nil,
        timeZone: String,
        note: String? = nil,
        createdById: String? = nil,
        updatedById: String? = nil,
        bottle: BottleDetails? = nil,
        pump: PumpDetails? = nil,
        breastfeed: BreastfeedDetails? = nil,
        diaper: DiaperDetails? = nil,
        growth: GrowthDetails? = nil,
        milestone: MilestoneDetails? = nil,
        solids: SolidsDetails? = nil,
        routine: RoutineDetails? = nil,
        babyFirst: BabyFirstDetails? = nil,
        medical: MedicalDetails? = nil,
        vaccine: VaccineDetails? = nil,
        photoUri: String? = nil,
        comboGroupId: String? = nil,
        createdAt: EpochMs,
        updatedAt: EpochMs,
        deletedAt: EpochMs? = nil,
        version: Int = 1
    ) {
        self.id = id
        self.familyId = familyId
        self.profileId = profileId
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.timeZone = timeZone
        self.note = note
        self.createdById = createdById
        self.updatedById = updatedById
        self.bottle = bottle
        self.pump = pump
        self.breastfeed = breastfeed
        self.diaper = diaper
        self.growth = growth
        self.milestone = milestone
        self.solids = solids
        self.routine = routine
        self.babyFirst = babyFirst
        self.medical = medical
        self.vaccine = vaccine
        self.photoUri = photoUri
        self.comboGroupId = comboGroupId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }
}

public struct FamilyEntity: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String?
    public var createdAt: EpochMs
    public var updatedAt: EpochMs
    public var deletedAt: EpochMs?
    public var version: Int

    public init(id: String, name: String? = nil, createdAt: EpochMs, updatedAt: EpochMs, deletedAt: EpochMs? = nil, version: Int = 1) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }
}

public struct CaregiverEntity: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var familyId: String
    public var name: String
    public var userId: String?
    public var role: String
    public var createdAt: EpochMs
    public var updatedAt: EpochMs
    public var deletedAt: EpochMs?
    public var version: Int

    public init(id: String, familyId: String, name: String, userId: String? = nil, role: String = "MEMBER", createdAt: EpochMs, updatedAt: EpochMs, deletedAt: EpochMs? = nil, version: Int = 1) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.userId = userId
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }
}

public struct ProfileEntity: Equatable, Hashable, Identifiable, Sendable, Copyable {
    public var id: String
    public var familyId: String
    public var name: String
    public var birthDate: LocalDate?
    public var adjustedBirthDate: LocalDate?
    public var sex: Sex?
    public var profileType: ProfileType
    /// Storage path in `profile-photos`, or a staged local file until save. Nil keeps the letter monogram.
    public var photoPath: String?
    /// When the current photo file was saved. Nil when there is no photo.
    public var photoUpdatedAt: EpochMs?
    public var createdAt: EpochMs
    public var updatedAt: EpochMs
    public var deletedAt: EpochMs?
    public var version: Int

    public init(id: String, familyId: String, name: String, birthDate: LocalDate? = nil, adjustedBirthDate: LocalDate? = nil, sex: Sex? = nil, profileType: ProfileType = .CHILD, photoPath: String? = nil, photoUpdatedAt: EpochMs? = nil, createdAt: EpochMs, updatedAt: EpochMs, deletedAt: EpochMs? = nil, version: Int = 1) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.birthDate = birthDate
        self.adjustedBirthDate = adjustedBirthDate
        self.sex = sex
        self.profileType = profileType
        self.photoPath = photoPath
        self.photoUpdatedAt = photoUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }
}

public struct ReminderEntity: Equatable, Hashable, Identifiable, Sendable, Copyable {
    public var id: String
    public var familyId: String
    public var caregiverId: String
    public var profileId: String?
    public var kind: ReminderKind
    public var intervalMinutes: Int
    public var enabled: Bool
    public var createdAt: EpochMs
    public var updatedAt: EpochMs
    public var version: Int

    public init(id: String, familyId: String, caregiverId: String, profileId: String?, kind: ReminderKind, intervalMinutes: Int, enabled: Bool, createdAt: EpochMs, updatedAt: EpochMs, version: Int = 1) {
        self.id = id
        self.familyId = familyId
        self.caregiverId = caregiverId
        self.profileId = profileId
        self.kind = kind
        self.intervalMinutes = intervalMinutes
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }
}

public struct AppointmentEntity: Equatable, Hashable, Identifiable, Sendable, Copyable {
    public var id: String
    public var familyId: String
    public var profileId: String
    public var title: String
    public var doctorName: String?
    public var location: String?
    public var startsAt: EpochMs
    public var timeZone: String
    public var notes: String?
    public var reminderLead: AppointmentReminderLead
    public var createdAt: EpochMs
    public var updatedAt: EpochMs
    public var deletedAt: EpochMs?
    public var version: Int

    public init(id: String, familyId: String, profileId: String, title: String, doctorName: String? = nil, location: String? = nil, startsAt: EpochMs, timeZone: String, notes: String? = nil, reminderLead: AppointmentReminderLead = .NONE, createdAt: EpochMs, updatedAt: EpochMs, deletedAt: EpochMs? = nil, version: Int = 1) {
        self.id = id
        self.familyId = familyId
        self.profileId = profileId
        self.title = title
        self.doctorName = doctorName
        self.location = location
        self.startsAt = startsAt
        self.timeZone = timeZone
        self.notes = notes
        self.reminderLead = reminderLead
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }
}

public struct AppointmentQuestionEntity: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var appointmentId: String
    public var familyId: String
    public var text: String
    public var isDone: Bool
    public var sortOrder: Int
    public var createdAt: EpochMs
    public var updatedAt: EpochMs
    public var deletedAt: EpochMs?
    public var version: Int

    public init(id: String, appointmentId: String, familyId: String, text: String, isDone: Bool = false, sortOrder: Int = 0, createdAt: EpochMs, updatedAt: EpochMs, deletedAt: EpochMs? = nil, version: Int = 1) {
        self.id = id
        self.appointmentId = appointmentId
        self.familyId = familyId
        self.text = text
        self.isDone = isDone
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }
}

public struct NoteEntity: Equatable, Hashable, Identifiable, Sendable, Copyable {
    public var id: String
    public var familyId: String
    public var profileId: String
    public var title: String
    public var body: String
    public var createdAt: EpochMs
    public var updatedAt: EpochMs
    public var deletedAt: EpochMs?
    public var version: Int

    public init(id: String, familyId: String, profileId: String, title: String = "", body: String = "", createdAt: EpochMs, updatedAt: EpochMs, deletedAt: EpochMs? = nil, version: Int = 1) {
        self.id = id
        self.familyId = familyId
        self.profileId = profileId
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }
}
