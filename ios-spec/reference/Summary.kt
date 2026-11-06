package com.lifestyle.nestly.ui.activity

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.DiaperType
import com.lifestyle.nestly.data.units.UnitPrefs
import com.lifestyle.nestly.ui.components.Format

data class SummaryLine(val type: ActivityType, val count: Int, val details: List<String>)

object Summary {
    /** One line per activity type that has entries in [from, to), in dashboard order. */
    fun summarize(
        entries: List<ActivityEntity>,
        from: Long,
        to: Long,
        prefs: UnitPrefs = UnitPrefs.DEFAULT,
    ): List<SummaryLine> {
        val inRange = entries.filter { it.deletedAt == null && it.startTime >= from && it.startTime < to }
        return SUMMARY_ORDER.mapNotNull { type ->
            val items = inRange.filter { it.type == type }
            if (items.isEmpty()) null else SummaryLine(type, items.size, details(type, items, prefs))
        }
    }

    private fun details(type: ActivityType, items: List<ActivityEntity>, prefs: UnitPrefs): List<String> = when (type) {
        ActivityType.BOTTLE_FEED -> {
            val total = items.sumOf { it.bottle?.totalMl ?: 0.0 }
            val breast = items.sumOf { it.bottle?.breastMilkMl ?: 0.0 }
            val formula = items.sumOf { it.bottle?.formulaMl ?: 0.0 }
            listOfNotNull(
                "${Format.volume(total, prefs)} total",
                breast.takeIf { it > 0 }?.let { "${Format.volume(it, prefs)} breast milk" },
                formula.takeIf { it > 0 }?.let { "${Format.volume(it, prefs)} formula" },
            )
        }
        ActivityType.PUMP -> listOf("${Format.volume(items.sumOf { it.pump?.totalMl ?: 0.0 }, prefs)} total")
        ActivityType.BREASTFEED -> {
            val left = items.sumOf { it.breastfeed?.leftDurationSec ?: 0 }
            val right = items.sumOf { it.breastfeed?.rightDurationSec ?: 0 }
            listOf("${Format.duration(left + right)} total", "L ${Format.duration(left)}  R ${Format.duration(right)}")
        }
        ActivityType.DIAPER -> {
            val wet = items.count { it.diaper?.diaperType == DiaperType.WET || it.diaper?.diaperType == DiaperType.MIXED }
            val dirty = items.count { it.diaper?.diaperType == DiaperType.DIRTY || it.diaper?.diaperType == DiaperType.MIXED }
            listOf("$wet wet, $dirty dirty")
        }
        ActivityType.SLEEP -> listOf("${Format.duration(items.sumOf { it.durationSec ?: 0 })} total")
        else -> emptyList()
    }

    private val SUMMARY_ORDER = listOf(
        ActivityType.BREASTFEED,
        ActivityType.BOTTLE_FEED,
        ActivityType.SOLIDS,
        ActivityType.PUMP,
        ActivityType.DIAPER,
        ActivityType.SLEEP,
        ActivityType.ROUTINE,
        ActivityType.BABY_FIRST,
        ActivityType.GROWTH,
        ActivityType.MILESTONE,
        ActivityType.MEDICAL,
        ActivityType.VACCINE,
        ActivityType.VITAMIN_D,
    )
}

val ActivityType.displayName: String
    get() = when (this) {
        ActivityType.BOTTLE_FEED -> "Bottle Feed"
        ActivityType.BREASTFEED -> "Breastfeed"
        ActivityType.PUMP -> "Pump"
        ActivityType.DIAPER -> "Diaper"
        ActivityType.GROWTH -> "Growth"
        ActivityType.MILESTONE -> "Milestone"
        ActivityType.SLEEP -> "Sleep"
        ActivityType.SOLIDS -> "Solids"
        ActivityType.ROUTINE -> "Routine"
        ActivityType.BABY_FIRST -> "Baby First"
        ActivityType.MEDICAL -> "Medical"
        ActivityType.VACCINE -> "Vaccine"
        ActivityType.VITAMIN_D -> "Vitamin D"
    }
