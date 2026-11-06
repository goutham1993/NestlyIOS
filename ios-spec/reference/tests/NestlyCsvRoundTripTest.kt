package com.lifestyle.nestly.data.importer

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BottleDetails
import com.lifestyle.nestly.data.model.DiaperDetails
import com.lifestyle.nestly.data.model.DiaperType
import com.lifestyle.nestly.data.model.MilkType
import com.lifestyle.nestly.data.model.PumpDetails
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.io.StringReader

class NestlyCsvRoundTripTest {
    @Test
    fun activityFieldsSurviveExportAndParse() {
        val bottle = ActivityEntity(
            id = "act-bottle",
            familyId = "fam-1",
            profileId = "child-1",
            type = ActivityType.BOTTLE_FEED,
            startTime = 1_700_000_000_000L,
            endTime = null,
            timeZone = "America/Chicago",
            note = "evening feed",
            bottle = BottleDetails(
                milkType = MilkType.BREAST_MILK,
                breastMilkMl = 120.0,
                totalMl = 120.0,
            ),
            createdAt = 1_700_000_000_100L,
            updatedAt = 1_700_000_000_200L,
        )
        val pump = ActivityEntity(
            id = "act-pump",
            familyId = "fam-1",
            profileId = null,
            type = ActivityType.PUMP,
            startTime = 1_700_000_100_000L,
            endTime = 1_700_000_160_000L,
            timeZone = "America/Chicago",
            pump = PumpDetails(durationSec = 600, leftMl = 40.0, rightMl = 35.0, totalMl = 75.0),
            createdAt = 1_700_000_100_100L,
            updatedAt = 1_700_000_100_200L,
        )
        val diaper = ActivityEntity(
            id = "act-diaper",
            familyId = "fam-1",
            profileId = "child-1",
            type = ActivityType.DIAPER,
            startTime = 1_700_000_200_000L,
            timeZone = "America/Chicago",
            diaper = DiaperDetails(diaperType = DiaperType.WET),
            createdAt = 1_700_000_200_100L,
            updatedAt = 1_700_000_200_200L,
        )

        val csv = buildString {
            append('\uFEFF')
            appendLine(NestlyCsv.HEADER.joinToString(","))
            appendLine(NestlyCsv.activityRow(bottle))
            appendLine(NestlyCsv.activityRow(pump))
            appendLine(NestlyCsv.activityRow(diaper))
        }

        val rows = CsvParser.parseRecords(StringReader(csv))
        assertEquals(3, rows.size)

        val parsedBottle = NestlyCsv.parseActivity(rows[0], now = 0L)
        assertEquals(bottle.id, parsedBottle.id)
        assertEquals(bottle.familyId, parsedBottle.familyId)
        assertEquals(bottle.profileId, parsedBottle.profileId)
        assertEquals(bottle.type, parsedBottle.type)
        assertEquals(bottle.startTime, parsedBottle.startTime)
        assertEquals(bottle.note, parsedBottle.note)
        assertEquals(bottle.bottle, parsedBottle.bottle)

        val parsedPump = NestlyCsv.parseActivity(rows[1], now = 0L)
        assertEquals(pump.pump, parsedPump.pump)
        assertEquals(pump.endTime, parsedPump.endTime)

        val parsedDiaper = NestlyCsv.parseActivity(rows[2], now = 0L)
        assertNotNull(parsedDiaper.diaper)
        assertEquals(DiaperType.WET, parsedDiaper.diaper?.diaperType)
    }
}
