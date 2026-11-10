import Foundation

// Row shapes exchanged with PostgREST. Encoding writes every column, including explicit nulls,
// so an update can clear a value. Timestamps travel as ISO-8601 strings.

private extension KeyedEncodingContainer {
    /// Encodes `nil` as JSON null instead of omitting the key.
    mutating func put<T: Encodable>(_ value: T?, _ key: Key) throws {
        if let value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) }
    }
}

public struct FamilyDto: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var version: Int

    enum CodingKeys: String, CodingKey {
        case id, name, version
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public init(id: String, name: String?, createdAt: String, updatedAt: String, deletedAt: String?, version: Int) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.put(name, .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.put(deletedAt, .deletedAt)
        try c.encode(version, forKey: .version)
    }

    public func toEntity() throws -> FamilyEntity {
        FamilyEntity(id: id, name: name, createdAt: try createdAt.isoToMillis(), updatedAt: try updatedAt.isoToMillis(), deletedAt: try deletedAt?.isoToMillis(), version: version)
    }
}

public extension FamilyEntity {
    func toDto() -> FamilyDto {
        FamilyDto(id: id, name: name, createdAt: createdAt.toIso(), updatedAt: updatedAt.toIso(), deletedAt: deletedAt?.toIso(), version: version)
    }
}

public struct CaregiverDto: Codable, Equatable, Sendable {
    public var id: String
    public var familyId: String
    public var userId: String?
    public var name: String
    public var role: String
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var version: Int

    enum CodingKeys: String, CodingKey {
        case id, name, role, version
        case familyId = "family_id", userId = "user_id"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    public init(id: String, familyId: String, userId: String?, name: String, role: String, createdAt: String, updatedAt: String, deletedAt: String?, version: Int) {
        self.id = id
        self.familyId = familyId
        self.userId = userId
        self.name = name
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        familyId = try c.decode(String.self, forKey: .familyId)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "MEMBER"
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyId, forKey: .familyId)
        try c.put(userId, .userId)
        try c.encode(name, forKey: .name)
        try c.encode(role, forKey: .role)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.put(deletedAt, .deletedAt)
        try c.encode(version, forKey: .version)
    }

    public func toEntity() throws -> CaregiverEntity {
        CaregiverEntity(id: id, familyId: familyId, name: name, userId: userId, role: role, createdAt: try createdAt.isoToMillis(), updatedAt: try updatedAt.isoToMillis(), deletedAt: try deletedAt?.isoToMillis(), version: version)
    }
}

public extension CaregiverEntity {
    func toDto() -> CaregiverDto {
        CaregiverDto(id: id, familyId: familyId, userId: userId, name: name, role: role, createdAt: createdAt.toIso(), updatedAt: updatedAt.toIso(), deletedAt: deletedAt?.toIso(), version: version)
    }
}

public struct ProfileDto: Codable, Equatable, Sendable {
    public var id: String
    public var familyId: String
    public var name: String
    public var birthDate: String?
    public var adjustedBirthDate: String?
    public var sex: Sex?
    public var profileType: ProfileType
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var version: Int

