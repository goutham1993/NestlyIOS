package com.lifestyle.nestly.ui.entry

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BabyFirstDetails
import com.lifestyle.nestly.data.model.BottleDetails
import com.lifestyle.nestly.data.model.BreastSide
import com.lifestyle.nestly.data.model.BreastfeedDetails
import com.lifestyle.nestly.data.model.DiaperDetails
import com.lifestyle.nestly.data.model.DiaperType
import com.lifestyle.nestly.data.model.GrowthDetails
import com.lifestyle.nestly.data.model.MedicalDetails
import com.lifestyle.nestly.data.model.MilestoneDetails
import com.lifestyle.nestly.data.model.MilkType
import com.lifestyle.nestly.data.model.PumpDetails
import com.lifestyle.nestly.data.model.RoutineDetails
import com.lifestyle.nestly.data.model.SolidsDetails
import com.lifestyle.nestly.data.model.VaccineDetails

/** Who and where an entry is being saved for. */
data class EntryContext(
    val familyId: String,
    val profileId: String,
    val caregiverId: String?,
    val timeZone: String,
    val now: Long,
    val newId: () -> String,
)

object EntryBuilder {
    fun fahrenheitToCelsius(f: Double) = (f - 32) * 5 / 9
    fun celsiusToFahrenheit(c: Double) = c * 9 / 5 + 32

    fun canSave(kind: EntryKind, d: EntryDraft): Boolean = when (kind) {
        EntryKind.BREASTFEED -> d.leftSec + d.rightSec > 0
        EntryKind.BOTTLE -> d.bottleMl != null || d.milkType != null
        EntryKind.SOLIDS -> d.mealType != null || d.foods.isNotEmpty()
        EntryKind.COMBO -> canSave(EntryKind.BREASTFEED, d) || canSave(EntryKind.BOTTLE, d)
        // Start-only is allowed so a session can be logged in progress and finished later.
        EntryKind.PUMP -> d.startTimeSet || d.pumpSec > 0 || d.pumpTotalComputed != null
        EntryKind.DIAPER -> d.wet || d.dirty || d.dry
        EntryKind.SLEEP -> when {
            d.endTime != null -> d.endTime > d.startTime
            else -> d.startTimeSet
        }
        EntryKind.ROUTINE -> !d.routineName.isNullOrBlank()
        EntryKind.BABY_FIRST -> d.babyFirstTitle.isNotBlank()
        EntryKind.GROWTH -> d.weightKg != null || d.heightCm != null || d.headCm != null
        EntryKind.MILESTONE -> d.milestoneTitle.isNotBlank()
        EntryKind.MEDICAL -> d.temperatureF != null || !d.medicationName.isNullOrBlank()
        EntryKind.VACCINE -> d.vaccines.isNotEmpty()
        EntryKind.VITAMIN_D -> true
    }

