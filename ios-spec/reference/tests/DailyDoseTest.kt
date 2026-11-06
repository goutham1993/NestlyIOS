package com.lifestyle.nestly.data.reminder

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class DailyDoseTest {
    private val zone = ZoneId.of("America/Chicago")
    private val today = LocalDate.of(2026, 11, 4)
    private val startOfToday = today.atStartOfDay(zone).toInstant().toEpochMilli()
    private val startOfTomorrow = today.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()

    private fun at(hour: Int, minute: Int = 0, date: LocalDate = today) =
        date.atTime(hour, minute).atZone(zone).toInstant().toEpochMilli()

    private fun entry(start: Long, type: ActivityType = ActivityType.VITAMIN_D, deleted: Boolean = false) = ActivityEntity(
        id = "a$start$type",
        familyId = "f",
        profileId = "p",
        type = type,
        startTime = start,
        timeZone = zone.id,
        createdAt = start,
        updatedAt = start,
        deletedAt = if (deleted) start else null,
    )

    private fun givenAt(vararg entries: ActivityEntity) =
        DailyDose.givenAt(entries.toList(), startOfToday, startOfTomorrow)

    @Test
    fun notGivenWhenNothingLogged() {
        assertNull(givenAt())
    }

    @Test
    fun yesterdaysDoseDoesNotCountToday() {
        assertNull(givenAt(entry(at(23, 59, today.minusDays(1)))))
    }

    @Test
    fun doseRightAtMidnightCountsForToday() {
        assertEquals(startOfToday, givenAt(entry(startOfToday)))
    }

    @Test
    fun tomorrowsDoseDoesNotCountToday() {
        assertNull(givenAt(entry(startOfTomorrow)))
    }

    @Test
    fun earliestDoseTodayIsReported() {
        assertEquals(at(8, 12), givenAt(entry(at(20)), entry(at(8, 12))))
    }

    @Test
    fun deletedAndOtherTypesAreIgnored() {
        assertNull(givenAt(entry(at(9), deleted = true), entry(at(10), type = ActivityType.MEDICAL)))
    }
}
