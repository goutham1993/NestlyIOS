package com.lifestyle.nestly.data.importer

import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BottleDetails
import com.lifestyle.nestly.data.model.BreastSide
import com.lifestyle.nestly.data.model.BreastfeedDetails
import com.lifestyle.nestly.data.model.DiaperDetails
import com.lifestyle.nestly.data.model.DiaperType
import com.lifestyle.nestly.data.model.GrowthDetails
import com.lifestyle.nestly.data.model.MilestoneDetails
import com.lifestyle.nestly.data.model.MilkType
import com.lifestyle.nestly.data.model.ProfileType
import com.lifestyle.nestly.data.model.PumpDetails
import com.lifestyle.nestly.data.model.Sex
import com.lifestyle.nestly.data.model.StoolColor
import com.lifestyle.nestly.data.model.StoolTexture
import java.time.LocalDate

/** Parsed Nara row, independent of database ids for caregivers. */
sealed interface NaraRecord {
    val familyKey: String

    data class Profile(
        override val familyKey: String,
        val profileKey: String,
        val name: String,
        val birthDate: LocalDate?,
        val adjustedBirthDate: LocalDate?,
        val sex: Sex?,
        val profileType: ProfileType,
    ) : NaraRecord

    data class Activity(
        override val familyKey: String,
        val activityKey: String,
        val profileKey: String?,
        val profileName: String?,
        val type: ActivityType,
        val startTime: Long,
        val endTime: Long?,
        val timeZone: String,
        val note: String?,
        val createdBy: String?,
        val updatedBy: String?,
        val bottle: BottleDetails? = null,
        val pump: PumpDetails? = null,
        val breastfeed: BreastfeedDetails? = null,
        val diaper: DiaperDetails? = null,
        val growth: GrowthDetails? = null,
        val milestone: MilestoneDetails? = null,
    ) : NaraRecord
}

object NaraRowMapper {
    private const val ML_PER_FLOZ = 29.5735295625
    private const val KG_PER_LB = 0.45359237
    private const val CM_PER_IN = 2.54
    private const val DEFAULT_TIME_ZONE = "UTC"

    /** Returns null for rows of a type we don't support yet or rows missing required keys. */
    fun map(row: Map<String, String>): NaraRecord? {
        val familyKey = row["_familyKey"] ?: return null
        return when (row["Type"]) {
            "Profile" -> mapProfile(familyKey, row)
            "Bottle Feed" -> activity(familyKey, row, ActivityType.BOTTLE_FEED)?.copy(bottle = bottle(row))
            "Pump" -> mapPump(familyKey, row)
            "Breastfeed" -> mapBreastfeed(familyKey, row)
            "Diaper" -> activity(familyKey, row, ActivityType.DIAPER)?.copy(diaper = diaper(row))
            "Growth" -> activity(familyKey, row, ActivityType.GROWTH)?.copy(growth = growth(row))
            "Milestone" -> row["[Milestone] Milestone"]?.let { title ->
                activity(familyKey, row, ActivityType.MILESTONE)?.copy(milestone = MilestoneDetails(title.trim()))
            }
            else -> null
        }
    }

    private fun mapProfile(familyKey: String, row: Map<String, String>): NaraRecord.Profile? {
        val profileKey = row["_profileKey"] ?: return null
        return NaraRecord.Profile(
            familyKey = familyKey,
            profileKey = profileKey,
            name = row["Profile Name"] ?: "Baby",
            birthDate = row["[Profile] Birth Date"]?.let(::parseDate),
            adjustedBirthDate = row["[Profile] Birth Date (Adjusted)"]?.let(::parseDate),
            sex = row["[Profile] Sex"]?.let { enumOrNull<Sex>(it) },
            profileType = row["[Profile] Type"]?.let { enumOrNull<ProfileType>(it) } ?: ProfileType.CHILD,
        )
    }

    private fun activity(familyKey: String, row: Map<String, String>, type: ActivityType): NaraRecord.Activity? {
        val key = row["_activityKey"] ?: return null
        val start = row["Start Date/time (Epoch)"]?.toLongFlexible() ?: return null
        return NaraRecord.Activity(
            familyKey = familyKey,
            activityKey = key,
            profileKey = row["_profileKey"],
            profileName = row["Profile Name"],
            type = type,
            startTime = start,
            endTime = null,
            timeZone = row["Time Zone"] ?: DEFAULT_TIME_ZONE,
            note = row["Note"]?.trim()?.ifEmpty { null },
            createdBy = row["Created By Caregiver"],
            updatedBy = row["Last Updated By Caregiver"] ?: row["Created By Caregiver"],
        )
    }

    private fun bottle(row: Map<String, String>): BottleDetails {
        val breastMl = volumeMl(row, "[Bottle Feed] Breast Milk Volume")
        val formulaMl = volumeMl(row, "[Bottle Feed] Formula Volume")
        val genericMl = volumeMl(row, "[Bottle Feed] Volume")
        val milkType = when {
            breastMl != null && formulaMl != null -> MilkType.MIXED
            else -> when (row["[Bottle Feed] Type"]) {
                "Breast Milk" -> MilkType.BREAST_MILK
                "Formula" -> MilkType.FORMULA
                "Mixed" -> MilkType.MIXED
                else -> null
            }
        }
        val total = genericMl ?: sumOrNull(breastMl, formulaMl)
        return BottleDetails(
            milkType = milkType,
            breastMilkMl = breastMl,
            formulaMl = formulaMl,
            formulaName = row["[Bottle Feed] Formula Name"],
            totalMl = total,
        )
    }

