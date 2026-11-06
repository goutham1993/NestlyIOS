package com.lifestyle.nestly.data.importer

import com.lifestyle.nestly.data.model.ActivityType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * Runs the bundled real Nara export through the mapper and the deterministic
 * id mapping (the parts of the importer that don't need Supabase), verifying
 * counts and that every mapped row gets a unique, stable UUID.
 */
class NaraSampleImportTest {

    private fun sampleFile(): File {
        val candidates = listOf(
            File("src/androidTest/assets/nara_export.csv"),
            File("app/src/androidTest/assets/nara_export.csv"),
        )
        return candidates.firstOrNull { it.exists() } ?: candidates.first()
    }

    @Test
    fun sampleExportMapsWithUniqueDeterministicIds() {
        val file = sampleFile()
        assumeTrue("sample export present", file.exists())

        val rows = file.bufferedReader(Charsets.UTF_8).use(CsvParser::parseRecords)
        val records = rows.mapNotNull(NaraRowMapper::map)
        val activities = records.filterIsInstance<NaraRecord.Activity>()
        val profiles = records.filterIsInstance<NaraRecord.Profile>()

        assertEquals(1, profiles.size)
        assertEquals(
            mapOf(
                ActivityType.BOTTLE_FEED to 1125,
                ActivityType.PUMP to 1107,
                ActivityType.BREASTFEED to 65,
                ActivityType.GROWTH to 22,
                ActivityType.DIAPER to 9,
                ActivityType.MILESTONE to 3,
            ),
            activities.groupingBy { it.type }.eachCount(),
        )

        val ids = activities.map { NaraIds.activity(it.activityKey) }
        assertEquals("deterministic ids are unique per Nara key", ids.size, ids.toSet().size)
        assertEquals(ids, activities.map { NaraIds.activity(it.activityKey) })
        assertTrue(ids.all { it.length == 36 })

        // Every activity's profile reference resolves to the sample profile key.
        val profileKeys = profiles.map { it.profileKey }.toSet()
        assertTrue(activities.all { it.profileKey == null || it.profileKey in profileKeys })
    }
}
