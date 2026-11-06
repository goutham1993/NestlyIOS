package com.lifestyle.nestly.ui.activity

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.prefs.FilterOption

/** Applies the History Filters sheet to an activity list. An empty set means show everything. */
object ActivityFilters {
    fun matches(entry: ActivityEntity, filters: Set<FilterOption>): Boolean {
        if (filters.isEmpty()) return true
        val typeFilters = filters.filter { it.isTypeFilter }
        val typeOk = typeFilters.isEmpty() || typeFilters.any { option -> entry.type in option.types }
        if (!typeOk) return false
        if (FilterOption.NOTES in filters && entry.note.isNullOrBlank()) return false
        if (FilterOption.PHOTOS in filters && entry.photoUri.isNullOrBlank()) return false
        return true
    }

    fun filter(entries: List<ActivityEntity>, filters: Set<FilterOption>): List<ActivityEntity> =
        entries.filter { matches(it, filters) }
}

private val FilterOption.isTypeFilter: Boolean
    get() = this != FilterOption.NOTES && this != FilterOption.PHOTOS

val FilterOption.types: List<ActivityType>
    get() = when (this) {
        FilterOption.FEED -> listOf(ActivityType.BOTTLE_FEED, ActivityType.BREASTFEED, ActivityType.SOLIDS)
        FilterOption.PUMP -> listOf(ActivityType.PUMP)
        FilterOption.DIAPER -> listOf(ActivityType.DIAPER)
        FilterOption.SLEEP -> listOf(ActivityType.SLEEP)
        FilterOption.ROUTINE -> listOf(ActivityType.ROUTINE, ActivityType.BABY_FIRST)
        FilterOption.HEALTH -> listOf(ActivityType.MEDICAL, ActivityType.VACCINE, ActivityType.VITAMIN_D)
        FilterOption.NOTES, FilterOption.PHOTOS -> emptyList()
    }
