package com.lifestyle.nestly.data.importer

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
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
import com.lifestyle.nestly.data.model.ProfileEntity
import com.lifestyle.nestly.data.model.ProfileType
import com.lifestyle.nestly.data.model.PumpDetails
import com.lifestyle.nestly.data.model.RoutineDetails
import com.lifestyle.nestly.data.model.Sex
import com.lifestyle.nestly.data.model.SolidsDetails
import com.lifestyle.nestly.data.model.StoolColor
import com.lifestyle.nestly.data.model.StoolTexture
import com.lifestyle.nestly.data.model.VaccineDetails
import java.time.LocalDate

/** Nestly backup CSV: one row per family / caregiver / profile / activity, keyed by `record`. */
object NestlyCsv {
    const val LIST_SEP = "|"

    val HEADER = listOf(
        "record",
        "id",
        "familyId",
        "profileId",
        "name",
        "birthDate",
        "sex",
        "profileType",
        "type",
        "startTime",
        "endTime",
        "timeZone",
        "note",
        "photoUri",
        "comboGroupId",
        "createdById",
        "updatedById",
        "createdAt",
        "updatedAt",
        "bottle_milkType",
        "bottle_breastMilkMl",
        "bottle_formulaMl",
        "bottle_formulaName",
        "bottle_totalMl",
        "pump_durationSec",
        "pump_leftMl",
        "pump_rightMl",
        "pump_totalMl",
        "breast_beginSide",
        "breast_endSide",
        "breast_leftDurationSec",
        "breast_rightDurationSec",
        "breast_isManualEntry",
        "diaper_diaperType",
        "diaper_color",
        "diaper_texture",
        "diaper_detail",
        "diaper_hasRash",
        "growth_weightKg",
        "growth_heightCm",
        "growth_headCm",
        "milestone_title",
        "milestone_milestoneKey",
        "solids_mealType",
        "solids_foods",
        "routine_name",
        "babyFirst_title",
        "medical_temperatureC",
        "medical_medicationName",
        "medical_dose",
        "medical_doseUnit",
        "vaccine_vaccines",
    )

