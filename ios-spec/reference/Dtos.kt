package com.lifestyle.nestly.data.supabase

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.AppointmentEntity
import com.lifestyle.nestly.data.model.AppointmentQuestionEntity
import com.lifestyle.nestly.data.model.AppointmentReminderLead
import com.lifestyle.nestly.data.model.BabyFirstDetails
import com.lifestyle.nestly.data.model.BottleDetails
import com.lifestyle.nestly.data.model.BreastSide
import com.lifestyle.nestly.data.model.BreastfeedDetails
import com.lifestyle.nestly.data.model.CaregiverEntity
import com.lifestyle.nestly.data.model.DiaperDetails
import com.lifestyle.nestly.data.model.DiaperType
import com.lifestyle.nestly.data.model.FamilyEntity
import com.lifestyle.nestly.data.model.GrowthDetails
import com.lifestyle.nestly.data.model.MealType
import com.lifestyle.nestly.data.model.MedicalDetails
import com.lifestyle.nestly.data.model.MilestoneDetails
import com.lifestyle.nestly.data.model.MilkType
import com.lifestyle.nestly.data.model.NoteEntity
import com.lifestyle.nestly.data.model.ProfileEntity
import com.lifestyle.nestly.data.model.ProfileType
import com.lifestyle.nestly.data.model.PumpDetails
import com.lifestyle.nestly.data.model.ReminderEntity
import com.lifestyle.nestly.data.model.ReminderKind
import com.lifestyle.nestly.data.model.RoutineDetails
import com.lifestyle.nestly.data.model.Sex
import com.lifestyle.nestly.data.model.SolidsDetails
import com.lifestyle.nestly.data.model.StoolColor
import com.lifestyle.nestly.data.model.StoolTexture
import com.lifestyle.nestly.data.model.VaccineDetails
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime

fun Long.toIso(): String = Instant.ofEpochMilli(this).toString()

fun String.isoToMillis(): Long = runCatching { Instant.parse(this).toEpochMilli() }
    .getOrElse { OffsetDateTime.parse(this).toInstant().toEpochMilli() }

@Serializable
data class FamilyDto(
    val id: String,
    val name: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val version: Int = 1,
) {
    fun toEntity() = FamilyEntity(id, name, createdAt.isoToMillis(), updatedAt.isoToMillis(), deletedAt?.isoToMillis(), version)
}

fun FamilyEntity.toDto() = FamilyDto(id, name, createdAt.toIso(), updatedAt.toIso(), deletedAt?.toIso(), version)

@Serializable
data class CaregiverDto(
    val id: String,
    @SerialName("family_id") val familyId: String,
    @SerialName("user_id") val userId: String? = null,
    val name: String,
    val role: String = "MEMBER",
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val version: Int = 1,
) {
    fun toEntity() = CaregiverEntity(id, familyId, name, userId, role, createdAt.isoToMillis(), updatedAt.isoToMillis(), deletedAt?.isoToMillis(), version)
}

fun CaregiverEntity.toDto() = CaregiverDto(id, familyId, userId, name, role, createdAt.toIso(), updatedAt.toIso(), deletedAt?.toIso(), version)

@Serializable
data class ProfileDto(
    val id: String,
    @SerialName("family_id") val familyId: String,
    val name: String,
    @SerialName("birth_date") val birthDate: String? = null,
    @SerialName("adjusted_birth_date") val adjustedBirthDate: String? = null,
    val sex: Sex? = null,
    @SerialName("profile_type") val profileType: ProfileType = ProfileType.CHILD,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val version: Int = 1,
) {
    fun toEntity() = ProfileEntity(
        id, familyId, name,
        birthDate?.let(LocalDate::parse),
        adjustedBirthDate?.let(LocalDate::parse),
        sex, profileType,
        createdAt.isoToMillis(), updatedAt.isoToMillis(), deletedAt?.isoToMillis(), version,
    )
}

fun ProfileEntity.toDto() = ProfileDto(
    id, familyId, name, birthDate?.toString(), adjustedBirthDate?.toString(), sex, profileType,
    createdAt.toIso(), updatedAt.toIso(), deletedAt?.toIso(), version,
)

