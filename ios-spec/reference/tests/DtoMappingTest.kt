package com.lifestyle.nestly.data.supabase

import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BottleDetails
import com.lifestyle.nestly.data.model.MilkType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DtoMappingTest {

    @Test
    fun activityRoundTripsThroughDto() {
        val original = com.lifestyle.nestly.data.model.ActivityEntity(
            id = "11111111-1111-1111-1111-111111111111",
            familyId = "22222222-2222-2222-2222-222222222222",
            profileId = "33333333-3333-3333-3333-333333333333",
            type = ActivityType.BOTTLE_FEED,
            startTime = 1_700_000_000_000L,
            endTime = 1_700_000_600_000L,
            timeZone = "America/Chicago",
            note = "test",
            createdById = "44444444-4444-4444-4444-444444444444",
            bottle = BottleDetails(MilkType.FORMULA, formulaMl = 120.0, formulaName = "Gentle", totalMl = 120.0),
            createdAt = 1_700_000_000_000L,
            updatedAt = 1_700_000_100_000L,
            version = 3,
        )
        val restored = original.toDto().toEntity()
        assertEquals(original, restored)
    }

    @Test
    fun emptyDetailsStayNull() {
        val dto = com.lifestyle.nestly.data.model.ActivityEntity(
            id = "11111111-1111-1111-1111-111111111111",
            familyId = "22222222-2222-2222-2222-222222222222",
            profileId = null,
            type = ActivityType.SLEEP,
            startTime = 1_700_000_000_000L,
            timeZone = "UTC",
            createdAt = 1_700_000_000_000L,
            updatedAt = 1_700_000_000_000L,
        ).toDto()
        assertNull(dto.bottleTotalMl)
        assertNull(dto.pumpDurationSec)
        val restored = dto.toEntity()
        assertNull(restored.bottle)
        assertNull(restored.pump)
        assertNull(restored.breastfeed)
    }

    @Test
    fun appointmentRoundTripsThroughDto() {
        val original = com.lifestyle.nestly.data.model.AppointmentEntity(
            id = "11111111-1111-1111-1111-111111111111",
            familyId = "22222222-2222-2222-2222-222222222222",
            profileId = "33333333-3333-3333-3333-333333333333",
            title = "2-month checkup",
            doctorName = "Dr. Patel",
            location = "Sunny Pediatrics",
            startsAt = 1_700_000_000_000L,
            timeZone = "America/Chicago",
            notes = "Bring vaccine record",
            reminderLead = com.lifestyle.nestly.data.model.AppointmentReminderLead.ONE_DAY,
            createdAt = 1_700_000_000_000L,
            updatedAt = 1_700_000_100_000L,
            version = 2,
        )
        assertEquals(original, original.toDto().toEntity())
        assertEquals(1440, original.toDto().reminderLeadMinutes)
    }

    @Test
    fun appointmentNullableFieldsStayNull() {
        val dto = com.lifestyle.nestly.data.model.AppointmentEntity(
            id = "11111111-1111-1111-1111-111111111111",
            familyId = "22222222-2222-2222-2222-222222222222",
            profileId = "33333333-3333-3333-3333-333333333333",
            title = "Checkup",
            startsAt = 1_700_000_000_000L,
            timeZone = "UTC",
            createdAt = 1_700_000_000_000L,
            updatedAt = 1_700_000_000_000L,
        ).toDto()
        assertNull(dto.doctorName)
        assertNull(dto.location)
        assertNull(dto.notes)
        assertNull(dto.reminderLeadMinutes)
        assertEquals(
            com.lifestyle.nestly.data.model.AppointmentReminderLead.NONE,
            dto.toEntity().reminderLead,
        )
    }

    @Test
    fun appointmentQuestionRoundTripsThroughDto() {
        val original = com.lifestyle.nestly.data.model.AppointmentQuestionEntity(
            id = "11111111-1111-1111-1111-111111111111",
            appointmentId = "22222222-2222-2222-2222-222222222222",
            familyId = "33333333-3333-3333-3333-333333333333",
            text = "Is this rash normal?",
            isDone = true,
            sortOrder = 2,
            createdAt = 1_700_000_000_000L,
            updatedAt = 1_700_000_100_000L,
            version = 3,
        )
        assertEquals(original, original.toDto().toEntity())
    }

    @Test
    fun noteRoundTripsThroughDto() {
        val original = com.lifestyle.nestly.data.model.NoteEntity(
            id = "11111111-1111-1111-1111-111111111111",
            familyId = "33333333-3333-3333-3333-333333333333",
            profileId = "44444444-4444-4444-4444-444444444444",
            title = "Bedtime routine",
            body = "1. Bath\n2. Feed\n☑ Lay out pajamas\n☐ Buy diapers\n• White noise on",
            createdAt = 1_700_000_000_000L,
            updatedAt = 1_700_000_100_000L,
            deletedAt = 1_700_000_200_000L,
            version = 4,
        )
        assertEquals(original, original.toDto().toEntity())
    }

    @Test
    fun isoConversionRoundTrips() {
        val millis = 1_700_000_123_000L
        assertEquals(millis, millis.toIso().isoToMillis())
        // Postgres returns offsets like +00:00 rather than Z.
        assertEquals(millis + 123L, "2023-11-14T22:15:23.123+00:00".isoToMillis())
    }
}
