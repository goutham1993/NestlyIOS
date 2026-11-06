package com.lifestyle.nestly.data.importer

import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BreastSide
import com.lifestyle.nestly.data.model.DiaperType
import com.lifestyle.nestly.data.model.MilkType
import com.lifestyle.nestly.data.model.Sex
import com.lifestyle.nestly.data.model.StoolColor
import com.lifestyle.nestly.data.model.StoolTexture
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.LocalDate

class NaraRowMapperTest {
    private fun row(type: String, vararg fields: Pair<String, String>) = mapOf(
        "Type" to type,
        "Start Date/time (Epoch)" to "1790896458000",
        "Time Zone" to "America/Chicago",
        "Created By Caregiver" to "Pravalika",
        "_familyKey" to "f-1",
        "_profileKey" to "c-1",
        "_activityKey" to "t-1",
    ) + fields

    private fun activity(row: Map<String, String>) = NaraRowMapper.map(row) as NaraRecord.Activity

    @Test
    fun bottleBreastMilk() {
        val a = activity(
            row(
                "Bottle Feed",
                "[Bottle Feed] Type" to "Breast Milk",
                "[Bottle Feed] Breast Milk Volume" to "150",
                "[Bottle Feed] Breast Milk Volume Unit" to "ML",
            ),
        )
        assertEquals(ActivityType.BOTTLE_FEED, a.type)
        assertEquals(MilkType.BREAST_MILK, a.bottle!!.milkType)
        assertEquals(150.0, a.bottle!!.totalMl!!, 0.0)
        assertEquals("Pravalika", a.updatedBy)
    }

    @Test
    fun bottleWithOnlyGenericVolumeHasUnknownMilkType() {
        val a = activity(row("Bottle Feed", "[Bottle Feed] Volume" to "60", "[Bottle Feed] Volume Unit" to "ML"))
        assertNull(a.bottle!!.milkType)
        assertEquals(60.0, a.bottle!!.totalMl!!, 0.0)
    }

    @Test
    fun pumpClampsNegativeDurationAndEndBeforeStart() {
        val a = activity(
            row(
                "Pump",
                "[Pump] Duration (Seconds)" to "-83820",
                "[Pump] End Date/time (Epoch)" to "1790800000000",
                "[Pump] Total Volume" to "130",
                "[Pump] Total Volume Unit" to "ML",
            ) - "_profileKey",
        )
        assertNull(a.profileKey)
        assertEquals(0L, a.pump!!.durationSec)
        assertEquals(a.startTime, a.endTime)
        assertEquals(130.0, a.pump!!.totalMl!!, 0.0)
    }

    @Test
    fun pumpConvertsFlozAndSumsSides() {
        val a = activity(
            row(
                "Pump",
                "[Pump] Left Volume" to "3",
                "[Pump] Left Volume Unit" to "FLOZ",
                "[Pump] Right Volume" to "3",
                "[Pump] Right Volume Unit" to "FLOZ",
            ),
        )
        assertEquals(88.72, a.pump!!.leftMl!!, 0.01)
        assertEquals(177.44, a.pump!!.totalMl!!, 0.01)
    }

    @Test
    fun breastfeedNonTimerIsManual() {
        val a = activity(
            row(
                "Breastfeed",
                "[Breastfeed] Begin Side" to "LEFT",
                "[Breastfeed] End Side" to "RIGHT.nonTimer",
                "[Breastfeed] Left Duration (Seconds)" to "600",
                "[Breastfeed] Right Duration (Seconds)" to "300",
            ),
        )
        val b = a.breastfeed!!
        assertEquals(BreastSide.LEFT, b.beginSide)
        assertEquals(BreastSide.RIGHT, b.endSide)
        assertTrue(b.isManualEntry)
        assertEquals(a.startTime + 900_000, a.endTime)
    }

    @Test
    fun breastfeedTimerIsNotManual() {
        val a = activity(row("Breastfeed", "[Breastfeed] End Side" to "LEFT"))
        assertFalse(a.breastfeed!!.isManualEntry)
    }

    @Test
    fun diaperDirtyWetIsMixed() {
        val a = activity(
            row(
                "Diaper",
                "[Diaper] Type" to "Dirty Wet",
                "[Diaper] Dirty Color" to "YELLOW",
                "[Diaper] Dirty Texture" to "MUCOUS",
            ),
        )
        assertEquals(DiaperType.MIXED, a.diaper!!.diaperType)
        assertEquals(StoolColor.YELLOW, a.diaper!!.color)
        assertEquals(StoolTexture.MUCOUS, a.diaper!!.texture)
    }

    @Test
    fun growthConvertsInchesToCm() {
        val a = activity(
            row(
                "Growth",
                "[Growth] Height" to "22",
                "[Growth] Height Unit" to "IN",
                "[Growth] Weight" to "7.6",
                "[Growth] Weight Unit" to "KG",
            ),
        )
        assertEquals(55.88, a.growth!!.heightCm!!, 0.001)
        assertEquals(7.6, a.growth!!.weightKg!!, 0.0)
        assertNull(a.growth!!.headCm)
    }

    @Test
    fun profileRow() {
        val p = NaraRowMapper.map(
            mapOf(
                "Type" to "Profile",
                "Profile Name" to "Rithan",
                "[Profile] Birth Date" to "2026-05-04",
                "[Profile] Sex" to "MALE",
                "[Profile] Type" to "CHILD",
                "_familyKey" to "f-1",
                "_profileKey" to "c-1",
            ),
        ) as NaraRecord.Profile
        assertEquals(LocalDate.of(2026, 5, 4), p.birthDate)
        assertEquals(Sex.MALE, p.sex)
    }

    @Test
    fun unknownTypeIsSkipped() {
        assertNull(NaraRowMapper.map(row("Sleep")))
    }

    @Test
    fun realExportMapsEveryRow() {
        val file = File("src/androidTest/assets/nara_export.csv")
        if (!file.exists()) return
        val rows = file.reader().use(CsvParser::parseRecords)
        val records = rows.mapNotNull(NaraRowMapper::map)
        assertEquals(rows.size, records.size)
        val counts = records.filterIsInstance<NaraRecord.Activity>().groupingBy { it.type }.eachCount()
        assertEquals(
            mapOf(
                ActivityType.BOTTLE_FEED to 1125,
                ActivityType.PUMP to 1107,
                ActivityType.BREASTFEED to 65,
                ActivityType.GROWTH to 22,
                ActivityType.DIAPER to 9,
                ActivityType.MILESTONE to 3,
            ),
            counts,
        )
        assertEquals(1, records.count { it is NaraRecord.Profile })
    }
}