    enum CodingKeys: String, CodingKey {
        case id, name, sex, version
        case familyId = "family_id", birthDate = "birth_date", adjustedBirthDate = "adjusted_birth_date", profileType = "profile_type"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    public init(id: String, familyId: String, name: String, birthDate: String?, adjustedBirthDate: String?, sex: Sex?, profileType: ProfileType, createdAt: String, updatedAt: String, deletedAt: String?, version: Int) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.birthDate = birthDate
        self.adjustedBirthDate = adjustedBirthDate
        self.sex = sex
        self.profileType = profileType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        familyId = try c.decode(String.self, forKey: .familyId)
        name = try c.decode(String.self, forKey: .name)
        birthDate = try c.decodeIfPresent(String.self, forKey: .birthDate)
        adjustedBirthDate = try c.decodeIfPresent(String.self, forKey: .adjustedBirthDate)
        sex = try c.decodeIfPresent(Sex.self, forKey: .sex)
        profileType = try c.decodeIfPresent(ProfileType.self, forKey: .profileType) ?? .CHILD
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyId, forKey: .familyId)
        try c.encode(name, forKey: .name)
        try c.put(birthDate, .birthDate)
        try c.put(adjustedBirthDate, .adjustedBirthDate)
        try c.put(sex, .sex)
        try c.encode(profileType, forKey: .profileType)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.put(deletedAt, .deletedAt)
        try c.encode(version, forKey: .version)
    }

    public func toEntity() throws -> ProfileEntity {
        ProfileEntity(
            id: id, familyId: familyId, name: name,
            birthDate: birthDate.flatMap(LocalDate.parse),
            adjustedBirthDate: adjustedBirthDate.flatMap(LocalDate.parse),
            sex: sex, profileType: profileType,
            createdAt: try createdAt.isoToMillis(), updatedAt: try updatedAt.isoToMillis(), deletedAt: try deletedAt?.isoToMillis(), version: version
        )
    }
}

public extension ProfileEntity {
    func toDto() -> ProfileDto {
        ProfileDto(id: id, familyId: familyId, name: name, birthDate: birthDate?.description, adjustedBirthDate: adjustedBirthDate?.description, sex: sex, profileType: profileType, createdAt: createdAt.toIso(), updatedAt: updatedAt.toIso(), deletedAt: deletedAt?.toIso(), version: version)
    }
}

public struct ReminderDto: Codable, Equatable, Sendable {
    public var id: String
    public var familyId: String
    public var caregiverId: String
    public var profileId: String?
    public var kind: ReminderKind
    public var intervalMinutes: Int
    public var enabled: Bool
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var version: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, enabled, version
        case familyId = "family_id", caregiverId = "caregiver_id", profileId = "profile_id", intervalMinutes = "interval_minutes"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    public init(id: String, familyId: String, caregiverId: String, profileId: String?, kind: ReminderKind, intervalMinutes: Int, enabled: Bool, createdAt: String, updatedAt: String, deletedAt: String?, version: Int) {
        self.id = id
        self.familyId = familyId
        self.caregiverId = caregiverId
        self.profileId = profileId
        self.kind = kind
        self.intervalMinutes = intervalMinutes
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        familyId = try c.decode(String.self, forKey: .familyId)
        caregiverId = try c.decode(String.self, forKey: .caregiverId)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId)
        kind = try c.decode(ReminderKind.self, forKey: .kind)
        intervalMinutes = try c.decode(Int.self, forKey: .intervalMinutes)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyId, forKey: .familyId)
        try c.encode(caregiverId, forKey: .caregiverId)
        try c.put(profileId, .profileId)
        try c.encode(kind, forKey: .kind)
        try c.encode(intervalMinutes, forKey: .intervalMinutes)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.put(deletedAt, .deletedAt)
        try c.encode(version, forKey: .version)
    }

    public func toEntity() throws -> ReminderEntity {
        ReminderEntity(id: id, familyId: familyId, caregiverId: caregiverId, profileId: profileId, kind: kind, intervalMinutes: intervalMinutes, enabled: enabled, createdAt: try createdAt.isoToMillis(), updatedAt: try updatedAt.isoToMillis(), version: version)
    }
}

public extension ReminderEntity {
    func toDto() -> ReminderDto {
        ReminderDto(id: id, familyId: familyId, caregiverId: caregiverId, profileId: profileId, kind: kind, intervalMinutes: intervalMinutes, enabled: enabled, createdAt: createdAt.toIso(), updatedAt: updatedAt.toIso(), deletedAt: nil, version: version)
    }
}

public struct ActivityDto: Codable, Equatable, Sendable {
    public var id: String
    public var familyId: String
    public var profileId: String?
    public var type: ActivityType
    public var startTime: String
    public var endTime: String?
    public var timeZone: String
    public var note: String?
    public var createdById: String?
    public var updatedById: String?

