package com.lifestyle.nestly.data.importer

import com.lifestyle.nestly.data.model.ProfileEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

class NaraImportMappingTest {

    @Test
    fun idsAreDeterministicAndNamespaced() {
        assertEquals(NaraIds.activity("t-abc"), NaraIds.activity("t-abc"))
        assertNotEquals(NaraIds.activity("t-abc"), NaraIds.profile("t-abc"))
        assertNotEquals(NaraIds.activity("t-abc"), NaraIds.activity("t-def"))
        // Valid UUID format for Postgres uuid columns.
        assertEquals(36, NaraIds.activity("t-abc").length)
    }

    @Test
    fun caregiverIdsIgnoreNameSpacingAndCase() {
        assertEquals(
            NaraIds.caregiver("fam-1", "  Jane   Doe "),
            NaraIds.caregiver("fam-1", "jane doe"),
        )
        assertNotEquals(
            NaraIds.caregiver("fam-1", "Jane Doe"),
            NaraIds.caregiver("fam-2", "Jane Doe"),
        )
    }

    private fun profile(name: String, birthDate: LocalDate?, id: String = name + birthDate) = ProfileEntity(
        id = id,
        familyId = "fam",
        name = name,
        birthDate = birthDate,
        sex = null,
        createdAt = 0,
        updatedAt = 0,
    )

    @Test
    fun matchesByNameAndBirthDate() {
        val dob = LocalDate.of(2026, 1, 15)
        val existing = listOf(profile("Rithan", dob), profile("Rithan", dob.plusMonths(3), id = "other"))
        assertEquals(existing[0], NaraProfileMatcher.match(" rithan ", dob, existing))
    }

    @Test
    fun matchesSingleSameNamedProfileWhenDatesDiffer() {
        val dob = LocalDate.of(2026, 1, 15)
        val existing = listOf(profile("Rithan", dob.plusMonths(3)))
        assertEquals(existing[0], NaraProfileMatcher.match("Rithan", dob, existing))
    }

    @Test
    fun noMatchWhenAmbiguousOrUnknown() {
        val dob = LocalDate.of(2026, 1, 15)
        val twins = listOf(
            profile("Alex", dob.plusMonths(1), id = "a"),
            profile("Alex", dob.plusMonths(2), id = "b"),
        )
        assertNull(NaraProfileMatcher.match("Alex", dob, twins))
        assertNull(NaraProfileMatcher.match("Alex", null, twins))
        assertNull(NaraProfileMatcher.match("Sam", dob, twins))
    }
}
