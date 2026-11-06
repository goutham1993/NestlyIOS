package com.lifestyle.nestly.ui.components

import com.lifestyle.nestly.data.reminder.NextFeedState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class FormatTest {
    private val minute = 60_000L

    @Test
    fun ago() {
        val now = 1_000 * minute
        assertEquals("Just now", Format.ago(now - 30_000, now))
        assertEquals("5m ago", Format.ago(now - 5 * minute, now))
        assertEquals("1h 53m ago", Format.ago(now - 113 * minute, now))
        assertEquals("2d ago", Format.ago(now - 2 * 24 * 60 * minute, now))
        assertEquals("Just now", Format.ago(now + minute, now))
    }

    @Test
    fun age() {
        val birth = LocalDate.of(2026, 1, 15)
        assertEquals("Born today", Format.age(birth, birth))
        assertEquals("1 day old", Format.age(birth, birth.plusDays(1)))
        assertEquals("5 days old", Format.age(birth, birth.plusDays(5)))
        assertEquals("1 week old", Format.age(birth, birth.plusWeeks(1)))
        assertEquals("2 weeks, 3 days old", Format.age(birth, birth.plusDays(17)))
        assertEquals("1 month old", Format.age(birth, birth.plusMonths(1)))
        assertEquals("4 months, 2 weeks old", Format.age(birth, birth.plusMonths(4).plusDays(14)))
        assertEquals("1 year old", Format.age(birth, birth.plusYears(1)))
        assertEquals("1 year, 3 months old", Format.age(birth, birth.plusYears(1).plusMonths(3)))
        assertEquals("2 years old", Format.age(birth, birth.plusYears(2)))
        assertNull(Format.age(birth, birth.minusDays(1)))
    }

    @Test
    fun countdown() {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.of(2026, 11, 4)
        val now = today.atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        fun at(date: LocalDate, hour: Int = 9) = date.atTime(hour, 0).atZone(zone).toInstant().toEpochMilli()
        assertEquals("Today", Format.countdown(at(today, 9), now))
        assertEquals("Today", Format.countdown(at(today, 18), now))
        assertEquals("Tomorrow", Format.countdown(at(today.plusDays(1)), now))
        assertEquals("Yesterday", Format.countdown(at(today.minusDays(1)), now))
        assertEquals("in 2 days", Format.countdown(at(today.plusDays(2)), now))
        assertEquals("in 13 days", Format.countdown(at(today.plusDays(13)), now))
        assertEquals("in 2 weeks", Format.countdown(at(today.plusDays(16)), now))
        assertEquals("in 4 weeks", Format.countdown(at(today.plusDays(29)), now))
        assertEquals("2 weeks ago", Format.countdown(at(today.minusDays(14)), now))
        assertEquals("1 month ago", Format.countdown(at(today.minusDays(33)), now))
        assertEquals("in 3 months", Format.countdown(at(today.plusMonths(3)), now))
        assertEquals("in 1 year", Format.countdown(at(today.plusYears(1)), now))
        assertEquals("2 years ago", Format.countdown(at(today.minusYears(2)), now))
    }

    @Test
    fun nextFeeding() {
        // 7:18pm in the local zone, so the expected clock text is exact.
        val due = LocalDate.of(2026, 11, 3).atTime(19, 18)
            .atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        assertEquals(
            "Next feeding in 1h 25m at 7:18pm",
            Format.nextFeeding(NextFeedState.Upcoming(dueMs = due, remainingMs = 85 * minute)),
        )
        assertEquals(
            "Next feeding in 1h 17m at 7:18pm",
            Format.nextFeeding(NextFeedState.Upcoming(dueMs = due, remainingMs = 77 * minute)),
        )
        assertEquals(
            "Next feeding in 1h at 7:18pm",
            Format.nextFeeding(NextFeedState.Upcoming(dueMs = due, remainingMs = 60 * minute)),
        )
        assertEquals(
            "Next feeding in 1m at 7:18pm",
            Format.nextFeeding(NextFeedState.Upcoming(dueMs = due, remainingMs = minute)),
        )
        // A partial final minute still counts as a minute to go.
        assertEquals(
            "Next feeding in 1m at 7:18pm",
            Format.nextFeeding(NextFeedState.Upcoming(dueMs = due, remainingMs = 30_000)),
        )
        assertEquals("Next feeding due now", Format.nextFeeding(NextFeedState.DueNow(due)))
        assertEquals(
            "Next feeding overdue by 42m · due 7:18pm",
            Format.nextFeeding(NextFeedState.Overdue(dueMs = due, overdueMs = 42 * minute)),
        )
        assertNull(Format.nextFeeding(NextFeedState.NoFeed))
    }

    @Test
    fun duration() {
        assertEquals("0s", Format.duration(0))
        assertEquals("45s", Format.duration(45))
        assertEquals("12m", Format.duration(12 * 60))
        assertEquals("12m 5s", Format.duration(12 * 60 + 5))
        assertEquals("1h 5m", Format.duration(3600 + 5 * 60 + 30))
    }

    @Test
    fun durationUnderOneMinuteShowsSeconds() {
        assertEquals("0s", Format.duration(0))
        assertEquals("45s", Format.duration(45))
        assertEquals("59s", Format.duration(59))
    }

    @Test
    fun volumeRespectsUnitPrefs() {
        val mlPrefs = com.lifestyle.nestly.data.units.UnitPrefs()
        val ozPrefs = mlPrefs.copy(volume = com.lifestyle.nestly.data.units.VolumeUnit.OZ)
        assertEquals("150 mL", Format.volume(150.0, mlPrefs))
        assertEquals("5.1 oz", Format.volume(150.0, ozPrefs))
    }

    @Test
    fun number() {
        assertEquals("150", Format.number(150.0))
        assertEquals("7.34", Format.number(7.3412))
        assertEquals("7.5", Format.number(7.5))
        assertEquals("150 mL", Format.ml(149.6))
    }
}
