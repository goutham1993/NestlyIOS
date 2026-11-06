package com.lifestyle.nestly.data.reminder

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType

/** Once-a-day doses (Vitamin D): given at any time during the local calendar day. */
object DailyDose {
    /**
     * Start time of the first [type] entry on the day beginning at [startOfToday], or null if
     * none yet. [startOfTomorrow] bounds the day so a future-dated entry doesn't count early.
     */
    fun givenAt(
        entries: List<ActivityEntity>,
        startOfToday: Long,
        startOfTomorrow: Long,
        type: ActivityType = ActivityType.VITAMIN_D,
    ): Long? = entries
        .filter { it.deletedAt == null && it.type == type && it.startTime >= startOfToday && it.startTime < startOfTomorrow }
        .minOfOrNull { it.startTime }
}