    public var bottleMilkType: MilkType?
    public var bottleBreastMilkMl: Double?
    public var bottleFormulaMl: Double?
    public var bottleFormulaName: String?
    public var bottleTotalMl: Double?

    public var pumpDurationSec: Int64?
    public var pumpLeftMl: Double?
    public var pumpRightMl: Double?
    public var pumpTotalMl: Double?

    public var breastBeginSide: BreastSide?
    public var breastEndSide: BreastSide?
    public var breastLeftDurationSec: Int64?
    public var breastRightDurationSec: Int64?
    public var breastIsManualEntry: Bool?

    public var diaperType: DiaperType?
    public var diaperColor: StoolColor?
    public var diaperTexture: StoolTexture?
    public var diaperDetail: String?
    public var diaperHasRash: Bool?

    public var growthWeightKg: Double?
    public var growthHeightCm: Double?
    public var growthHeadCm: Double?

    public var milestoneTitle: String?
    public var milestoneKey: String?

    public var solidsMealType: MealType?
    public var solidsFoods: [String]?
    public var solidsResetsFeedSchedule: Bool?

    public var routineName: String?
    public var babyFirstTitle: String?

    public var medicalTemperatureC: Double?
    public var medicalMedicationName: String?
    public var medicalDose: Double?
    public var medicalDoseUnit: String?

    public var vaccineVaccines: [String]?