    fun escape(value: String?): String {
        if (value == null) return ""
        return if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
            "\"" + value.replace("\"", "\"\"") + "\""
        } else value
    }

    fun row(values: Map<String, String?>): String =
        HEADER.joinToString(",") { escape(values[it]) }

    fun familyRow(f: FamilyEntity) = row(
        mapOf(
            "record" to "FAMILY",
            "id" to f.id,
            "name" to f.name,
            "createdAt" to f.createdAt.toString(),
            "updatedAt" to f.updatedAt.toString(),
        ),
    )

    fun caregiverRow(c: CaregiverEntity) = row(
        mapOf(
            "record" to "CAREGIVER",
            "id" to c.id,
            "familyId" to c.familyId,
            "name" to c.name,
            "createdAt" to c.createdAt.toString(),
            "updatedAt" to c.updatedAt.toString(),
        ),
    )

    fun profileRow(p: ProfileEntity) = row(
        mapOf(
            "record" to "PROFILE",
            "id" to p.id,
            "familyId" to p.familyId,
            "name" to p.name,
            "birthDate" to p.birthDate?.toString(),
            "sex" to p.sex?.name,
            "profileType" to p.profileType.name,
            "createdAt" to p.createdAt.toString(),
            "updatedAt" to p.updatedAt.toString(),
        ),
    )

    fun activityRow(a: ActivityEntity) = row(
        buildMap {
            put("record", "ACTIVITY")
            put("id", a.id)
            put("familyId", a.familyId)
            put("profileId", a.profileId)
            put("type", a.type.name)
            put("startTime", a.startTime.toString())
            put("endTime", a.endTime?.toString())
            put("timeZone", a.timeZone)
            put("note", a.note)
            put("photoUri", a.photoUri)
            put("comboGroupId", a.comboGroupId)
            put("createdById", a.createdById)
            put("updatedById", a.updatedById)
            put("createdAt", a.createdAt.toString())
            put("updatedAt", a.updatedAt.toString())
            a.bottle?.let {
                put("bottle_milkType", it.milkType?.name)
                put("bottle_breastMilkMl", it.breastMilkMl?.toString())
                put("bottle_formulaMl", it.formulaMl?.toString())
                put("bottle_formulaName", it.formulaName)
                put("bottle_totalMl", it.totalMl?.toString())
            }
            a.pump?.let {
                put("pump_durationSec", it.durationSec.toString())
                put("pump_leftMl", it.leftMl?.toString())
                put("pump_rightMl", it.rightMl?.toString())
                put("pump_totalMl", it.totalMl?.toString())
            }
            a.breastfeed?.let {
                put("breast_beginSide", it.beginSide?.name)
                put("breast_endSide", it.endSide?.name)
                put("breast_leftDurationSec", it.leftDurationSec.toString())
                put("breast_rightDurationSec", it.rightDurationSec.toString())
                put("breast_isManualEntry", it.isManualEntry.toString())
            }
            a.diaper?.let {
                put("diaper_diaperType", it.diaperType.name)
                put("diaper_color", it.color?.name)
                put("diaper_texture", it.texture?.name)
                put("diaper_detail", it.detail)
                put("diaper_hasRash", it.hasRash?.toString())
            }
            a.growth?.let {
                put("growth_weightKg", it.weightKg?.toString())
                put("growth_heightCm", it.heightCm?.toString())
                put("growth_headCm", it.headCm?.toString())
            }
            a.milestone?.let {
                put("milestone_title", it.title)
                put("milestone_milestoneKey", it.milestoneKey)
            }
            a.solids?.let {
                put("solids_mealType", it.mealType?.name)
                put("solids_foods", it.foods.joinToString(LIST_SEP))
            }
            a.routine?.let { put("routine_name", it.name) }
            a.babyFirst?.let { put("babyFirst_title", it.title) }
            a.medical?.let {
                put("medical_temperatureC", it.temperatureC?.toString())
                put("medical_medicationName", it.medicationName)
                put("medical_dose", it.dose?.toString())
                put("medical_doseUnit", it.doseUnit)
            }
            a.vaccine?.let { put("vaccine_vaccines", it.vaccines.joinToString(LIST_SEP)) }
        },
    )

    fun parseFamily(row: Map<String, String>, now: Long): FamilyEntity = FamilyEntity(
        id = row.require("id"),
        name = row["name"],
        createdAt = row["createdAt"]?.toLongOrNull() ?: now,
        updatedAt = row["updatedAt"]?.toLongOrNull() ?: now,
    )

    fun parseCaregiver(row: Map<String, String>, now: Long): CaregiverEntity = CaregiverEntity(
        id = row.require("id"),
        familyId = row.require("familyId"),
        name = row.require("name"),
        createdAt = row["createdAt"]?.toLongOrNull() ?: now,
        updatedAt = row["updatedAt"]?.toLongOrNull() ?: now,
    )

    fun parseProfile(row: Map<String, String>, now: Long): ProfileEntity = ProfileEntity(
        id = row.require("id"),
        familyId = row.require("familyId"),
        name = row.require("name"),
        birthDate = row["birthDate"]?.let(LocalDate::parse),
        sex = row["sex"]?.let { runCatching { Sex.valueOf(it) }.getOrNull() },
        profileType = row["profileType"]?.let { runCatching { ProfileType.valueOf(it) }.getOrNull() } ?: ProfileType.CHILD,
        createdAt = row["createdAt"]?.toLongOrNull() ?: now,
        updatedAt = row["updatedAt"]?.toLongOrNull() ?: now,
    )

    fun parseActivity(row: Map<String, String>, now: Long): ActivityEntity {
        val type = ActivityType.valueOf(row.require("type"))
        return ActivityEntity(
            id = row.require("id"),
            familyId = row.require("familyId"),
            profileId = row["profileId"],
            type = type,
            startTime = row.require("startTime").toLong(),
            endTime = row["endTime"]?.toLongOrNull(),
            timeZone = row["timeZone"] ?: "UTC",
            note = row["note"],
            createdById = row["createdById"],
            updatedById = row["updatedById"],
            bottle = bottleOf(row),
            pump = pumpOf(row),
            breastfeed = breastOf(row),
            diaper = diaperOf(row),
            growth = growthOf(row),
            milestone = milestoneOf(row),
            solids = solidsOf(row),
            routine = row["routine_name"]?.let(::RoutineDetails),
            babyFirst = row["babyFirst_title"]?.let(::BabyFirstDetails),
            medical = medicalOf(row),
            vaccine = row["vaccine_vaccines"]?.let { VaccineDetails(it.split(LIST_SEP).filter { s -> s.isNotEmpty() }) },
            photoUri = row["photoUri"],
            comboGroupId = row["comboGroupId"],
            createdAt = row["createdAt"]?.toLongOrNull() ?: now,
            updatedAt = row["updatedAt"]?.toLongOrNull() ?: now,
            )
    }

    private fun Map<String, String>.require(key: String) =
        this[key] ?: error("Missing column $key")

    private fun bottleOf(row: Map<String, String>): BottleDetails? {
        if (listOf("bottle_milkType", "bottle_totalMl", "bottle_breastMilkMl", "bottle_formulaMl").none { it in row }) return null
        return BottleDetails(
            milkType = row["bottle_milkType"]?.let { runCatching { MilkType.valueOf(it) }.getOrNull() },
            breastMilkMl = row["bottle_breastMilkMl"]?.toDoubleOrNull(),
            formulaMl = row["bottle_formulaMl"]?.toDoubleOrNull(),
            formulaName = row["bottle_formulaName"],
            totalMl = row["bottle_totalMl"]?.toDoubleOrNull(),
        )
    }

    private fun pumpOf(row: Map<String, String>): PumpDetails? {
        val duration = row["pump_durationSec"]?.toLongOrNull() ?: return null
        return PumpDetails(
            durationSec = duration,
            leftMl = row["pump_leftMl"]?.toDoubleOrNull(),
            rightMl = row["pump_rightMl"]?.toDoubleOrNull(),
            totalMl = row["pump_totalMl"]?.toDoubleOrNull(),
        )
    }

    private fun breastOf(row: Map<String, String>): BreastfeedDetails? {
        if ("breast_leftDurationSec" !in row && "breast_rightDurationSec" !in row) return null
        return BreastfeedDetails(
            beginSide = row["breast_beginSide"]?.let { runCatching { BreastSide.valueOf(it) }.getOrNull() },
            endSide = row["breast_endSide"]?.let { runCatching { BreastSide.valueOf(it) }.getOrNull() },
            leftDurationSec = row["breast_leftDurationSec"]?.toLongOrNull() ?: 0,
            rightDurationSec = row["breast_rightDurationSec"]?.toLongOrNull() ?: 0,
            isManualEntry = row["breast_isManualEntry"]?.toBooleanStrictOrNull() ?: false,
        )
    }

    private fun diaperOf(row: Map<String, String>): DiaperDetails? {
        val type = row["diaper_diaperType"]?.let { runCatching { DiaperType.valueOf(it) }.getOrNull() } ?: return null
        return DiaperDetails(
            diaperType = type,
            color = row["diaper_color"]?.let { runCatching { StoolColor.valueOf(it) }.getOrNull() },
            texture = row["diaper_texture"]?.let { runCatching { StoolTexture.valueOf(it) }.getOrNull() },
            detail = row["diaper_detail"],
            hasRash = row["diaper_hasRash"]?.toBooleanStrictOrNull(),
        )
    }

    private fun growthOf(row: Map<String, String>): GrowthDetails? {
        if (listOf("growth_weightKg", "growth_heightCm", "growth_headCm").none { it in row }) return null
        return GrowthDetails(
            weightKg = row["growth_weightKg"]?.toDoubleOrNull(),
            heightCm = row["growth_heightCm"]?.toDoubleOrNull(),
            headCm = row["growth_headCm"]?.toDoubleOrNull(),
        )
    }

    private fun milestoneOf(row: Map<String, String>): MilestoneDetails? {
        val title = row["milestone_title"] ?: return null
        return MilestoneDetails(title, row["milestone_milestoneKey"])
    }

    private fun solidsOf(row: Map<String, String>): SolidsDetails? {
        if ("solids_mealType" !in row && "solids_foods" !in row) return null
        return SolidsDetails(
            mealType = row["solids_mealType"]?.let { runCatching { MealType.valueOf(it) }.getOrNull() },
            foods = row["solids_foods"]?.split(LIST_SEP)?.filter { it.isNotEmpty() }.orEmpty(),
        )
    }

    private fun medicalOf(row: Map<String, String>): MedicalDetails? {
        if (listOf("medical_temperatureC", "medical_medicationName", "medical_dose").none { it in row }) return null
        return MedicalDetails(
            temperatureC = row["medical_temperatureC"]?.toDoubleOrNull(),
            medicationName = row["medical_medicationName"],
            dose = row["medical_dose"]?.toDoubleOrNull(),
            doseUnit = row["medical_doseUnit"],
        )
    }
}
