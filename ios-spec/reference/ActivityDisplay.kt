package com.lifestyle.nestly.ui.activity

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.DiaperType
import com.lifestyle.nestly.data.model.MilkType
import com.lifestyle.nestly.data.prefs.CardKind
import com.lifestyle.nestly.data.units.UnitPrefs
import com.lifestyle.nestly.ui.components.Format
import com.lifestyle.nestly.ui.components.IconKind

val ActivityType.card: CardKind
    get() = when (this) {
        ActivityType.BOTTLE_FEED, ActivityType.BREASTFEED, ActivityType.SOLIDS -> CardKind.FEED
        ActivityType.PUMP -> CardKind.PUMP
        ActivityType.DIAPER -> CardKind.DIAPER
        ActivityType.SLEEP -> CardKind.SLEEP
        ActivityType.ROUTINE -> CardKind.ROUTINE
        ActivityType.BABY_FIRST -> CardKind.BABY_FIRSTS
        ActivityType.GROWTH, ActivityType.MILESTONE -> CardKind.GROWTH
        ActivityType.MEDICAL, ActivityType.VACCINE, ActivityType.VITAMIN_D -> CardKind.HEALTH
    }

val CardKind.types: List<ActivityType>
    get() = ActivityType.entries.filter { it.card == this }

val CardKind.title: String
    get() = when (this) {
        CardKind.FEED -> "Feed"
        CardKind.PUMP -> "Pump"
        CardKind.DIAPER -> "Diaper"
        CardKind.SLEEP -> "Sleep"
        CardKind.ROUTINE -> "Routine"
        CardKind.BABY_FIRSTS -> "Baby Firsts"
        CardKind.GROWTH -> "Growth"
        CardKind.HEALTH -> "Health"
    }

val ActivityEntity.iconKind: IconKind
    get() = when (type) {
        ActivityType.BOTTLE_FEED -> IconKind.BOTTLE
        ActivityType.BREASTFEED -> IconKind.BREAST
        ActivityType.SOLIDS -> IconKind.SOLIDS
        ActivityType.PUMP -> IconKind.PUMP
        ActivityType.DIAPER -> IconKind.DIAPER
        ActivityType.SLEEP -> IconKind.SLEEP
        ActivityType.ROUTINE -> IconKind.ROUTINE
        ActivityType.BABY_FIRST -> IconKind.BABY_FIRST
        ActivityType.GROWTH -> IconKind.WEIGHT
        ActivityType.MILESTONE -> IconKind.MILESTONE
        ActivityType.MEDICAL -> IconKind.MEDICAL
        ActivityType.VACCINE -> IconKind.VACCINE
        ActivityType.VITAMIN_D -> IconKind.MEDICAL
    }

/** Short label shown after the time in list rows, e.g. "Breast Milk". */
val ActivityEntity.label: String
    get() = when (type) {
        ActivityType.BOTTLE_FEED -> when (bottle?.milkType) {
            MilkType.BREAST_MILK -> "Breast Milk"
            MilkType.FORMULA -> "Formula"
            MilkType.MIXED -> "Mixed"
            null -> "Bottle"
        }
        ActivityType.BREASTFEED -> "Breastfeed"
        ActivityType.SOLIDS -> solids?.mealType?.name?.lowercase()?.replaceFirstChar { it.uppercase() } ?: "Solids"
        ActivityType.PUMP -> ""
        ActivityType.DIAPER -> diaper?.diaperType?.let(::diaperLabel) ?: "Diaper"
        ActivityType.SLEEP -> "Sleep"
        ActivityType.ROUTINE -> routine?.name ?: "Routine"
        ActivityType.BABY_FIRST -> babyFirst?.title ?: "Baby First"
        ActivityType.GROWTH -> "Growth"
        ActivityType.MILESTONE -> milestone?.title ?: "Milestone"
        ActivityType.MEDICAL -> medical?.medicationName ?: "Medical"
        ActivityType.VACCINE -> vaccine?.vaccines?.joinToString() ?: "Vaccine"
        ActivityType.VITAMIN_D -> "Vitamin D"
    }

fun diaperLabel(type: DiaperType): String = when (type) {
    DiaperType.WET -> "Wet"
    DiaperType.DIRTY -> "Dirty"
    DiaperType.MIXED -> "Wet + Dirty"
    DiaperType.DRY -> "Dry"
}

/** Value next to the bar, e.g. "150 mL" or "L 10m  R 5m". */
fun ActivityEntity.detailText(prefs: UnitPrefs = UnitPrefs.DEFAULT): String? = when (type) {
    ActivityType.BOTTLE_FEED -> bottle?.totalMl?.let { Format.volume(it, prefs) }
    ActivityType.PUMP -> pump?.totalMl?.let { Format.volume(it, prefs) }
    ActivityType.BREASTFEED -> breastfeed?.let { b ->
        listOfNotNull(
            b.leftDurationSec.takeIf { it > 0 }?.let { "L ${Format.duration(it)}" },
            b.rightDurationSec.takeIf { it > 0 }?.let { "R ${Format.duration(it)}" },
        ).joinToString("  ").ifEmpty { null }
    }
    ActivityType.SLEEP -> durationSec?.let(Format::duration)
    ActivityType.SOLIDS -> solids?.foods?.joinToString()?.ifEmpty { null }
    ActivityType.MEDICAL -> medical?.temperatureC?.let { Format.temp(it, prefs) }
    ActivityType.VITAMIN_D -> medical?.dose?.let { dose ->
        listOfNotNull(Format.number(dose), medical.doseUnit).joinToString(" ")
    }
    else -> null
}

/** Magnitude used to size the bar in list rows; null for rows without a bar. */
val ActivityEntity.barValue: Double?
    get() = when (type) {
        ActivityType.BOTTLE_FEED -> bottle?.totalMl
        ActivityType.PUMP -> pump?.totalMl
        ActivityType.BREASTFEED -> breastfeed?.let { (it.leftDurationSec + it.rightDurationSec).toDouble() }
        ActivityType.SLEEP -> durationSec?.toDouble()
        else -> null
    }

val ActivityEntity.durationSec: Long?
    get() = endTime?.let { ((it - startTime) / 1000).coerceAtLeast(0) }