    public var photoPath: String?
    public var comboGroupId: String?

    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var version: Int

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, type, note, version
        case familyId = "family_id", profileId = "profile_id"
        case startTime = "start_time", endTime = "end_time", timeZone = "time_zone"
        case createdById = "created_by_id", updatedById = "updated_by_id"
        case bottleMilkType = "bottle_milk_type", bottleBreastMilkMl = "bottle_breast_milk_ml", bottleFormulaMl = "bottle_formula_ml"
        case bottleFormulaName = "bottle_formula_name", bottleTotalMl = "bottle_total_ml"
        case pumpDurationSec = "pump_duration_sec", pumpLeftMl = "pump_left_ml", pumpRightMl = "pump_right_ml", pumpTotalMl = "pump_total_ml"
        case breastBeginSide = "breast_begin_side", breastEndSide = "breast_end_side"
        case breastLeftDurationSec = "breast_left_duration_sec", breastRightDurationSec = "breast_right_duration_sec"
        case breastIsManualEntry = "breast_is_manual_entry"
        case diaperType = "diaper_type", diaperColor = "diaper_color", diaperTexture = "diaper_texture"
        case diaperDetail = "diaper_detail", diaperHasRash = "diaper_has_rash"
        case growthWeightKg = "growth_weight_kg", growthHeightCm = "growth_height_cm", growthHeadCm = "growth_head_cm"
        case milestoneTitle = "milestone_title", milestoneKey = "milestone_key"
        case solidsMealType = "solids_meal_type", solidsFoods = "solids_foods"
        case solidsResetsFeedSchedule = "solids_resets_feed_schedule"
        case routineName = "routine_name", babyFirstTitle = "baby_first_title"
        case medicalTemperatureC = "medical_temperature_c", medicalMedicationName = "medical_medication_name"
        case medicalDose = "medical_dose", medicalDoseUnit = "medical_dose_unit"
        case vaccineVaccines = "vaccine_vaccines"
        case photoPath = "photo_path", comboGroupId = "combo_group_id"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    public init(id: String, familyId: String, profileId: String?, type: ActivityType, startTime: String, timeZone: String, createdAt: String, updatedAt: String) {
        self.id = id
        self.familyId = familyId
        self.profileId = profileId
        self.type = type
        self.startTime = startTime
        self.timeZone = timeZone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = 1
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        familyId = try c.decode(String.self, forKey: .familyId)
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId)
        type = try c.decode(ActivityType.self, forKey: .type)
        startTime = try c.decode(String.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        timeZone = try c.decode(String.self, forKey: .timeZone)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        createdById = try c.decodeIfPresent(String.self, forKey: .createdById)
        updatedById = try c.decodeIfPresent(String.self, forKey: .updatedById)
        bottleMilkType = try c.decodeIfPresent(MilkType.self, forKey: .bottleMilkType)
        bottleBreastMilkMl = try c.decodeIfPresent(Double.self, forKey: .bottleBreastMilkMl)
        bottleFormulaMl = try c.decodeIfPresent(Double.self, forKey: .bottleFormulaMl)
        bottleFormulaName = try c.decodeIfPresent(String.self, forKey: .bottleFormulaName)
        bottleTotalMl = try c.decodeIfPresent(Double.self, forKey: .bottleTotalMl)
        pumpDurationSec = try c.decodeIfPresent(Int64.self, forKey: .pumpDurationSec)
        pumpLeftMl = try c.decodeIfPresent(Double.self, forKey: .pumpLeftMl)
        pumpRightMl = try c.decodeIfPresent(Double.self, forKey: .pumpRightMl)
        pumpTotalMl = try c.decodeIfPresent(Double.self, forKey: .pumpTotalMl)
        breastBeginSide = try c.decodeIfPresent(BreastSide.self, forKey: .breastBeginSide)
        breastEndSide = try c.decodeIfPresent(BreastSide.self, forKey: .breastEndSide)
        breastLeftDurationSec = try c.decodeIfPresent(Int64.self, forKey: .breastLeftDurationSec)
        breastRightDurationSec = try c.decodeIfPresent(Int64.self, forKey: .breastRightDurationSec)
        breastIsManualEntry = try c.decodeIfPresent(Bool.self, forKey: .breastIsManualEntry)
        diaperType = try c.decodeIfPresent(DiaperType.self, forKey: .diaperType)
        diaperColor = try c.decodeIfPresent(StoolColor.self, forKey: .diaperColor)
        diaperTexture = try c.decodeIfPresent(StoolTexture.self, forKey: .diaperTexture)
        diaperDetail = try c.decodeIfPresent(String.self, forKey: .diaperDetail)
        diaperHasRash = try c.decodeIfPresent(Bool.self, forKey: .diaperHasRash)
        growthWeightKg = try c.decodeIfPresent(Double.self, forKey: .growthWeightKg)
        growthHeightCm = try c.decodeIfPresent(Double.self, forKey: .growthHeightCm)
        growthHeadCm = try c.decodeIfPresent(Double.self, forKey: .growthHeadCm)
        milestoneTitle = try c.decodeIfPresent(String.self, forKey: .milestoneTitle)
        milestoneKey = try c.decodeIfPresent(String.self, forKey: .milestoneKey)
        solidsMealType = try c.decodeIfPresent(MealType.self, forKey: .solidsMealType)
        solidsFoods = try c.decodeIfPresent([String].self, forKey: .solidsFoods)
        solidsResetsFeedSchedule = try c.decodeIfPresent(Bool.self, forKey: .solidsResetsFeedSchedule)
        routineName = try c.decodeIfPresent(String.self, forKey: .routineName)
        babyFirstTitle = try c.decodeIfPresent(String.self, forKey: .babyFirstTitle)
        medicalTemperatureC = try c.decodeIfPresent(Double.self, forKey: .medicalTemperatureC)
        medicalMedicationName = try c.decodeIfPresent(String.self, forKey: .medicalMedicationName)
        medicalDose = try c.decodeIfPresent(Double.self, forKey: .medicalDose)
        medicalDoseUnit = try c.decodeIfPresent(String.self, forKey: .medicalDoseUnit)
        vaccineVaccines = try c.decodeIfPresent([String].self, forKey: .vaccineVaccines)
        photoPath = try c.decodeIfPresent(String.self, forKey: .photoPath)
        comboGroupId = try c.decodeIfPresent(String.self, forKey: .comboGroupId)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyId, forKey: .familyId)
        try c.put(profileId, .profileId)
        try c.encode(type, forKey: .type)
        try c.encode(startTime, forKey: .startTime)
        try c.put(endTime, .endTime)
        try c.encode(timeZone, forKey: .timeZone)
        try c.put(note, .note)
        try c.put(createdById, .createdById)
        try c.put(updatedById, .updatedById)
        try c.put(bottleMilkType, .bottleMilkType)
        try c.put(bottleBreastMilkMl, .bottleBreastMilkMl)
        try c.put(bottleFormulaMl, .bottleFormulaMl)
        try c.put(bottleFormulaName, .bottleFormulaName)
        try c.put(bottleTotalMl, .bottleTotalMl)
        try c.put(pumpDurationSec, .pumpDurationSec)
        try c.put(pumpLeftMl, .pumpLeftMl)
        try c.put(pumpRightMl, .pumpRightMl)
        try c.put(pumpTotalMl, .pumpTotalMl)
        try c.put(breastBeginSide, .breastBeginSide)
        try c.put(breastEndSide, .breastEndSide)
        try c.put(breastLeftDurationSec, .breastLeftDurationSec)
        try c.put(breastRightDurationSec, .breastRightDurationSec)
        try c.put(breastIsManualEntry, .breastIsManualEntry)
        try c.put(diaperType, .diaperType)
        try c.put(diaperColor, .diaperColor)
        try c.put(diaperTexture, .diaperTexture)
        try c.put(diaperDetail, .diaperDetail)
        try c.put(diaperHasRash, .diaperHasRash)
        try c.put(growthWeightKg, .growthWeightKg)
        try c.put(growthHeightCm, .growthHeightCm)
        try c.put(growthHeadCm, .growthHeadCm)
        try c.put(milestoneTitle, .milestoneTitle)
        try c.put(milestoneKey, .milestoneKey)
        try c.put(solidsMealType, .solidsMealType)
        try c.put(solidsFoods, .solidsFoods)
        try c.put(solidsResetsFeedSchedule, .solidsResetsFeedSchedule)
        try c.put(routineName, .routineName)
        try c.put(babyFirstTitle, .babyFirstTitle)
        try c.put(medicalTemperatureC, .medicalTemperatureC)
        try c.put(medicalMedicationName, .medicalMedicationName)
        try c.put(medicalDose, .medicalDose)
        try c.put(medicalDoseUnit, .medicalDoseUnit)
        try c.put(vaccineVaccines, .vaccineVaccines)
        try c.put(photoPath, .photoPath)
        try c.put(comboGroupId, .comboGroupId)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.put(deletedAt, .deletedAt)
        try c.encode(version, forKey: .version)
    }

    public func toEntity() throws -> ActivityEntity {
        let hasBottle = bottleMilkType != nil || bottleTotalMl != nil || bottleBreastMilkMl != nil || bottleFormulaMl != nil || bottleFormulaName != nil
        let hasBreast = breastLeftDurationSec != nil || breastRightDurationSec != nil
        let hasGrowth = growthWeightKg != nil || growthHeightCm != nil || growthHeadCm != nil
        let hasSolids = type == .SOLIDS || solidsMealType != nil || solidsFoods != nil || solidsResetsFeedSchedule != nil
        let hasMedical = medicalTemperatureC != nil || medicalMedicationName != nil || medicalDose != nil
        return ActivityEntity(
            id: id,
            familyId: familyId,
            profileId: profileId,
            type: type,
            startTime: try startTime.isoToMillis(),
            endTime: try endTime?.isoToMillis(),
            timeZone: timeZone,
            note: note,
            createdById: createdById,
            updatedById: updatedById,
            bottle: hasBottle ? BottleDetails(bottleMilkType, breastMilkMl: bottleBreastMilkMl, formulaMl: bottleFormulaMl, formulaName: bottleFormulaName, totalMl: bottleTotalMl) : nil,
            pump: pumpDurationSec.map { PumpDetails(durationSec: $0, leftMl: pumpLeftMl, rightMl: pumpRightMl, totalMl: pumpTotalMl) },
            breastfeed: hasBreast ? BreastfeedDetails(beginSide: breastBeginSide, endSide: breastEndSide, leftDurationSec: breastLeftDurationSec ?? 0, rightDurationSec: breastRightDurationSec ?? 0, isManualEntry: breastIsManualEntry ?? false) : nil,
            diaper: diaperType.map { DiaperDetails($0, color: diaperColor, texture: diaperTexture, detail: diaperDetail, hasRash: diaperHasRash) },
            growth: hasGrowth ? GrowthDetails(growthWeightKg, growthHeightCm, growthHeadCm) : nil,
            milestone: milestoneTitle.map { MilestoneDetails($0, milestoneKey) },
            solids: hasSolids ? SolidsDetails(solidsMealType, solidsFoods ?? [], resetsFeedSchedule: solidsResetsFeedSchedule ?? true) : nil,
            routine: routineName.map(RoutineDetails.init),
            babyFirst: babyFirstTitle.map(BabyFirstDetails.init),
            medical: hasMedical ? MedicalDetails(temperatureC: medicalTemperatureC, medicationName: medicalMedicationName, dose: medicalDose, doseUnit: medicalDoseUnit) : nil,
            vaccine: vaccineVaccines.map(VaccineDetails.init),
            photoUri: photoPath,
            comboGroupId: comboGroupId,
            createdAt: try createdAt.isoToMillis(),
            updatedAt: try updatedAt.isoToMillis(),
            deletedAt: try deletedAt?.isoToMillis(),
            version: version
        )
    }
}

