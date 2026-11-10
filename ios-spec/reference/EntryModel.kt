package com.lifestyle.nestly.ui.entry

import com.lifestyle.nestly.data.catalog.Milestone
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BreastSide
import com.lifestyle.nestly.data.model.MealType
import com.lifestyle.nestly.data.model.MilkType
import com.lifestyle.nestly.data.model.StoolColor
import com.lifestyle.nestly.data.model.StoolTexture
import com.lifestyle.nestly.data.prefs.CardKind
import com.lifestyle.nestly.ui.components.IconKind

enum class EntryKind(val title: String, val card: CardKind, val icon: IconKind) {
    BREASTFEED("Breastfeed", CardKind.FEED, IconKind.BREAST),
    BOTTLE("Bottle Feed", CardKind.FEED, IconKind.BOTTLE),
    SOLIDS("Solids", CardKind.FEED, IconKind.SOLIDS),
    COMBO("Combo Feed", CardKind.FEED, IconKind.COMBO),
    PUMP("Pump", CardKind.PUMP, IconKind.PUMP),
    DIAPER("Diaper", CardKind.DIAPER, IconKind.DIAPER),
    SLEEP("Sleep", CardKind.SLEEP, IconKind.SLEEP),
    ROUTINE("Routine", CardKind.ROUTINE, IconKind.ROUTINE),
    BABY_FIRST("Baby First", CardKind.BABY_FIRSTS, IconKind.BABY_FIRST),
    GROWTH("Growth", CardKind.GROWTH, IconKind.WEIGHT),
    MILESTONE("Milestone", CardKind.GROWTH, IconKind.MILESTONE),
    MEDICAL("Medical", CardKind.HEALTH, IconKind.MEDICAL),
    VACCINE("Vaccine", CardKind.HEALTH, IconKind.VACCINE),
    VITAMIN_D("Vitamin D", CardKind.HEALTH, IconKind.MEDICAL),
    ;

    companion object {
        fun of(type: ActivityType): EntryKind = when (type) {
            ActivityType.BOTTLE_FEED -> BOTTLE
            ActivityType.BREASTFEED -> BREASTFEED
            ActivityType.PUMP -> PUMP
            ActivityType.DIAPER -> DIAPER
            ActivityType.GROWTH -> GROWTH
            ActivityType.MILESTONE -> MILESTONE
            ActivityType.SLEEP -> SLEEP
            ActivityType.SOLIDS -> SOLIDS
            ActivityType.ROUTINE -> ROUTINE
            ActivityType.BABY_FIRST -> BABY_FIRST
            ActivityType.MEDICAL -> MEDICAL
            ActivityType.VACCINE -> VACCINE
            ActivityType.VITAMIN_D -> VITAMIN_D
        }
    }
}

sealed interface EntryRequest {
    data class New(
        val kind: EntryKind,
        val milestone: Milestone? = null,
        /** Vaccines pre-selected in the form, e.g. when logging a dose from the vaccination chart. */
        val vaccines: List<String> = emptyList(),
    ) : EntryRequest
    data class Edit(val activityId: String) : EntryRequest
}

enum class PumpMode { LEFT_RIGHT, TOTAL }

/** Everything any sheet can edit. Only the fields for the current [EntryKind] are used on save. */
data class EntryDraft(
    val startTime: Long,
    /** False until the user picks a start time or a timer runs; the row then shows "Add". */
    val startTimeSet: Boolean = true,
    val endTime: Long? = null,
    val note: String = "",
    val photoPath: String? = null,

    val milkType: MilkType? = null,
    val bottleMl: Double? = null,
    val formulaName: String? = null,

    val leftSec: Long = 0,
    val rightSec: Long = 0,
    val beginSide: BreastSide? = null,
    val endSide: BreastSide? = null,

    val mealType: MealType? = null,
    val foods: List<String> = emptyList(),
    /** Solids only: false = keep milk schedule (default for new), true = replace milk feed. */
    val solidsResetsFeedSchedule: Boolean = false,

    val pumpMode: PumpMode = PumpMode.TOTAL,
    val pumpSec: Long = 0,
    val pumpLeftMl: Double? = null,
    val pumpRightMl: Double? = null,
    val pumpTotalMl: Double? = null,

    val wet: Boolean = false,
    val dirty: Boolean = false,
    val dry: Boolean = false,
    val stoolColor: StoolColor? = null,
    val stoolTexture: StoolTexture? = null,
    val rash: Boolean = false,

    val routineName: String? = null,
    val babyFirstTitle: String = "",

    val weightKg: Double? = null,
    val heightCm: Double? = null,
    val headCm: Double? = null,

    val milestoneKey: String? = null,
    val milestoneTitle: String = "",

    val temperatureF: Double? = null,
    val medicationName: String? = null,
    val dose: Double? = null,
    val doseUnit: String? = null,

    val vaccines: List<String> = emptyList(),

    /** 0 = Breastfeed tab, 1 = Bottle Feed tab. */
    val comboTab: Int = 0,
) {
    val pumpTotalComputed: Double?
        get() = when (pumpMode) {
            PumpMode.TOTAL -> pumpTotalMl
            PumpMode.LEFT_RIGHT ->
                if (pumpLeftMl == null && pumpRightMl == null) null else (pumpLeftMl ?: 0.0) + (pumpRightMl ?: 0.0)
        }
}
