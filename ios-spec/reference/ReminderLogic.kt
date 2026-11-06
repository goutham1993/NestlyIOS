package com.lifestyle.nestly.data.reminder

import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.ReminderKind

object ReminderLogic {
    fun typesFor(kind: ReminderKind): List<ActivityType> = when (kind) {
        ReminderKind.FEED -> listOf(ActivityType.BOTTLE_FEED, ActivityType.BREASTFEED, ActivityType.SOLIDS)
        ReminderKind.PUMP -> listOf(ActivityType.PUMP)
        ReminderKind.DIAPER -> listOf(ActivityType.DIAPER)
        ReminderKind.SLEEP -> listOf(ActivityType.SLEEP)
    }

    /**
     * When the next notification should fire. If the due time is already past, schedules a catch-up
     * one minute from [now] so something still alerts once.
     */
    fun nextFireMs(lastActivityStart: Long?, intervalMinutes: Int, now: Long = System.currentTimeMillis()): Long? {
        if (lastActivityStart == null) return null
        val due = lastActivityStart + intervalMinutes * 60_000L
        return if (due > now) due else now + 60_000L
    }

    /** Absolute time the next feed is estimated to be due, or null with no feed history. */
    fun nextFeedDueMs(lastFeedStart: Long?, intervalMinutes: Int): Long? =
        lastFeedStart?.let { it + intervalMinutes.coerceAtLeast(1) * 60_000L }

    /** Display state for [nextFeedDueMs] relative to [now]. */
    fun nextFeedState(lastFeedStart: Long?, intervalMinutes: Int, now: Long): NextFeedState {
        val due = nextFeedDueMs(lastFeedStart, intervalMinutes) ?: return NextFeedState.NoFeed
        return when {
            now < due -> NextFeedState.Upcoming(dueMs = due, remainingMs = due - now)
            now - due < DUE_NOW_WINDOW_MS -> NextFeedState.DueNow(dueMs = due)
            else -> NextFeedState.Overdue(dueMs = due, overdueMs = now - due)
        }
    }

    fun defaultIntervalMinutes(kind: ReminderKind): Int = when (kind) {
        ReminderKind.FEED, ReminderKind.PUMP -> 180
        ReminderKind.DIAPER, ReminderKind.SLEEP -> 120
    }

    private const val DUE_NOW_WINDOW_MS = 60_000L

    fun label(kind: ReminderKind): String = when (kind) {
        ReminderKind.FEED -> "Feed"
        ReminderKind.PUMP -> "Pump"
        ReminderKind.DIAPER -> "Diaper"
        ReminderKind.SLEEP -> "Sleep"
    }
}

/** How the estimated next feed relates to now, for dashboard-style displays. */
sealed interface NextFeedState {
    data object NoFeed : NextFeedState
    data class Upcoming(val dueMs: Long, val remainingMs: Long) : NextFeedState
    data class DueNow(val dueMs: Long) : NextFeedState
    data class Overdue(val dueMs: Long, val overdueMs: Long) : NextFeedState
}