public extension ActivityEntity {
    func toDto() -> ActivityDto {
        var d = ActivityDto(id: id, familyId: familyId, profileId: profileId, type: type, startTime: startTime.toIso(), timeZone: timeZone, createdAt: createdAt.toIso(), updatedAt: updatedAt.toIso())
        d.endTime = endTime?.toIso()
        d.note = note
        d.createdById = createdById
        d.updatedById = updatedById
        d.bottleMilkType = bottle?.milkType
        d.bottleBreastMilkMl = bottle?.breastMilkMl
        d.bottleFormulaMl = bottle?.formulaMl
        d.bottleFormulaName = bottle?.formulaName
        d.bottleTotalMl = bottle?.totalMl
        d.pumpDurationSec = pump?.durationSec
        d.pumpLeftMl = pump?.leftMl
        d.pumpRightMl = pump?.rightMl
        d.pumpTotalMl = pump?.totalMl
        d.breastBeginSide = breastfeed?.beginSide
        d.breastEndSide = breastfeed?.endSide
        d.breastLeftDurationSec = breastfeed?.leftDurationSec
        d.breastRightDurationSec = breastfeed?.rightDurationSec
        d.breastIsManualEntry = breastfeed?.isManualEntry
        d.diaperType = diaper?.diaperType
        d.diaperColor = diaper?.color
        d.diaperTexture = diaper?.texture
        d.diaperDetail = diaper?.detail
        d.diaperHasRash = diaper?.hasRash
        d.growthWeightKg = growth?.weightKg
        d.growthHeightCm = growth?.heightCm
        d.growthHeadCm = growth?.headCm
        d.milestoneTitle = milestone?.title
        d.milestoneKey = milestone?.milestoneKey
        d.solidsMealType = solids?.mealType
        d.solidsFoods = solids?.foods
        d.solidsResetsFeedSchedule = type == .SOLIDS ? (solids?.resetsFeedSchedule ?? true) : nil
        d.routineName = routine?.name
        d.babyFirstTitle = babyFirst?.title
        d.medicalTemperatureC = medical?.temperatureC
        d.medicalMedicationName = medical?.medicationName
        d.medicalDose = medical?.dose
        d.medicalDoseUnit = medical?.doseUnit
        d.vaccineVaccines = vaccine?.vaccines
        d.photoPath = photoUri
        d.comboGroupId = comboGroupId
        d.deletedAt = deletedAt?.toIso()
        d.version = version
        return d
    }
}