@Serializable
data class ReminderDto(
    val id: String,
    @SerialName("family_id") val familyId: String,
    @SerialName("caregiver_id") val caregiverId: String,
    @SerialName("profile_id") val profileId: String? = null,
    val kind: ReminderKind,
    @SerialName("interval_minutes") val intervalMinutes: Int,
    val enabled: Boolean = true,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val version: Int = 1,
) {
    fun toEntity() = ReminderEntity(id, familyId, caregiverId, profileId, kind, intervalMinutes, enabled, updatedAt.isoToMillis(), version)
}

fun ReminderEntity.toDto(createdAt: Long = updatedAt) = ReminderDto(
    id, familyId, caregiverId, profileId, kind, intervalMinutes, enabled,
    createdAt.toIso(), updatedAt.toIso(), null, version,
)

@Serializable
data class ActivityDto(
    val id: String,
    @SerialName("family_id") val familyId: String,
    @SerialName("profile_id") val profileId: String? = null,
    val type: ActivityType,
    @SerialName("start_time") val startTime: String,
    @SerialName("end_time") val endTime: String? = null,
    @SerialName("time_zone") val timeZone: String,
    val note: String? = null,
    @SerialName("created_by_id") val createdById: String? = null,
    @SerialName("updated_by_id") val updatedById: String? = null,

    @SerialName("bottle_milk_type") val bottleMilkType: MilkType? = null,
    @SerialName("bottle_breast_milk_ml") val bottleBreastMilkMl: Double? = null,
    @SerialName("bottle_formula_ml") val bottleFormulaMl: Double? = null,
    @SerialName("bottle_formula_name") val bottleFormulaName: String? = null,
    @SerialName("bottle_total_ml") val bottleTotalMl: Double? = null,

    @SerialName("pump_duration_sec") val pumpDurationSec: Long? = null,
    @SerialName("pump_left_ml") val pumpLeftMl: Double? = null,
    @SerialName("pump_right_ml") val pumpRightMl: Double? = null,
    @SerialName("pump_total_ml") val pumpTotalMl: Double? = null,

    @SerialName("breast_begin_side") val breastBeginSide: BreastSide? = null,
    @SerialName("breast_end_side") val breastEndSide: BreastSide? = null,
    @SerialName("breast_left_duration_sec") val breastLeftDurationSec: Long? = null,
    @SerialName("breast_right_duration_sec") val breastRightDurationSec: Long? = null,
    @SerialName("breast_is_manual_entry") val breastIsManualEntry: Boolean? = null,

    @SerialName("diaper_type") val diaperType: DiaperType? = null,
    @SerialName("diaper_color") val diaperColor: StoolColor? = null,
    @SerialName("diaper_texture") val diaperTexture: StoolTexture? = null,
    @SerialName("diaper_detail") val diaperDetail: String? = null,
    @SerialName("diaper_has_rash") val diaperHasRash: Boolean? = null,

    @SerialName("growth_weight_kg") val growthWeightKg: Double? = null,
    @SerialName("growth_height_cm") val growthHeightCm: Double? = null,
    @SerialName("growth_head_cm") val growthHeadCm: Double? = null,

    @SerialName("milestone_title") val milestoneTitle: String? = null,
    @SerialName("milestone_key") val milestoneKey: String? = null,

    @SerialName("solids_meal_type") val solidsMealType: MealType? = null,
    @SerialName("solids_foods") val solidsFoods: List<String>? = null,
    @SerialName("solids_resets_feed_schedule") val solidsResetsFeedSchedule: Boolean? = null,

    @SerialName("routine_name") val routineName: String? = null,
    @SerialName("baby_first_title") val babyFirstTitle: String? = null,

    @SerialName("medical_temperature_c") val medicalTemperatureC: Double? = null,
    @SerialName("medical_medication_name") val medicalMedicationName: String? = null,
    @SerialName("medical_dose") val medicalDose: Double? = null,
    @SerialName("medical_dose_unit") val medicalDoseUnit: String? = null,

    @SerialName("vaccine_vaccines") val vaccineVaccines: List<String>? = null,

    @SerialName("photo_path") val photoPath: String? = null,
    @SerialName("combo_group_id") val comboGroupId: String? = null,

    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val version: Int = 1,
) {
    fun toEntity() = ActivityEntity(
        id = id,
        familyId = familyId,
        profileId = profileId,
        type = type,
        startTime = startTime.isoToMillis(),
        endTime = endTime?.isoToMillis(),
        timeZone = timeZone,
        note = note,
        createdById = createdById,
        updatedById = updatedById,
        bottle = if (bottleMilkType != null || bottleTotalMl != null || bottleBreastMilkMl != null || bottleFormulaMl != null || bottleFormulaName != null)
            BottleDetails(bottleMilkType, bottleBreastMilkMl, bottleFormulaMl, bottleFormulaName, bottleTotalMl) else null,
        pump = pumpDurationSec?.let { PumpDetails(it, pumpLeftMl, pumpRightMl, pumpTotalMl) },
        breastfeed = if (breastLeftDurationSec != null || breastRightDurationSec != null)
            BreastfeedDetails(breastBeginSide, breastEndSide, breastLeftDurationSec ?: 0, breastRightDurationSec ?: 0, breastIsManualEntry ?: false) else null,
        diaper = diaperType?.let { DiaperDetails(it, diaperColor, diaperTexture, diaperDetail, diaperHasRash) },
        growth = if (growthWeightKg != null || growthHeightCm != null || growthHeadCm != null)
            GrowthDetails(growthWeightKg, growthHeightCm, growthHeadCm) else null,
        milestone = milestoneTitle?.let { MilestoneDetails(it, milestoneKey) },
        solids = if (type == ActivityType.SOLIDS || solidsMealType != null || solidsFoods != null || solidsResetsFeedSchedule != null)
            SolidsDetails(solidsMealType, solidsFoods.orEmpty(), resetsFeedSchedule = solidsResetsFeedSchedule ?: true) else null,
        routine = routineName?.let(::RoutineDetails),
        babyFirst = babyFirstTitle?.let(::BabyFirstDetails),
        medical = if (medicalTemperatureC != null || medicalMedicationName != null || medicalDose != null)
            MedicalDetails(medicalTemperatureC, medicalMedicationName, medicalDose, medicalDoseUnit) else null,
        vaccine = vaccineVaccines?.let(::VaccineDetails),
        photoUri = photoPath,
        comboGroupId = comboGroupId,
        createdAt = createdAt.isoToMillis(),
        updatedAt = updatedAt.isoToMillis(),
        deletedAt = deletedAt?.isoToMillis(),
        version = version,
    )
}

