package com.lifestyle.nestly.ui.activity

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BottleDetails
import com.lifestyle.nestly.data.model.MilkType
import com.lifestyle.nestly.data.prefs.FilterOption
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivityFiltersTest {
    private fun row(
        type: ActivityType = ActivityType.BOTTLE_FEED,
        note: String? = null,
        photo: String? = null,
    ) = ActivityEntity(
        id = "1",
        familyId = "f",
        profileId = "p",
        type = type,
        startTime = 0,
        timeZone = "UTC",
        note = note,
        photoUri = photo,
        bottle = if (type == ActivityType.BOTTLE_FEED) BottleDetails(MilkType.BREAST_MILK, totalMl = 100.0) else null,
        createdAt = 0,
        updatedAt = 0,
    )

    @Test
    fun emptyFiltersMatchEverything() {
        assertTrue(ActivityFilters.matches(row(), emptySet()))
        assertTrue(ActivityFilters.matches(row(ActivityType.SLEEP), emptySet()))
    }

    @Test
    fun typeFilterRestricts() {
        assertTrue(ActivityFilters.matches(row(), setOf(FilterOption.FEED)))
        assertFalse(ActivityFilters.matches(row(ActivityType.DIAPER), setOf(FilterOption.FEED)))
        assertTrue(ActivityFilters.matches(row(ActivityType.DIAPER), setOf(FilterOption.DIAPER)))
        assertTrue(ActivityFilters.matches(row(ActivityType.MEDICAL), setOf(FilterOption.HEALTH)))
    }

    @Test
    fun notesAndPhotosRequireContent() {
        assertFalse(ActivityFilters.matches(row(), setOf(FilterOption.NOTES)))
        assertTrue(ActivityFilters.matches(row(note = "hi"), setOf(FilterOption.NOTES)))
        assertFalse(ActivityFilters.matches(row(note = "hi"), setOf(FilterOption.PHOTOS)))
        assertTrue(ActivityFilters.matches(row(note = "hi", photo = "/p.jpg"), setOf(FilterOption.PHOTOS, FilterOption.NOTES)))
    }

    @Test
    fun typePlusNotesMustSatisfyBoth() {
        assertFalse(ActivityFilters.matches(row(), setOf(FilterOption.FEED, FilterOption.NOTES)))
        assertTrue(ActivityFilters.matches(row(note = "x"), setOf(FilterOption.FEED, FilterOption.NOTES)))
        assertFalse(ActivityFilters.matches(row(ActivityType.PUMP, note = "x"), setOf(FilterOption.FEED, FilterOption.NOTES)))
    }
}