    /**
     * Builds the rows to upsert. [existing] is the row being edited (its id and audit fields are
     * kept). Combo Feed can produce two rows linked by a shared group id.
     */
    fun build(kind: EntryKind, d: EntryDraft, ctx: EntryContext, existing: ActivityEntity? = null): List<ActivityEntity> {
        if (kind == EntryKind.COMBO) {
            val parts = listOfNotNull(
                if (canSave(EntryKind.BREASTFEED, d)) EntryKind.BREASTFEED else null,
                if (canSave(EntryKind.BOTTLE, d)) EntryKind.BOTTLE else null,
            )
            val group = if (parts.size > 1) ctx.newId() else null
            return parts.flatMap { part -> build(part, d, ctx) }.map { it.copy(comboGroupId = group) }
        }

        val base = existing ?: ActivityEntity(
            id = ctx.newId(),
            familyId = ctx.familyId,
            profileId = if (kind == EntryKind.PUMP) null else ctx.profileId,
            type = typeOf(kind),
            startTime = d.startTime,
            timeZone = ctx.timeZone,
            createdById = ctx.caregiverId,
            createdAt = ctx.now,
            updatedAt = ctx.now,
        )
        val common = base.copy(
            startTime = d.startTime,
            endTime = null,
            note = d.note.trim().ifEmpty { null },
            photoUri = d.photoPath,
            updatedById = ctx.caregiverId ?: base.updatedById,
        )
        val row = when (kind) {
            EntryKind.BREASTFEED -> common.copy(
                endTime = d.startTime + (d.leftSec + d.rightSec) * 1000,
                breastfeed = BreastfeedDetails(
                    beginSide = d.beginSide ?: defaultSide(d),
                    endSide = d.endSide ?: defaultSide(d),
                    leftDurationSec = d.leftSec,
                    rightDurationSec = d.rightSec,
                    isManualEntry = existing?.breastfeed?.isManualEntry ?: false,
                ),
            )
            EntryKind.BOTTLE -> common.copy(
                bottle = BottleDetails(
                    milkType = d.milkType,
                    breastMilkMl = d.bottleMl.takeIf { d.milkType == MilkType.BREAST_MILK },
                    formulaMl = d.bottleMl.takeIf { d.milkType == MilkType.FORMULA },
                    formulaName = d.formulaName.takeIf { d.milkType == MilkType.FORMULA },
                    totalMl = d.bottleMl,
                ),
            )
            EntryKind.SOLIDS -> common.copy(
                solids = SolidsDetails(d.mealType, d.foods, resetsFeedSchedule = d.solidsResetsFeedSchedule),
            )
            EntryKind.PUMP -> common.copy(
                // No duration yet → leave end open so the session can be finished later.
                endTime = if (d.pumpSec > 0) d.startTime + d.pumpSec * 1000 else null,
                pump = PumpDetails(
                    durationSec = d.pumpSec,
                    leftMl = d.pumpLeftMl.takeIf { d.pumpMode == PumpMode.LEFT_RIGHT },
                    rightMl = d.pumpRightMl.takeIf { d.pumpMode == PumpMode.LEFT_RIGHT },
                    totalMl = d.pumpTotalComputed,
                ),
            )
            EntryKind.DIAPER -> common.copy(
                diaper = DiaperDetails(
                    diaperType = when {
                        d.wet && d.dirty -> DiaperType.MIXED
                        d.dirty -> DiaperType.DIRTY
                        d.wet -> DiaperType.WET
                        else -> DiaperType.DRY
                    },
                    color = d.stoolColor.takeIf { d.dirty },
                    texture = d.stoolTexture.takeIf { d.dirty },
                    hasRash = d.rash,
                ),
            )
            EntryKind.SLEEP -> common.copy(endTime = d.endTime)
            EntryKind.ROUTINE -> common.copy(routine = RoutineDetails(d.routineName!!.trim()))
            EntryKind.BABY_FIRST -> common.copy(babyFirst = BabyFirstDetails(d.babyFirstTitle.trim()))
            EntryKind.GROWTH -> common.copy(growth = GrowthDetails(d.weightKg, d.heightCm, d.headCm))
            EntryKind.MILESTONE -> common.copy(milestone = MilestoneDetails(d.milestoneTitle, d.milestoneKey))
            EntryKind.MEDICAL -> common.copy(
                medical = MedicalDetails(
                    temperatureC = d.temperatureF?.let(::fahrenheitToCelsius),
                    medicationName = d.medicationName?.trim()?.ifEmpty { null },
                    dose = d.dose,
                    doseUnit = d.doseUnit,
                ),
            )
            EntryKind.VACCINE -> common.copy(vaccine = VaccineDetails(d.vaccines))
            EntryKind.VITAMIN_D -> common.copy(
                medical = MedicalDetails(
                    medicationName = VITAMIN_D_NAME,
                    dose = d.dose,
                    doseUnit = d.doseUnit.takeIf { d.dose != null },
                ),
            )
            EntryKind.COMBO -> error("handled above")
        }
        return listOf(row)
    }