    private fun mapPump(familyKey: String, row: Map<String, String>): NaraRecord.Activity? {
        val base = activity(familyKey, row, ActivityType.PUMP) ?: return null
        val left = volumeMl(row, "[Pump] Left Volume")
        val right = volumeMl(row, "[Pump] Right Volume")
        val total = volumeMl(row, "[Pump] Total Volume") ?: sumOrNull(left, right)
        val rawEnd = row["[Pump] End Date/time (Epoch)"]?.toLongFlexible()
        val end = rawEnd?.coerceAtLeast(base.startTime)
        val duration = (row["[Pump] Duration (Seconds)"]?.toLongFlexible() ?: 0L).coerceAtLeast(0L)
        return base.copy(
            endTime = end,
            pump = PumpDetails(durationSec = duration, leftMl = left, rightMl = right, totalMl = total),
        )
    }

    private fun mapBreastfeed(familyKey: String, row: Map<String, String>): NaraRecord.Activity? {
        val base = activity(familyKey, row, ActivityType.BREASTFEED) ?: return null
        val rawEnd = row["[Breastfeed] End Side"]
        val left = (row["[Breastfeed] Left Duration (Seconds)"]?.toLongFlexible() ?: 0L).coerceAtLeast(0L)
        val right = (row["[Breastfeed] Right Duration (Seconds)"]?.toLongFlexible() ?: 0L).coerceAtLeast(0L)
        return base.copy(
            endTime = base.startTime + (left + right) * 1000,
            breastfeed = BreastfeedDetails(
                beginSide = row["[Breastfeed] Begin Side"]?.let(::side),
                endSide = rawEnd?.let(::side),
                leftDurationSec = left,
                rightDurationSec = right,
                isManualEntry = rawEnd?.endsWith(".nonTimer") == true,
            ),
        )
    }

    private fun diaper(row: Map<String, String>): DiaperDetails {
        val type = row["[Diaper] Type"].orEmpty()
        val dirty = type.contains("Dirty", ignoreCase = true)
        val wet = type.contains("Wet", ignoreCase = true)
        val diaperType = when {
            dirty && wet -> DiaperType.MIXED
            dirty -> DiaperType.DIRTY
            wet -> DiaperType.WET
            else -> DiaperType.DRY
        }
        return DiaperDetails(
            diaperType = diaperType,
            color = row["[Diaper] Dirty Color"]?.let { enumOrNull<StoolColor>(it) },
            texture = row["[Diaper] Dirty Texture"]?.let { enumOrNull<StoolTexture>(it) },
            detail = row["[Diaper] Detail"],
        )
    }

    private fun growth(row: Map<String, String>) = GrowthDetails(
        weightKg = row["[Growth] Weight"]?.toDoubleOrNull()?.let { toKg(it, row["[Growth] Weight Unit"]) },
        heightCm = row["[Growth] Height"]?.toDoubleOrNull()?.let { toCm(it, row["[Growth] Height Unit"]) },
        headCm = row["[Growth] Head Size"]?.toDoubleOrNull()?.let { toCm(it, row["[Growth] Head Size Unit"]) },
    )

    private fun volumeMl(row: Map<String, String>, column: String): Double? {
        val value = row[column]?.toDoubleOrNull() ?: return null
        return toMl(value, row["$column Unit"])
    }

    internal fun toMl(value: Double, unit: String?): Double = when (unit?.uppercase()) {
        "FLOZ", "OZ" -> value * ML_PER_FLOZ
        "L" -> value * 1000
        else -> value
    }

    internal fun toKg(value: Double, unit: String?): Double = when (unit?.uppercase()) {
        "LB", "LBS" -> value * KG_PER_LB
        "OZ" -> value * KG_PER_LB / 16
        "G" -> value / 1000
        else -> value
    }

    internal fun toCm(value: Double, unit: String?): Double = when (unit?.uppercase()) {
        "IN" -> value * CM_PER_IN
        "MM" -> value / 10
        "M" -> value * 100
        else -> value
    }

    private fun sumOrNull(a: Double?, b: Double?): Double? =
        if (a == null && b == null) null else (a ?: 0.0) + (b ?: 0.0)

    private fun side(raw: String): BreastSide? = enumOrNull<BreastSide>(raw.substringBefore('.'))

    private fun parseDate(raw: String): LocalDate? = runCatching { LocalDate.parse(raw) }.getOrNull()

    private inline fun <reified T : Enum<T>> enumOrNull(raw: String): T? =
        enumValues<T>().firstOrNull { it.name.equals(raw.trim(), ignoreCase = true) }
}

/** Spreadsheet numeric cells arrive as "1790896458000.0" / "1.79E12", not plain longs. */
internal fun String.toLongFlexible(): Long? =
    trim().toLongOrNull() ?: trim().toDoubleOrNull()?.toLong()