fun ActivityEntity.toDto() = ActivityDto(
    id = id,
    familyId = familyId,
    profileId = profileId,
    type = type,
    startTime = startTime.toIso(),
    endTime = endTime?.toIso(),
    timeZone = timeZone,
    note = note,
    createdById = createdById,
    updatedById = updatedById,
    bottleMilkType = bottle?.milkType,
    bottleBreastMilkMl = bottle?.breastMilkMl,
    bottleFormulaMl = bottle?.formulaMl,
    bottleFormulaName = bottle?.formulaName,
    bottleTotalMl = bottle?.totalMl,
    pumpDurationSec = pump?.durationSec,
    pumpLeftMl = pump?.leftMl,
    pumpRightMl = pump?.rightMl,
    pumpTotalMl = pump?.totalMl,
    breastBeginSide = breastfeed?.beginSide,
    breastEndSide = breastfeed?.endSide,
    breastLeftDurationSec = breastfeed?.leftDurationSec,
    breastRightDurationSec = breastfeed?.rightDurationSec,
    breastIsManualEntry = breastfeed?.isManualEntry,
    diaperType = diaper?.diaperType,
    diaperColor = diaper?.color,
    diaperTexture = diaper?.texture,
    diaperDetail = diaper?.detail,
    diaperHasRash = diaper?.hasRash,
    growthWeightKg = growth?.weightKg,
    growthHeightCm = growth?.heightCm,
    growthHeadCm = growth?.headCm,
    milestoneTitle = milestone?.title,
    milestoneKey = milestone?.milestoneKey,
    solidsMealType = solids?.mealType,
    solidsFoods = solids?.foods,
    solidsResetsFeedSchedule = if (type == ActivityType.SOLIDS) solids?.resetsFeedSchedule ?: true else null,
    routineName = routine?.name,
    babyFirstTitle = babyFirst?.title,
    medicalTemperatureC = medical?.temperatureC,
    medicalMedicationName = medical?.medicationName,
    medicalDose = medical?.dose,
    medicalDoseUnit = medical?.doseUnit,
    vaccineVaccines = vaccine?.vaccines,
    photoPath = photoUri,
    comboGroupId = comboGroupId,
    createdAt = createdAt.toIso(),
    updatedAt = updatedAt.toIso(),
    deletedAt = deletedAt?.toIso(),
    version = version,
)

