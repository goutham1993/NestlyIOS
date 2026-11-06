package com.lifestyle.nestly.ui.trends

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BottleDetails
import com.lifestyle.nestly.data.model.DiaperDetails
import com.lifestyle.nestly.data.model.DiaperType
import com.lifestyle.nestly.data.model.MilkType
import com.lifestyle.nestly.data.model.PumpDetails
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneOffset

class TrendsAggregatorTest {
    private val zone = ZoneOffset.UTC
    private val day0 = LocalDate.of(2026, 10, 1)
    private fun ms(day: LocalDate, hour: Int = 12) =
        day.atTime(hour, 0).toInstant(zone).toEpochMilli()

    private fun bottle(day: LocalDate, ml: Double) = ActivityEntity(
        id = "b$ml$day",
        familyId = "f",
        profileId = "p",
        type = ActivityType.BOTTLE_FEED,
        startTime = ms(day),
        timeZone = "UTC",
        bottle = BottleDetails(MilkType.BREAST_MILK, breastMilkMl = ml, totalMl = ml),
        createdAt = 0,
        updatedAt = 0,
    )

    private fun pump(day: LocalDate, ml: Double) = ActivityEntity(
        id = "p$ml$day",
        familyId = "f",
        profileId = null,
        type = ActivityType.PUMP,
        startTime = ms(day),
        timeZone = "UTC",
        pump = PumpDetails(durationSec = 600, totalMl = ml),
        createdAt = 0,
        updatedAt = 0,
    )

    private fun diaper(day: LocalDate) = ActivityEntity(
        id = "d$day",
        familyId = "f",
        profileId = "p",
        type = ActivityType.DIAPER,
        startTime = ms(day),
        timeZone = "UTC",
        diaper = DiaperDetails(DiaperType.WET),
        createdAt = 0,
        updatedAt = 0,
    )

    private fun sleep(id: String, start: Long, end: Long) = ActivityEntity(
        id = id,
        familyId = "f",
        profileId = "p",
        type = ActivityType.SLEEP,
        startTime = start,
        endTime = end,
        timeZone = "UTC",
        createdAt = 0,
        updatedAt = 0,
    )

    private fun compute(metric: TrendMetric, entries: List<ActivityEntity>, days: Int = 7) =
        TrendsAggregator.compute(metric, entries, day0, days, zone)

    @Test
    fun sevenDayAveragesAndBarCounts() {
        val entries = listOf(
            bottle(day0, 150.0),
            bottle(day0.plusDays(1), 100.0),
            pump(day0, 80.0),
            diaper(day0),
            diaper(day0.plusDays(2)),
        ) + diaper(day0).copy(id = "d2")

        val sessions = compute(TrendMetric.FEED_SESSIONS, entries)
        assertEquals(2.0 / 7, sessions.value, 1e-9)
        assertEquals(7, sessions.days.size)

        val bottlefed = compute(TrendMetric.AMOUNT_BOTTLEFED, entries)
        assertEquals(250.0 / 7, bottlefed.value, 1e-9)
        assertEquals(150.0, bottlefed.days[0].total, 0.0)
        assertEquals(100.0, bottlefed.days[1].total, 0.0)
        assertEquals(0.0, bottlefed.days[2].total, 0.0)
        assertEquals(TrendSeries.BREAST_MILK, bottlefed.breakdown.single().series)

        assertEquals(125.0, compute(TrendMetric.BOTTLE_SIZE, entries).value, 1e-9)
        assertEquals(80.0 / 7, compute(TrendMetric.AMOUNT_PUMPED, entries).value, 1e-9)

        val diapers = compute(TrendMetric.TOTAL_DIAPERS, entries)
        assertEquals(3, diapers.sampleCount)
        assertEquals(3.0 / 7, diapers.value, 1e-9)
        assertEquals(2.0, diapers.days[0].total, 0.0)
        // Every fixture is at noon.
        assertEquals(0.0, compute(TrendMetric.NIGHT_DIAPERS, entries).value, 0.0)
    }

    @Test
    fun overnightSleepSplitsAcrossDaysAndBands() {
        // 9pm day0 → 7am day1: 3h night on day0, 6h night + 1h day on day1.
        val entries = listOf(sleep("s", ms(day0, 21), ms(day0.plusDays(1), 7)))
        val total = compute(TrendMetric.TOTAL_SLEEP, entries, days = 2)
        assertEquals(3 * 3600.0, total.days[0].total, 0.0)
        assertEquals(7 * 3600.0, total.days[1].total, 0.0)
        assertEquals(5 * 3600.0, total.value, 0.0)
        val day = compute(TrendMetric.DAY_SLEEP, entries, days = 2)
        assertEquals(3600.0, day.days[1].total, 0.0)
        val night = compute(TrendMetric.NIGHT_SLEEP, entries, days = 2)
        assertEquals(9 * 3600.0, night.days.sumOf { it.total }, 0.0)
    }

    @Test
    fun comboFeedCountsAsOneSessionAndGapsAverage() {
        val combo = listOf(
            bottle(day0, 60.0).copy(id = "c1", comboGroupId = "g"),
            bottle(day0, 0.0).copy(id = "c2", type = ActivityType.BREASTFEED, bottle = null, comboGroupId = "g"),
        )
        val later = bottle(day0, 90.0).copy(id = "late", startTime = ms(day0, 15))
        val sessions = compute(TrendMetric.FEED_SESSIONS, combo + later)
        assertEquals(2, sessions.sampleCount)
        assertEquals(listOf(TrendSeries.BOTTLE, TrendSeries.COMBO), sessions.breakdown.map { it.series })
        assertEquals(3 * 3600.0, compute(TrendMetric.TIME_BETWEEN_FEEDS, combo + later).value, 0.0)
    }
}
