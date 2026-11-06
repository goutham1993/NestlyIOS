package com.lifestyle.nestly.ui.activity

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BottleDetails
import com.lifestyle.nestly.data.model.DiaperDetails
import com.lifestyle.nestly.data.model.DiaperType
import com.lifestyle.nestly.data.model.MilkType
import org.junit.Assert.assertEquals
import org.junit.Test

class SummaryTest {
    private val hour = 3_600_000L
    private val now = 100 * hour
    private val startOfToday = now - 10 * hour

    private fun row(id: String, type: ActivityType, start: Long, deleted: Boolean = false, build: (ActivityEntity) -> ActivityEntity = { it }) =
        build(
            ActivityEntity(
                id = id,
                familyId = "f",
                profileId = "p",
                type = type,
                startTime = start,
                timeZone = "UTC",
                createdAt = start,
                updatedAt = start,
                deletedAt = if (deleted) start else null,
            ),
        )

    private val entries = listOf(
        row("b1", ActivityType.BOTTLE_FEED, now - 2 * hour) {
            it.copy(bottle = BottleDetails(MilkType.BREAST_MILK, breastMilkMl = 120.0, formulaMl = null, formulaName = null, totalMl = 120.0))
        },
        row("b2", ActivityType.BOTTLE_FEED, now - 12 * hour) {
            it.copy(bottle = BottleDetails(MilkType.FORMULA, breastMilkMl = null, formulaMl = 90.0, formulaName = null, totalMl = 90.0))
        },
        row("b3", ActivityType.BOTTLE_FEED, now - 30 * hour) {
            it.copy(bottle = BottleDetails(MilkType.FORMULA, breastMilkMl = null, formulaMl = 60.0, formulaName = null, totalMl = 60.0))
        },
        row("d1", ActivityType.DIAPER, now - hour) { it.copy(diaper = DiaperDetails(DiaperType.MIXED)) },
        row("d2", ActivityType.DIAPER, now - 3 * hour, deleted = true) { it.copy(diaper = DiaperDetails(DiaperType.WET)) },
    )

    @Test
    fun todayCountsOnlyEntriesSinceMidnight() {
        val lines = Summary.summarize(entries, startOfToday, now + 1)
        assertEquals(listOf(ActivityType.BOTTLE_FEED, ActivityType.DIAPER), lines.map { it.type })
        val bottle = lines.first()
        assertEquals(1, bottle.count)
        assertEquals(listOf("120 mL total", "120 mL breast milk"), bottle.details)
        assertEquals(listOf("1 wet, 1 dirty"), lines[1].details)
    }

    @Test
    fun last24HoursIncludesYesterdayEvening() {
        val lines = Summary.summarize(entries, now - 24 * hour, now + 1)
        val bottle = lines.first { it.type == ActivityType.BOTTLE_FEED }
        assertEquals(2, bottle.count)
        assertEquals(listOf("210 mL total", "120 mL breast milk", "90 mL formula"), bottle.details)
    }

    @Test
    fun deletedEntriesAreIgnored() {
        val lines = Summary.summarize(entries, startOfToday, now + 1)
        assertEquals(1, lines.first { it.type == ActivityType.DIAPER }.count)
    }
}
