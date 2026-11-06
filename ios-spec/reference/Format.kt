package com.lifestyle.nestly.ui.components

import com.lifestyle.nestly.data.reminder.NextFeedState
import com.lifestyle.nestly.data.units.UnitPrefs
import com.lifestyle.nestly.data.units.Units
import java.time.Instant
import java.time.LocalDate
import java.time.Period
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.roundToInt

object Format {
    private val timeFormat = DateTimeFormatter.ofPattern("h:mma", Locale.US)
    private val dayFormat = DateTimeFormatter.ofPattern("MMM d", Locale.US)
    private val dayYearFormat = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US)
    private val headerDateFormat = DateTimeFormatter.ofPattern("EEE, MMM d", Locale.US)
    private val longDateFormat = DateTimeFormatter.ofPattern("MMM d yyyy", Locale.US)

    /** "6:14pm" */
    fun time(epochMs: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        timeFormat.format(Instant.ofEpochMilli(epochMs).atZone(zone)).lowercase(Locale.US)

    /** "Today", "Yesterday" or "Sep 30" (with the year if not this year). */
    fun relativeDay(epochMs: Long, now: Long, zone: ZoneId = ZoneId.systemDefault()): String {
        val date = Instant.ofEpochMilli(epochMs).atZone(zone).toLocalDate()
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        return when (date) {
            today -> "Today"
            today.minusDays(1) -> "Yesterday"
            today.plusDays(1) -> "Tomorrow"
            else -> if (date.year == today.year) dayFormat.format(date) else dayYearFormat.format(date)
        }
    }

    /** "Today  8:07pm" */
    fun dayAndTime(epochMs: Long, now: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        "${relativeDay(epochMs, now, zone)}  ${time(epochMs, zone)}"

    /**
     * Calendar-day distance from today: "Today", "Tomorrow", "in 5 days", "in 2 weeks",
     * "in 3 months", "in 1 year", or the past equivalents ("Yesterday", "2 weeks ago").
     */
    fun countdown(epochMs: Long, now: Long, zone: ZoneId = ZoneId.systemDefault()): String {
        val date = Instant.ofEpochMilli(epochMs).atZone(zone).toLocalDate()
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val future = !date.isBefore(today)
        val (from, to) = if (future) today to date else date to today
        val days = ChronoUnit.DAYS.between(from, to)
        val months = ChronoUnit.MONTHS.between(from, to)
        fun unit(value: Long, name: String) = "$value $name${if (value == 1L) "" else "s"}"
        val amount = when {
            days == 0L -> return "Today"
            days == 1L -> return if (future) "Tomorrow" else "Yesterday"
            days < 14 -> unit(days, "day")
            days < 30 || months == 0L -> unit(days / 7, "week")
            months < 12 -> unit(months, "month")
            else -> unit(months / 12, "year")
        }
        return if (future) "in $amount" else "$amount ago"
    }

    /** "Thu, Oct 1" */
    fun headerDate(now: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        headerDateFormat.format(Instant.ofEpochMilli(now).atZone(zone))

    /** "May 12 2026 4:30am" */
    fun longDateTime(epochMs: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        "${longDateFormat.format(Instant.ofEpochMilli(epochMs).atZone(zone))} ${time(epochMs, zone)}"

    /** "Oct 1, 2026" */
    fun date(date: LocalDate): String = dayYearFormat.format(date)

    /**
     * Age since [birthDate]: "Born today", "3 days old", "2 weeks, 3 days old",
     * "4 months, 2 weeks old", "1 year, 3 months old". Null if [birthDate] is
     * in the future. Weeks/days are only shown while under a year old.
     */
    fun age(birthDate: LocalDate, today: LocalDate = LocalDate.now()): String? {
        if (birthDate.isAfter(today)) return null
        val period = Period.between(birthDate, today)
        fun unit(value: Int, name: String) = "$value $name${if (value == 1) "" else "s"}"
        return when {
            period.years > 0 -> listOfNotNull(
                unit(period.years, "year"),
                period.months.takeIf { it > 0 }?.let { unit(it, "month") },
            ).joinToString(", ") + " old"
            period.months > 0 -> listOfNotNull(
                unit(period.months, "month"),
                (period.days / 7).takeIf { it > 0 }?.let { unit(it, "week") },
            ).joinToString(", ") + " old"
            period.days >= 7 -> listOfNotNull(
                unit(period.days / 7, "week"),
                (period.days % 7).takeIf { it > 0 }?.let { unit(it, "day") },
            ).joinToString(", ") + " old"
            period.days > 0 -> "${unit(period.days, "day")} old"
            else -> "Born today"
        }
    }

    /** "1h 53m ago", "5m ago", "Just now", "3d ago" */
    fun ago(epochMs: Long, now: Long): String {
        val minutes = ((now - epochMs) / 60_000).coerceAtLeast(0)
        return when {
            minutes < 1 -> "Just now"
            minutes < 60 -> "${minutes}m ago"
            minutes < 60 * 24 -> "${minutes / 60}h ${minutes % 60}m ago"
            else -> "${minutes / (60 * 24)}d ago"
        }
    }

    /** "1h 5m", "12m", "45s", "0s" */
    fun duration(totalSec: Long): String {
        val h = totalSec / 3600
        val m = (totalSec % 3600) / 60
        val s = totalSec % 60
        return when {
            h > 0 -> "${h}h ${m}m"
            m > 0 -> if (s > 0) "${m}m ${s}s" else "${m}m"
            else -> "${s}s"
        }
    }

    /**
     * "Next feeding in 1h 25m at 7:18pm", or how long it is
     * overdue once that time has passed. Null when no feed has been logged.
     * Whole minutes only: callers tick at most every 30 seconds.
     */
    fun nextFeeding(state: NextFeedState): String? = when (state) {
        is NextFeedState.Upcoming ->
            "Next feeding in ${durationShort(state.remainingMs, roundUp = true)} at ${time(state.dueMs)}"
        is NextFeedState.DueNow -> "Next feeding due now"
        is NextFeedState.Overdue ->
            "Next feeding overdue by ${durationShort(state.overdueMs, roundUp = false)} · due ${time(state.dueMs)}"
        NextFeedState.NoFeed -> null
    }

    /** "1m", "25m", "1h", "1h 25m", "1d 2h". */
    private fun durationShort(ms: Long, roundUp: Boolean): String {
        val totalMinutes = ((if (roundUp) ms + 59_999L else ms) / 60_000L).coerceAtLeast(1)
        val days = totalMinutes / (24 * 60)
        val hours = (totalMinutes % (24 * 60)) / 60
        val minutes = totalMinutes % 60
        val parts = listOfNotNull(
            days.takeIf { it > 0 }?.let { "${it}d" },
            hours.takeIf { it > 0 }?.let { "${it}h" },
            minutes.takeIf { it > 0 || (days == 0L && hours == 0L) }?.let { "${it}m" },
        )
        return parts.joinToString(" ")
    }

    /** "150" for whole numbers, "7.34" otherwise. */
    fun number(value: Double, maxDecimals: Int = 2): String {
        val factor = Math.pow(10.0, maxDecimals.toDouble())
        val rounded = (value * factor).roundToInt() / factor
        return if (rounded == rounded.toLong().toDouble()) rounded.toLong().toString()
        else rounded.toString().trimEnd('0').trimEnd('.')
    }

    fun ml(value: Double): String = "${number(value, 0)} mL"

    fun volume(ml: Double, prefs: UnitPrefs = UnitPrefs.DEFAULT): String {
        val decimals = if (prefs.volume.name == "OZ") 1 else 0
        return "${number(Units.mlToDisplay(ml, prefs.volume), decimals)} ${Units.volumeLabel(prefs.volume)}"
    }

    fun weight(kg: Double, prefs: UnitPrefs = UnitPrefs.DEFAULT): String =
        "${number(Units.kgToDisplay(kg, prefs.weight), if (prefs.weight.name == "LB") 1 else 2)} ${Units.weightLabel(prefs.weight)}"

    fun length(cm: Double, prefs: UnitPrefs = UnitPrefs.DEFAULT): String =
        "${number(Units.cmToDisplay(cm, prefs.length), if (prefs.length.name == "IN") 1 else 1)} ${Units.lengthLabel(prefs.length)}"

    fun temp(celsius: Double, prefs: UnitPrefs = UnitPrefs.DEFAULT): String =
        "${number(Units.cToDisplay(celsius, prefs.temp), 1)} ${Units.tempLabel(prefs.temp)}"

    fun lowerFirst(text: String) = text.replaceFirstChar { it.lowercase(Locale.US) }
}
