package com.lifestyle.nestly.data.reminder

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
}
