package com.lifestyle.nestly.data.reminder

import com.lifestyle.nestly.data.model.AppointmentReminderLead

object AppointmentReminderLogic {
    /**
     * When the reminder for an appointment starting at [startsAt] should fire, or null when
     * no alarm should be scheduled (no reminder chosen, or the appointment is already past).
     * If the ideal lead time has already passed but the appointment is still ahead, fires
     * as a catch-up one minute from [now] (or at the appointment time if that's sooner),
     * mirroring [ReminderLogic.nextFireMs].
     */
    fun fireAtMs(startsAt: Long, lead: AppointmentReminderLead, now: Long = System.currentTimeMillis()): Long? {
        val leadMinutes = lead.leadMinutes ?: return null
        if (startsAt <= now) return null
        val ideal = startsAt - leadMinutes * 60_000L
        return if (ideal > now) ideal else minOf(now + 60_000L, startsAt)
    }

    /** Stable request-code / notification-id seed so appointment alarms never clash with interval reminders. */
    fun requestCode(appointmentId: String): Int = ("appointment:" + appointmentId).hashCode()
}