public struct AppointmentDto: Codable, Equatable, Sendable {
    public var id: String
    public var familyId: String
    public var profileId: String
    public var title: String
    public var doctorName: String?
    public var location: String?
    public var startsAt: String
    public var timeZone: String
    public var notes: String?
    public var reminderLeadMinutes: Int?
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var version: Int

    enum CodingKeys: String, CodingKey {
        case id, title, location, notes, version
        case familyId = "family_id", profileId = "profile_id", doctorName = "doctor_name", startsAt = "starts_at"
        case timeZone = "time_zone", reminderLeadMinutes = "reminder_lead_minutes"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    public init(id: String, familyId: String, profileId: String, title: String, doctorName: String?, location: String?, startsAt: String, timeZone: String, notes: String?, reminderLeadMinutes: Int?, createdAt: String, updatedAt: String, deletedAt: String?, version: Int) {
        self.id = id
        self.familyId = familyId
        self.profileId = profileId
        self.title = title
        self.doctorName = doctorName
        self.location = location
        self.startsAt = startsAt
        self.timeZone = timeZone
        self.notes = notes
        self.reminderLeadMinutes = reminderLeadMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        familyId = try c.decode(String.self, forKey: .familyId)
        profileId = try c.decode(String.self, forKey: .profileId)
        title = try c.decode(String.self, forKey: .title)
        doctorName = try c.decodeIfPresent(String.self, forKey: .doctorName)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        startsAt = try c.decode(String.self, forKey: .startsAt)
        timeZone = try c.decode(String.self, forKey: .timeZone)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        reminderLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyId, forKey: .familyId)
        try c.encode(profileId, forKey: .profileId)
        try c.encode(title, forKey: .title)
        try c.put(doctorName, .doctorName)
        try c.put(location, .location)
        try c.encode(startsAt, forKey: .startsAt)
        try c.encode(timeZone, forKey: .timeZone)
        try c.put(notes, .notes)
        try c.put(reminderLeadMinutes, .reminderLeadMinutes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.put(deletedAt, .deletedAt)
        try c.encode(version, forKey: .version)
    }

