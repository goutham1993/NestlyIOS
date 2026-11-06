package com.lifestyle.nestly.data.growth

import com.lifestyle.nestly.data.model.Sex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class GrowthPercentilesTest {

    @Test
    fun medianMeasurementIsThe50thPercentile() {
        // WHO weight-for-age, boys, 6 months: M = 7.934 kg.
        val percentile = GrowthPercentiles.percentile(GrowthMetric.WEIGHT, Sex.MALE, 6.0, 7.934)
        assertEquals(50.0, percentile!!, 1.0)
        assertEquals(
            7.934,
            GrowthPercentiles.valueAtPercentile(GrowthMetric.WEIGHT, Sex.MALE, 6.0, 50.0)!!,
            0.01,
        )
    }

    @Test
    fun screenshotExampleLandsNearThe75thPercentile() {
        // Reference screenshot: boy, 8.35 kg at 5m 2w 2d shown as 75%.
        val percentile = GrowthPercentiles.percentile(GrowthMetric.WEIGHT, Sex.MALE, 5.55, 8.35)
        assertTrue("was $percentile", percentile!! in 70.0..80.0)
    }

    @Test
    fun percentileCurvesIncreaseWithPercentileAndAge() {
        val ages = listOf(0.0, 6.0, 12.0, 24.0)
        ages.forEach { age ->
            val values = GrowthPercentiles.CHART_PERCENTILES.map {
                GrowthPercentiles.valueAtPercentile(GrowthMetric.HEIGHT, Sex.FEMALE, age, it)!!
            }
            assertEquals(values.sorted(), values)
        }
        val medians = ages.map {
            GrowthPercentiles.valueAtPercentile(GrowthMetric.HEIGHT, Sex.FEMALE, it, 50.0)!!
        }
        assertEquals(medians.sorted(), medians)
    }

    @Test
    fun noPercentileWithoutSexBirthRange() {
        assertNull(GrowthPercentiles.percentile(GrowthMetric.WEIGHT, null, 6.0, 8.0))
        assertNull(GrowthPercentiles.percentile(GrowthMetric.WEIGHT, Sex.OTHER, 6.0, 8.0))
        assertNull(GrowthPercentiles.percentile(GrowthMetric.WEIGHT, Sex.MALE, 61.0, 18.0))
        assertNull(GrowthPercentiles.valueAtPercentile(GrowthMetric.HEAD, Sex.FEMALE, -1.0, 50.0))
    }

    @Test
    fun ageLabelMatchesScreenshotFormat() {
        val birth = LocalDate.of(2026, 5, 4)
        assertEquals("5m 2w 2d", GrowthPercentiles.ageLabel(birth, LocalDate.of(2026, 10, 20)))
        assertEquals("4m 3w", GrowthPercentiles.ageLabel(birth, LocalDate.of(2026, 9, 25)))
        assertEquals("0d", GrowthPercentiles.ageLabel(birth, birth))
    }
}
