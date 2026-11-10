package com.lifestyle.nestly.data.reminder

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.MealType
import com.lifestyle.nestly.data.model.SolidsDetails
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderLogicTest {
    @Test
    fun nextFireFromLastActivity() {
        val last = 1_000_000L
        val interval = 180
        assertEquals(last + 180 * 60_000L, ReminderLogic.nextFireMs(last, interval, now = last + 60_000)!!)
    }

    @Test
    fun pastDueFiresOneMinuteFromNow() {
        val last = 1_000_000L
        val now = last + 5 * 60 * 60_000L
        assertEquals(now + 60_000L, ReminderLogic.nextFireMs(last, 180, now = now)!!)
    }

    @Test
    fun noActivityMeansNoFire() {
        assertNull(ReminderLogic.nextFireMs(null, 180, now = 1_000L))
    }

    @Test
    fun nextFeedDueIsLastPlusInterval() {
        val last = 1_000_000L
        assertEquals(last + 180 * 60_000L, ReminderLogic.nextFeedDueMs(last, 180)!!)
        assertNull(ReminderLogic.nextFeedDueMs(null, 180))
    }

    @Test
    fun nextFeedUpcomingReportsRemaining() {
        val last = 1_000_000L
        val now = last + 60 * 60_000L
        val state = ReminderLogic.nextFeedState(last, 180, now = now)
        assertEquals(
            NextFeedState.Upcoming(dueMs = last + 180 * 60_000L, remainingMs = 120 * 60_000L),
            state,
        )
    }

    @Test
    fun nextFeedDueNowWithinOneMinutePastDue() {
        val last = 1_000_000L
        val due = last + 180 * 60_000L
        assertEquals(NextFeedState.DueNow(due), ReminderLogic.nextFeedState(last, 180, now = due))
        assertEquals(NextFeedState.DueNow(due), ReminderLogic.nextFeedState(last, 180, now = due + 59_000L))
    }

    @Test
    fun nextFeedOverdueIsNotClampedLikeNotification() {
        val last = 1_000_000L
        val now = last + 5 * 60 * 60_000L
        assertEquals(
            NextFeedState.Overdue(dueMs = last + 180 * 60_000L, overdueMs = 2 * 60 * 60_000L),
            ReminderLogic.nextFeedState(last, 180, now = now),
        )
    }

    @Test
    fun nextFeedNoFeedWithoutHistory() {
        assertEquals(NextFeedState.NoFeed, ReminderLogic.nextFeedState(null, 180, now = 1_000L))
    }

    @Test
    fun resetsFeedScheduleForMilkAndSolidsChoice() {
        fun solids(resets: Boolean?) = ActivityEntity(
            id = "s",
            familyId = "f",
            profileId = "p",
            type = ActivityType.SOLIDS,
            startTime = 1_000L,
            timeZone = "UTC",
            solids = SolidsDetails(MealType.LUNCH, listOf("Peas"), resetsFeedSchedule = resets ?: true),
            createdAt = 1L,
            updatedAt = 1L,
        )
        assertTrue(ReminderLogic.resetsFeedSchedule(
            ActivityEntity(id = "b", familyId = "f", profileId = "p", type = ActivityType.BOTTLE_FEED, startTime = 1L, timeZone = "UTC", createdAt = 1L, updatedAt = 1L),
        ))
        assertFalse(ReminderLogic.resetsFeedSchedule(solids(false)))
        assertTrue(ReminderLogic.resetsFeedSchedule(solids(true)))
    }
}