@Serializable
data class AppointmentDto(
    val id: String,
    @SerialName("family_id") val familyId: String,
    @SerialName("profile_id") val profileId: String,
    val title: String,
    @SerialName("doctor_name") val doctorName: String? = null,
    val location: String? = null,
    @SerialName("starts_at") val startsAt: String,
    @SerialName("time_zone") val timeZone: String,
    val notes: String? = null,
    @SerialName("reminder_lead_minutes") val reminderLeadMinutes: Int? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val version: Int = 1,
) {
    fun toEntity() = AppointmentEntity(
        id = id,
        familyId = familyId,
        profileId = profileId,
        title = title,
        doctorName = doctorName,
        location = location,
        startsAt = startsAt.isoToMillis(),
        timeZone = timeZone,
        notes = notes,
        reminderLead = AppointmentReminderLead.fromLeadMinutes(reminderLeadMinutes),
        createdAt = createdAt.isoToMillis(),
        updatedAt = updatedAt.isoToMillis(),
        deletedAt = deletedAt?.isoToMillis(),
        version = version,
    )
}

fun AppointmentEntity.toDto() = AppointmentDto(
    id = id,
    familyId = familyId,
    profileId = profileId,
    title = title,
    doctorName = doctorName,
    location = location,
    startsAt = startsAt.toIso(),
    timeZone = timeZone,
    notes = notes,
    reminderLeadMinutes = reminderLead.leadMinutes,
    createdAt = createdAt.toIso(),
    updatedAt = updatedAt.toIso(),
    deletedAt = deletedAt?.toIso(),
    version = version,
)

@Serializable
data class AppointmentQuestionDto(
    val id: String,
    @SerialName("appointment_id") val appointmentId: String,
    @SerialName("family_id") val familyId: String,
    val text: String,
    @SerialName("is_done") val isDone: Boolean = false,
    @SerialName("sort_order") val sortOrder: Int = 0,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val version: Int = 1,
) {
    fun toEntity() = AppointmentQuestionEntity(
        id = id,
        appointmentId = appointmentId,
        familyId = familyId,
        text = text,
        isDone = isDone,
        sortOrder = sortOrder,
        createdAt = createdAt.isoToMillis(),
        updatedAt = updatedAt.isoToMillis(),
        deletedAt = deletedAt?.isoToMillis(),
        version = version,
    )
}

fun AppointmentQuestionEntity.toDto() = AppointmentQuestionDto(
    id = id,
    appointmentId = appointmentId,
    familyId = familyId,
    text = text,
    isDone = isDone,
    sortOrder = sortOrder,
    createdAt = createdAt.toIso(),
    updatedAt = updatedAt.toIso(),
    deletedAt = deletedAt?.toIso(),
    version = version,
)

@Serializable
data class NoteDto(
    val id: String,
    @SerialName("family_id") val familyId: String,
    @SerialName("profile_id") val profileId: String,
    val title: String = "",
    val body: String = "",
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    val version: Int = 1,
) {
    fun toEntity() = NoteEntity(
        id = id,
        familyId = familyId,
        profileId = profileId,
        title = title,
        body = body,
        createdAt = createdAt.isoToMillis(),
        updatedAt = updatedAt.isoToMillis(),
        deletedAt = deletedAt?.isoToMillis(),
        version = version,
    )
}

fun NoteEntity.toDto() = NoteDto(
    id = id,
    familyId = familyId,
    profileId = profileId,
    title = title,
    body = body,
    createdAt = createdAt.toIso(),
    updatedAt = updatedAt.toIso(),
    deletedAt = deletedAt?.toIso(),
    version = version,
)

@Serializable
data class TypeOnlyDto(val type: ActivityType)

@Serializable
data class InviteDto(
    val id: String,
    @SerialName("family_id") val familyId: String,
    val code: String,
    @SerialName("expires_at") val expiresAt: String? = null,
    @SerialName("accepted_at") val acceptedAt: String? = null,
    @SerialName("revoked_at") val revokedAt: String? = null,
)

@Serializable
data class AcceptInviteParams(
    val code: String,
    @SerialName("caregiver_name") val caregiverName: String,
)

@Serializable
data class AcceptInviteResult(
    @SerialName("family_id") val familyId: String,
    @SerialName("caregiver_id") val caregiverId: String,
)