    public func toEntity() throws -> AppointmentEntity {
        AppointmentEntity(
            id: id, familyId: familyId, profileId: profileId, title: title, doctorName: doctorName, location: location,
            startsAt: try startsAt.isoToMillis(), timeZone: timeZone, notes: notes,
            reminderLead: AppointmentReminderLead.fromLeadMinutes(reminderLeadMinutes),
            createdAt: try createdAt.isoToMillis(), updatedAt: try updatedAt.isoToMillis(), deletedAt: try deletedAt?.isoToMillis(), version: version
        )
    }
}

public extension AppointmentEntity {
    func toDto() -> AppointmentDto {
        AppointmentDto(id: id, familyId: familyId, profileId: profileId, title: title, doctorName: doctorName, location: location, startsAt: startsAt.toIso(), timeZone: timeZone, notes: notes, reminderLeadMinutes: reminderLead.leadMinutes, createdAt: createdAt.toIso(), updatedAt: updatedAt.toIso(), deletedAt: deletedAt?.toIso(), version: version)
    }
}

public struct AppointmentQuestionDto: Codable, Equatable, Sendable {
    public var id: String
    public var appointmentId: String
    public var familyId: String
    public var text: String
    public var isDone: Bool
    public var sortOrder: Int
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var version: Int

    enum CodingKeys: String, CodingKey {
        case id, text, version
        case appointmentId = "appointment_id", familyId = "family_id", isDone = "is_done", sortOrder = "sort_order"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    public init(id: String, appointmentId: String, familyId: String, text: String, isDone: Bool, sortOrder: Int, createdAt: String, updatedAt: String, deletedAt: String?, version: Int) {
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        appointmentId = try c.decode(String.self, forKey: .appointmentId)
        familyId = try c.decode(String.self, forKey: .familyId)
        text = try c.decode(String.self, forKey: .text)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(appointmentId, forKey: .appointmentId)
        try c.encode(familyId, forKey: .familyId)
        try c.encode(text, forKey: .text)
        try c.encode(isDone, forKey: .isDone)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.put(deletedAt, .deletedAt)
        try c.encode(version, forKey: .version)
    }

