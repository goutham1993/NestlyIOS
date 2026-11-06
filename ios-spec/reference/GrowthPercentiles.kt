package com.lifestyle.nestly.data.growth

import com.lifestyle.nestly.data.model.GrowthDetails
import com.lifestyle.nestly.data.model.Sex
import java.time.LocalDate
import java.time.Period
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sign
import kotlin.math.sqrt

/** The three measurements tracked on the Growth card / screen. */
enum class GrowthMetric(val label: String) {
    WEIGHT("Weight"),
    HEIGHT("Height"),
    HEAD("Head Size"),
    ;

    fun valueOf(details: GrowthDetails?): Double? = when (this) {
        WEIGHT -> details?.weightKg
        HEIGHT -> details?.heightCm
        HEAD -> details?.headCm
    }
}

/**
 * WHO percentile maths on top of [WhoGrowthTables]: converts a measurement
 * to a percentile (via its z-score) and generates the percentile curves
 * drawn on the Growth chart. Ages are fractional months; LMS parameters are
 * interpolated linearly between the monthly table rows.
 */
object GrowthPercentiles {
    /** Curves shown on the chart, thinnest standard set used by WHO charts. */
    val CHART_PERCENTILES = listOf(2.0, 5.0, 10.0, 25.0, 50.0, 75.0, 90.0, 95.0, 98.0)

    const val MAX_AGE_MONTHS = 60.0

    private fun table(metric: GrowthMetric, sex: Sex?): Array<Lms>? = when (sex) {
        Sex.MALE -> when (metric) {
            GrowthMetric.WEIGHT -> WhoGrowthTables.weightBoys
            GrowthMetric.HEIGHT -> WhoGrowthTables.lengthBoys
            GrowthMetric.HEAD -> WhoGrowthTables.headBoys
        }
        Sex.FEMALE -> when (metric) {
            GrowthMetric.WEIGHT -> WhoGrowthTables.weightGirls
            GrowthMetric.HEIGHT -> WhoGrowthTables.lengthGirls
            GrowthMetric.HEAD -> WhoGrowthTables.headGirls
        }
        else -> null
    }

    /** Interpolated LMS at [ageMonths], or null when no curve applies. */
    fun lms(metric: GrowthMetric, sex: Sex?, ageMonths: Double): Lms? {
        val rows = table(metric, sex) ?: return null
        if (ageMonths < 0.0 || ageMonths > MAX_AGE_MONTHS) return null
        val lower = ageMonths.toInt().coerceIn(0, rows.lastIndex)
        val upper = (lower + 1).coerceAtMost(rows.lastIndex)
        val fraction = (ageMonths - lower).coerceIn(0.0, 1.0)
        val a = rows[lower]
        val b = rows[upper]
        return Lms(
            l = a.l + (b.l - a.l) * fraction,
            m = a.m + (b.m - a.m) * fraction,
            s = a.s + (b.s - a.s) * fraction,
        )
    }

    /** Percentile (0-100) of [value] at [ageMonths], or null when it can't be computed. */
    fun percentile(metric: GrowthMetric, sex: Sex?, ageMonths: Double, value: Double): Double? {
        val lms = lms(metric, sex, ageMonths) ?: return null
        if (value <= 0.0) return null
        val z = if (abs(lms.l) < 1e-9) {
            ln(value / lms.m) / lms.s
        } else {
            ((value / lms.m).pow(lms.l) - 1.0) / (lms.l * lms.s)
        }
        return normalCdf(z) * 100.0
    }

    /** The measurement value sitting on the [percentile] curve at [ageMonths]. */
    fun valueAtPercentile(metric: GrowthMetric, sex: Sex?, ageMonths: Double, percentile: Double): Double? {
        val lms = lms(metric, sex, ageMonths) ?: return null
        val z = inverseNormalCdf(percentile / 100.0)
        return if (abs(lms.l) < 1e-9) {
            lms.m * exp(lms.s * z)
        } else {
            val base = 1.0 + lms.l * lms.s * z
            if (base <= 0.0) null else lms.m * base.pow(1.0 / lms.l)
        }
    }

    /** Fractional age in months at [date]; negative when before birth. */
    fun ageMonths(birthDate: LocalDate, date: LocalDate): Double =
        ChronoUnit.DAYS.between(birthDate, date) / 30.4375

    /** Compact age as on the Growth list: "5m 2w 2d", "4m 3w", "Born today". */
    fun ageLabel(birthDate: LocalDate, date: LocalDate): String {
        if (date.isBefore(birthDate)) return "Not born yet"
        val period = Period.between(birthDate, date)
        if (period.years > 0) return "${period.years}y ${period.months}m"
        val weeks = period.days / 7
        val days = period.days % 7
        val parts = listOfNotNull(
            period.months.takeIf { it > 0 }?.let { "${it}m" },
            weeks.takeIf { it > 0 }?.let { "${it}w" },
            days.takeIf { it > 0 }?.let { "${it}d" },
        )
        return parts.joinToString(" ").ifEmpty { "0d" }
    }

    /** Standard normal CDF via the Abramowitz–Stegun erf approximation. */
    private fun normalCdf(z: Double): Double = 0.5 * (1.0 + erf(z / sqrt(2.0)))

    private fun erf(x: Double): Double {
        val t = 1.0 / (1.0 + 0.3275911 * abs(x))
        val poly = (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t
        return sign(x) * (1.0 - poly * exp(-x * x))
    }

    /** Inverse standard normal CDF (Acklam's rational approximation). */
    private fun inverseNormalCdf(p: Double): Double {
        require(p in 0.0..1.0)
        val a = doubleArrayOf(-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00)
        val b = doubleArrayOf(-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01)
        val c = doubleArrayOf(-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00)
        val d = doubleArrayOf(7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00)
        val pLow = 0.02425
        return when {
            p < pLow -> {
                val q = sqrt(-2.0 * ln(p))
                ((((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0))
            }
            p <= 1.0 - pLow -> {
                val q = p - 0.5
                val r = q * q
                ((((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
                    ((((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1.0)))
            }
            else -> {
                val q = sqrt(-2.0 * ln(1.0 - p))
                -((((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                    ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0))
            }
        }
    }
}
