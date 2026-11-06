package com.lifestyle.nestly.data.reminder

import com.lifestyle.nestly.data.model.AppointmentReminderLead
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AppointmentReminderLogicTest {
    private val now = 1_700_000_000_000L
    private val startsAt = now + 3 * 24 * 60 * 60_000L

    @Test
    fun noReminderSchedulesNothing() {
        assertNull(AppointmentReminderLogic.fireAtMs(startsAt, AppointmentReminderLead.NONE, now))
    }

    @Test
    fun atTimeFiresAtStart() {
        assertEquals(startsAt, AppointmentReminderLogic.fireAtMs(startsAt, AppointmentReminderLead.AT_TIME, now))
    }

    @Test
    fun oneHourBeforeSubtractsHour() {
        assertEquals(
            startsAt - 60 * 60_000L,
            AppointmentReminderLogic.fireAtMs(startsAt, AppointmentReminderLead.ONE_HOUR, now),
        )
    }

    @Test
    fun oneDayBeforeSubtractsDay() {
        assertEquals(
            startsAt - 24 * 60 * 60_000L,
            AppointmentReminderLogic.fireAtMs(startsAt, AppointmentReminderLead.ONE_DAY, now),
        )
    }

    @Test
    fun pastAppointmentSchedulesNothing() {
        assertNull(AppointmentReminderLogic.fireAtMs(now - 60_000L, AppointmentReminderLead.ONE_HOUR, now))
        assertNull(AppointmentReminderLogic.fireAtMs(now, AppointmentReminderLead.AT_TIME, now))
    }

    @Test
    fun leadAlreadyPassedFiresAsCatchUp() {
        // Booked 30 minutes from now with a one-day lead: ideal time is in the past.
        val soon = now + 30 * 60_000L
        assertEquals(now + 60_000L, AppointmentReminderLogic.fireAtMs(soon, AppointmentReminderLead.ONE_DAY, now))
    }

    @Test
    fun catchUpNeverFiresAfterAppointment() {
        // Appointment in 30 seconds: catch-up is capped at the appointment time.
        val imminent = now + 30_000L
        assertEquals(imminent, AppointmentReminderLogic.fireAtMs(imminent, AppointmentReminderLead.ONE_DAY, now))
    }

    @Test
    fun requestCodesAreNamespacedPerAppointment() {
        assertEquals(
            AppointmentReminderLogic.requestCode("abc"),
            AppointmentReminderLogic.requestCode("abc"),
        )
        assertNotEquals(
            AppointmentReminderLogic.requestCode("abc"),
            AppointmentReminderLogic.requestCode("def"),
        )
        assertNotEquals("abc".hashCode(), AppointmentReminderLogic.requestCode("abc"))
    }
}