    public func toEntity() throws -> AppointmentQuestionEntity {
        AppointmentQuestionEntity(id: id, appointmentId: appointmentId, familyId: familyId, text: text, isDone: isDone, sortOrder: sortOrder, createdAt: try createdAt.isoToMillis(), updatedAt: try updatedAt.isoToMillis(), deletedAt: try deletedAt?.isoToMillis(), version: version)
    }
}

public extension AppointmentQuestionEntity {
    func toDto() -> AppointmentQuestionDto {
        AppointmentQuestionDto(id: id, appointmentId: appointmentId, familyId: familyId, text: text, isDone: isDone, sortOrder: sortOrder, createdAt: createdAt.toIso(), updatedAt: updatedAt.toIso(), deletedAt: deletedAt?.toIso(), version: version)
    }
}

public struct NoteDto: Codable, Equatable, Sendable {
    public var id: String
    public var familyId: String
    public var profileId: String
    public var title: String
    public var body: String
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var version: Int

    enum CodingKeys: String, CodingKey {
        case id, title, body, version
        case familyId = "family_id", profileId = "profile_id"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    public init(id: String, familyId: String, profileId: String, title: String, body: String, createdAt: String, updatedAt: String, deletedAt: String?, version: Int) {
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        familyId = try c.decode(String.self, forKey: .familyId)
        profileId = try c.decode(String.self, forKey: .profileId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyId, forKey: .familyId)
        try c.encode(profileId, forKey: .profileId)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.put(deletedAt, .deletedAt)
        try c.encode(version, forKey: .version)
    }

    public func toEntity() throws -> NoteEntity {
        NoteEntity(id: id, familyId: familyId, profileId: profileId, title: title, body: body, createdAt: try createdAt.isoToMillis(), updatedAt: try updatedAt.isoToMillis(), deletedAt: try deletedAt?.isoToMillis(), version: version)
    }
}

public extension NoteEntity {
    func toDto() -> NoteDto {
        NoteDto(id: id, familyId: familyId, profileId: profileId, title: title, body: body, createdAt: createdAt.toIso(), updatedAt: updatedAt.toIso(), deletedAt: deletedAt?.toIso(), version: version)
    }
}

public struct TypeOnlyDto: Codable, Sendable {
    public let type: ActivityType
}

public struct InviteDto: Codable, Equatable, Sendable {
    public let id: String
    public let familyId: String
    public let code: String
    public let expiresAt: String?
    public let acceptedAt: String?
    public let revokedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, code
        case familyId = "family_id", expiresAt = "expires_at", acceptedAt = "accepted_at", revokedAt = "revoked_at"
    }
}

public struct AcceptInviteParams: Codable, Sendable {
    public let code: String
    public let caregiverName: String

    public init(code: String, caregiverName: String) {
        self.code = code
        self.caregiverName = caregiverName
    }

    enum CodingKeys: String, CodingKey {
        case code
        case caregiverName = "caregiver_name"
    }
}

public struct AcceptInviteResult: Codable, Sendable {
    public let familyId: String
    public let caregiverId: String

    enum CodingKeys: String, CodingKey {
        case familyId = "family_id", caregiverId = "caregiver_id"
    }
}

/// Partial update used for soft deletes (`deleted_at`, `updated_at`, `version`).
public struct SoftDeletePatch: Encodable, Sendable {
    public let deletedAt: String
    public let updatedAt: String
    public let version: Int

    public init(now: EpochMs, version: Int) {
        deletedAt = now.toIso()
        updatedAt = now.toIso()
        self.version = version
    }

    enum CodingKeys: String, CodingKey {
        case version
        case deletedAt = "deleted_at", updatedAt = "updated_at"
    }
}
