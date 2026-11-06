package com.lifestyle.nestly.data.catalog

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.VaccineDetails
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class VaccineScheduleTest {

    private val birth = LocalDate.of(2026, 1, 1)
    private val zone: ZoneId = ZoneId.of("UTC")

    private fun entry(id: String, date: LocalDate, vararg vaccines: String) = ActivityEntity(
        id = id,
        familyId = "family",
        profileId = "child",
        type = ActivityType.VACCINE,
        startTime = date.atStartOfDay(zone).toInstant().toEpochMilli(),
        timeZone = zone.id,
        vaccine = VaccineDetails(vaccines.toList()),
        createdAt = 0,
        updatedAt = 0,
    )

    private fun statuses(today: LocalDate, vararg entries: ActivityEntity, birthDate: LocalDate? = birth) =
        VaccineSchedule.doseStatuses(birthDate, entries.toList(), today, zone)

    private fun List<DoseStatus>.dose(key: String) = first { it.dose.key == key }

    @Test
    fun scheduleCoversCdcSeriesThroughSixYears() {
        val counts = VaccineSchedule.doses.groupingBy { it.vaccineName }.eachCount()
        assertEquals(3, counts[VaccineSchedule.HEP_B])
        assertEquals(5, counts[VaccineSchedule.DTAP])
        assertEquals(4, counts[VaccineSchedule.HIB])
        assertEquals(4, counts[VaccineSchedule.PCV])
        assertEquals(4, counts[VaccineSchedule.IPV])
        assertEquals(2, counts[VaccineSchedule.MMR])
        assertEquals(2, counts[VaccineSchedule.VAR])
        assertEquals(2, counts[VaccineSchedule.HEP_A])
    }

    @Test
    fun dosesAreInferredByChronologyFromNamesOnly() {
        // Passed newest-first, as the repository returns them.
        val result = statuses(
            LocalDate.of(2026, 5, 10),
            entry("second", LocalDate.of(2026, 5, 1), VaccineSchedule.DTAP),
            entry("first", LocalDate.of(2026, 3, 1), VaccineSchedule.DTAP),
        )
        assertEquals(DoseState.GIVEN, result.dose("dtap1").state)
        assertEquals("first", result.dose("dtap1").givenEntryId)
        assertEquals(LocalDate.of(2026, 3, 1), result.dose("dtap1").givenDate)
        assertEquals(DoseState.GIVEN, result.dose("dtap2").state)
        assertEquals("second", result.dose("dtap2").givenEntryId)
        assertEquals(DoseState.UPCOMING, result.dose("dtap3").state)
    }

    @Test
    fun multiVaccineEntryCountsOncePerVaccine() {
        val result = statuses(
            LocalDate.of(2026, 3, 5),
            entry(
                "visit", LocalDate.of(2026, 3, 1),
                VaccineSchedule.DTAP, VaccineSchedule.PCV, VaccineSchedule.DTAP,
            ),
        )
        assertEquals(DoseState.GIVEN, result.dose("dtap1").state)
        assertEquals(DoseState.GIVEN, result.dose("pcv1").state)
        // The duplicate DTaP in the same entry must not consume dose 2.
        assertEquals(DoseState.UPCOMING, result.dose("dtap2").state)
    }

    @Test
    fun dueAndOverdueBoundariesFollowTheWindow() {
        // DTaP dose 1 is due at 2 months: due from Mar 1, overdue from Apr 1.
        assertEquals(DoseState.UPCOMING, statuses(LocalDate.of(2026, 2, 28)).dose("dtap1").state)
        assertEquals(DoseState.DUE, statuses(LocalDate.of(2026, 3, 1)).dose("dtap1").state)
        assertEquals(DoseState.DUE, statuses(LocalDate.of(2026, 3, 31)).dose("dtap1").state)
        assertEquals(DoseState.OVERDUE, statuses(LocalDate.of(2026, 4, 1)).dose("dtap1").state)

        // A wide window (HepB dose 3, 6–18 months) stays due through its end month.
        val hepb3 = statuses(LocalDate.of(2027, 7, 31)).dose("hepb3")
        assertEquals(DoseState.DUE, hepb3.state)
        assertEquals(LocalDate.of(2026, 7, 1), hepb3.dueDate)
        assertEquals(DoseState.OVERDUE, statuses(LocalDate.of(2027, 8, 1)).dose("hepb3").state)
    }

    @Test
    fun brandDependentDosesAreNeverOverdueOrRecommended() {
        val result = statuses(LocalDate.of(2026, 9, 1)) // 8 months old, nothing logged
        assertEquals(DoseState.DUE, result.dose("rv3").state)
        assertEquals(DoseState.DUE, result.dose("hib3").state)
        assertTrue(result.dose("rv3").countsTowardCompletion.not())
        assertTrue(VaccineSchedule.recommendations(result).none { it.dose.brandDependent })
    }

    @Test
    fun importedAndAbbreviatedNamesStillMatch() {
        assertEquals(VaccineSchedule.DTAP, VaccineSchedule.canonicalVaccineName("DTaP"))
        assertEquals(VaccineSchedule.PCV, VaccineSchedule.canonicalVaccineName("PCV13"))
        assertEquals(VaccineSchedule.HEP_B, VaccineSchedule.canonicalVaccineName("Hep B"))
        assertEquals(VaccineSchedule.MMR, VaccineSchedule.canonicalVaccineName("mmr"))
        assertNull(VaccineSchedule.canonicalVaccineName("Influenza (Flu)"))
        assertNull(VaccineSchedule.canonicalVaccineName("Vitamin K"))

        val result = statuses(
            LocalDate.of(2026, 1, 20),
            entry("birth-dose", LocalDate.of(2026, 1, 1), "Hep B", "Vitamin K"),
        )
        assertEquals(DoseState.GIVEN, result.dose("hepb1").state)
    }

    @Test
    fun extraDosesBeyondTheScheduleAreIgnoredByTheChart() {
        val dates = listOf(2, 4, 6, 12).map { entry("m$it", birth.plusMonths(it.toLong()), VaccineSchedule.PCV) }
        val result = statuses(LocalDate.of(2027, 3, 1), *dates.toTypedArray())
        assertTrue(
            listOf("pcv1", "pcv2", "pcv3", "pcv4").all { result.dose(it).state == DoseState.GIVEN },
        )
    }

    @Test
    fun noBirthDateStillShowsGivenDoses() {
        val result = statuses(
            LocalDate.of(2026, 3, 5),
            entry("first", LocalDate.of(2026, 3, 1), VaccineSchedule.DTAP),
            birthDate = null,
        )
        assertEquals(DoseState.GIVEN, result.dose("dtap1").state)
        assertEquals(DoseState.UPCOMING, result.dose("dtap2").state)
        assertNull(result.dose("dtap2").dueDate)
    }

    @Test
    fun recommendationsOrderOverdueThenDueThenUpcoming() {
        // At 5 months with nothing logged: birth–4-month doses are overdue
        // (4-month doses turned overdue at 5 months) and 6-month doses are upcoming.
        val atFiveMonths = statuses(LocalDate.of(2026, 6, 1))
        val recs = VaccineSchedule.recommendations(atFiveMonths, limit = 20)
        assertTrue(recs.isNotEmpty())
        assertEquals(DoseState.OVERDUE, recs.first().state)
        val states = recs.map { it.state }
        assertEquals(states.sortedBy { it.ordinal }, states)

        // Soonest upcoming first within the upcoming block.
        val upcoming = recs.filter { it.state == DoseState.UPCOMING }
        assertEquals(upcoming.sortedBy { it.dueDate }, upcoming)
        assertTrue(VaccineSchedule.recommendations(atFiveMonths).size <= 5)
    }
}