    /** Fills a draft from a saved row, for editing. */
    fun draftOf(a: ActivityEntity): EntryDraft = EntryDraft(
        startTime = a.startTime,
        endTime = a.endTime,
        note = a.note.orEmpty(),
        photoPath = a.photoUri,
        milkType = a.bottle?.milkType,
        bottleMl = a.bottle?.totalMl ?: a.bottle?.breastMilkMl ?: a.bottle?.formulaMl,
        formulaName = a.bottle?.formulaName,
        leftSec = a.breastfeed?.leftDurationSec ?: 0,
        rightSec = a.breastfeed?.rightDurationSec ?: 0,
        beginSide = a.breastfeed?.beginSide,
        endSide = a.breastfeed?.endSide,
        mealType = a.solids?.mealType,
        foods = a.solids?.foods.orEmpty(),
        solidsResetsFeedSchedule = a.solids?.resetsFeedSchedule ?: true,
        pumpMode = if (a.pump?.leftMl != null || a.pump?.rightMl != null) PumpMode.LEFT_RIGHT else PumpMode.TOTAL,
        pumpSec = a.pump?.durationSec ?: 0,
        pumpLeftMl = a.pump?.leftMl,
        pumpRightMl = a.pump?.rightMl,
        pumpTotalMl = a.pump?.totalMl,
        wet = a.diaper?.diaperType == DiaperType.WET || a.diaper?.diaperType == DiaperType.MIXED,
        dirty = a.diaper?.diaperType == DiaperType.DIRTY || a.diaper?.diaperType == DiaperType.MIXED,
        dry = a.diaper?.diaperType == DiaperType.DRY,
        stoolColor = a.diaper?.color,
        stoolTexture = a.diaper?.texture,
        rash = a.diaper?.hasRash ?: false,
        routineName = a.routine?.name,
        babyFirstTitle = a.babyFirst?.title.orEmpty(),
        weightKg = a.growth?.weightKg,
        heightCm = a.growth?.heightCm,
        headCm = a.growth?.headCm,
        milestoneKey = a.milestone?.milestoneKey,
        milestoneTitle = a.milestone?.title.orEmpty(),
        temperatureF = a.medical?.temperatureC?.let(::celsiusToFahrenheit),
        medicationName = a.medical?.medicationName,
        dose = a.medical?.dose,
        doseUnit = a.medical?.doseUnit,
        vaccines = a.vaccine?.vaccines.orEmpty(),
    )

    fun typeOf(kind: EntryKind): ActivityType = when (kind) {
        EntryKind.BREASTFEED -> ActivityType.BREASTFEED
        EntryKind.BOTTLE -> ActivityType.BOTTLE_FEED
        EntryKind.SOLIDS -> ActivityType.SOLIDS
        EntryKind.COMBO -> ActivityType.BREASTFEED
        EntryKind.PUMP -> ActivityType.PUMP
        EntryKind.DIAPER -> ActivityType.DIAPER
        EntryKind.SLEEP -> ActivityType.SLEEP
        EntryKind.ROUTINE -> ActivityType.ROUTINE
        EntryKind.BABY_FIRST -> ActivityType.BABY_FIRST
        EntryKind.GROWTH -> ActivityType.GROWTH
        EntryKind.MILESTONE -> ActivityType.MILESTONE
        EntryKind.MEDICAL -> ActivityType.MEDICAL
        EntryKind.VACCINE -> ActivityType.VACCINE
        EntryKind.VITAMIN_D -> ActivityType.VITAMIN_D
    }

    const val VITAMIN_D_NAME = "Vitamin D"
    const val VITAMIN_D_DEFAULT_DOSE = 400.0
    const val VITAMIN_D_DEFAULT_UNIT = "IU"

    private fun defaultSide(d: EntryDraft): BreastSide? = when {
        d.leftSec > 0 && d.rightSec == 0L -> BreastSide.LEFT
        d.rightSec > 0 && d.leftSec == 0L -> BreastSide.RIGHT
        d.leftSec > 0 -> BreastSide.LEFT
        else -> null
    }
}