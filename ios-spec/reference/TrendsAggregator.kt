package com.lifestyle.nestly.ui.trends

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.DiaperType
import com.lifestyle.nestly.data.model.MilkType
import com.lifestyle.nestly.data.prefs.CardKind
import com.lifestyle.nestly.ui.components.IconKind
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

enum class MetricUnit { COUNT, VOLUME, DURATION }

/** PER_DAY: window total / days. AVERAGE: mean of the individual samples (bottles, gaps, naps…). */
enum class MetricStat { PER_DAY, AVERAGE }

enum class DayPart { ALL, DAY, NIGHT }

enum class TrendSeries(val label: String) {
    FEED("Feeds"),
    BOTTLE("Bottle Feed"),
    BREASTFEED("Breastfeed"),
    COMBO("Combo Feed"),
    SOLIDS("Solids"),
    BREAST_MILK("Breast Milk"),
    FORMULA("Formula"),
    OTHER_MILK("Unspecified"),
    PUMP("Pump"),
    WET("Wet"),
    DIRTY("Dirty"),
    MIXED_DIAPER("Wet + Dirty"),
    DRY("Dry"),
    SLEEP("Sleep"),
    NAP("Naps"),
    AWAKE("Awake"),
}

enum class TrendMetric(
    val section: CardKind,
    val title: String,
    val icon: IconKind,
    val unit: MetricUnit,
    val stat: MetricStat,
    val part: DayPart = DayPart.ALL,
    /** Plural noun for counts, e.g. "6.5 sessions per day". */
    val noun: String = "",
    /** Show the per-series breakdown under the value in the Trends list. */
    val showBreakdown: Boolean = false,
) {
    FEED_SESSIONS(CardKind.FEED, "Feed Sessions", IconKind.BOTTLE, MetricUnit.COUNT, MetricStat.PER_DAY, noun = "sessions", showBreakdown = true),
    TOTAL_BF(CardKind.FEED, "Total BF Hours", IconKind.BREAST, MetricUnit.DURATION, MetricStat.PER_DAY),
    DAY_BF(CardKind.FEED, "Daytime BF Hours", IconKind.BREAST, MetricUnit.DURATION, MetricStat.PER_DAY, DayPart.DAY),
    NIGHT_BF(CardKind.FEED, "Nighttime BF Hours", IconKind.BREAST, MetricUnit.DURATION, MetricStat.PER_DAY, DayPart.NIGHT),
    BF_LENGTH(CardKind.FEED, "BF Session Length", IconKind.BREAST, MetricUnit.DURATION, MetricStat.AVERAGE),
    AMOUNT_BOTTLEFED(CardKind.FEED, "Amount Bottlefed", IconKind.BOTTLE, MetricUnit.VOLUME, MetricStat.PER_DAY, showBreakdown = true),
    BOTTLE_SIZE(CardKind.FEED, "Bottle Size", IconKind.BOTTLE, MetricUnit.VOLUME, MetricStat.AVERAGE),
    TIME_BETWEEN_FEEDS(CardKind.FEED, "Time Btwn Feedings", IconKind.COMBO, MetricUnit.DURATION, MetricStat.AVERAGE),
    PUMP_SESSIONS(CardKind.PUMP, "Pump Sessions", IconKind.PUMP, MetricUnit.COUNT, MetricStat.PER_DAY, noun = "sessions"),
    AMOUNT_PUMPED(CardKind.PUMP, "Amount Pumped", IconKind.PUMP, MetricUnit.VOLUME, MetricStat.PER_DAY),
    PUMP_HOURS(CardKind.PUMP, "Total Pump Hours", IconKind.PUMP, MetricUnit.DURATION, MetricStat.PER_DAY),
    TOTAL_DIAPERS(CardKind.DIAPER, "Total Diapers", IconKind.DIAPER, MetricUnit.COUNT, MetricStat.PER_DAY, noun = "diapers", showBreakdown = true),
    DAY_DIAPERS(CardKind.DIAPER, "Daytime Diapers", IconKind.DIAPER, MetricUnit.COUNT, MetricStat.PER_DAY, DayPart.DAY, noun = "diapers"),
    NIGHT_DIAPERS(CardKind.DIAPER, "Nighttime Diapers", IconKind.DIAPER, MetricUnit.COUNT, MetricStat.PER_DAY, DayPart.NIGHT, noun = "diapers"),
    TOTAL_SLEEP(CardKind.SLEEP, "Total Sleep", IconKind.SLEEP, MetricUnit.DURATION, MetricStat.PER_DAY),
    DAY_SLEEP(CardKind.SLEEP, "Daytime Sleep", IconKind.SLEEP, MetricUnit.DURATION, MetricStat.PER_DAY, DayPart.DAY),
    NIGHT_SLEEP(CardKind.SLEEP, "Nighttime Sleep", IconKind.SLEEP, MetricUnit.DURATION, MetricStat.PER_DAY, DayPart.NIGHT),
    LONGEST_SLEEP(CardKind.SLEEP, "Longest Sleep", IconKind.SLEEP, MetricUnit.DURATION, MetricStat.AVERAGE),
    DAY_NAPS(CardKind.SLEEP, "Daytime Naps", IconKind.SLEEP, MetricUnit.COUNT, MetricStat.PER_DAY, DayPart.DAY, noun = "naps"),
    NAP_LENGTH(CardKind.SLEEP, "Daytime Nap Length", IconKind.SLEEP, MetricUnit.DURATION, MetricStat.AVERAGE, DayPart.DAY),
    WAKE_WINDOW(CardKind.SLEEP, "Wake Window", IconKind.SLEEP, MetricUnit.DURATION, MetricStat.AVERAGE),
}

data class TrendSegment(val series: TrendSeries, val value: Double)

data class TrendDay(val date: LocalDate, val segments: List<TrendSegment>) {
    val total: Double get() = segments.sumOf { it.value }
}

/** Something to plot on the calendar: a point (start == end) or an interval such as a sleep. */
data class TrendMark(val entryId: String, val series: TrendSeries, val startMs: Long, val endMs: Long)

data class MetricResult(
    val metric: TrendMetric,
    /** Per-day average for [MetricStat.PER_DAY], sample mean for [MetricStat.AVERAGE]. Counts, mL or seconds. */
    val value: Double,
    val sampleCount: Int,
    val days: List<TrendDay>,
    /** Same statistic as [value], split by series. */
    val breakdown: List<TrendSegment>,
    /** Contributing entries, newest first. */
    val entries: List<ActivityEntity>,
    val marks: List<TrendMark>,
)

object TrendsAggregator {
    /** Daytime is 6am–6pm, matching the light band on the History and Trends calendars. */
    const val DAY_START_HOUR = 6
    const val DAY_END_HOUR = 18

    private class Sample(val date: LocalDate, val series: TrendSeries, val value: Double, val entry: ActivityEntity)

    private class Session(val startMs: Long, val series: TrendSeries, val entries: List<ActivityEntity>)

    fun computeAll(entries: List<ActivityEntity>, from: LocalDate, days: Int, zone: ZoneId = ZoneId.systemDefault()) =
        TrendMetric.entries.map { compute(it, entries, from, days, zone) }

    fun compute(
        metric: TrendMetric,
        entries: List<ActivityEntity>,
        from: LocalDate,
        days: Int,
        zone: ZoneId = ZoneId.systemDefault(),
    ): MetricResult {
        val dates = (0 until days).map { from.plusDays(it.toLong()) }
        val until = from.plusDays(days.toLong())
        val (allSamples, allMarks) = samples(metric, entries, zone)
        val samples = allSamples.filter { !it.date.isBefore(from) && it.date.isBefore(until) }
        val fromMs = from.atStartOfDay(zone).toInstant().toEpochMilli()
        val untilMs = until.atStartOfDay(zone).toInstant().toEpochMilli()
        val marks = allMarks.filter { it.endMs >= fromMs && it.startMs < untilMs }

        val byDate = samples.groupBy { it.date }
        val trendDays = dates.map { date ->
            val day = byDate[date].orEmpty()
            TrendDay(date, combine(day, metric.stat, divisor = 1))
        }
        val value = when (metric.stat) {
            MetricStat.PER_DAY -> if (days == 0) 0.0 else samples.sumOf { it.value } / days
            MetricStat.AVERAGE -> if (samples.isEmpty()) 0.0 else samples.sumOf { it.value } / samples.size
        }
        return MetricResult(
            metric = metric,
            value = value,
            sampleCount = samples.size,
            days = trendDays,
            breakdown = combine(samples, metric.stat, divisor = days),
            entries = samples.map { it.entry }.distinctBy { it.id }.sortedByDescending { it.startTime },
            marks = marks,
        )
    }

    private fun combine(samples: List<Sample>, stat: MetricStat, divisor: Int): List<TrendSegment> =
        samples.groupBy { it.series }
            .map { (series, list) ->
                val sum = list.sumOf { it.value }
                TrendSegment(series, if (stat == MetricStat.PER_DAY) sum / divisor.coerceAtLeast(1) else sum / list.size)
            }
            .sortedBy { it.series.ordinal }

    private fun samples(metric: TrendMetric, entries: List<ActivityEntity>, zone: ZoneId): Pair<List<Sample>, List<TrendMark>> {
        val ascending = entries.sortedBy { it.startTime }
        val feeds = ascending.filter { it.type in FeedTypes }
        val breastfeeds = ascending.filter { it.type == ActivityType.BREASTFEED }
        val bottles = ascending.filter { it.type == ActivityType.BOTTLE_FEED }
        val pumps = ascending.filter { it.type == ActivityType.PUMP }
        val diapers = ascending.filter { it.type == ActivityType.DIAPER }
        val sleeps = ascending.filter { it.type == ActivityType.SLEEP && it.endTime != null && it.endTime > it.startTime }

        fun ActivityEntity.date() = date(startTime, zone)
        fun ActivityEntity.daytime() = isDaytime(startTime, zone)
        fun pointMarks(list: List<ActivityEntity>, series: (ActivityEntity) -> TrendSeries) =
            list.map { TrendMark(it.id, series(it), it.startTime, it.startTime) }

        return when (metric) {
            TrendMetric.FEED_SESSIONS -> {
                val sessions = sessions(feeds)
                sessions.map { Sample(date(it.startMs, zone), it.series, 1.0, it.entries.first()) } to
                    sessions.flatMap { s -> s.entries.map { TrendMark(it.id, s.series, it.startTime, it.startTime) } }
            }
            TrendMetric.TOTAL_BF, TrendMetric.DAY_BF, TrendMetric.NIGHT_BF -> {
                val list = breastfeeds.filter {
                    when (metric.part) {
                        DayPart.ALL -> true
                        DayPart.DAY -> it.daytime()
                        DayPart.NIGHT -> !it.daytime()
                    }
                }
                list.map { Sample(it.date(), TrendSeries.BREASTFEED, breastSec(it).toDouble(), it) } to
                    list.map { TrendMark(it.id, TrendSeries.BREASTFEED, it.startTime, it.endTime ?: (it.startTime + breastSec(it) * 1000)) }
            }
            TrendMetric.BF_LENGTH -> {
                val list = breastfeeds.filter { breastSec(it) > 0 }
                list.map { Sample(it.date(), TrendSeries.BREASTFEED, breastSec(it).toDouble(), it) } to
                    list.map { TrendMark(it.id, TrendSeries.BREASTFEED, it.startTime, it.endTime ?: (it.startTime + breastSec(it) * 1000)) }
            }
            TrendMetric.AMOUNT_BOTTLEFED -> {
                val samples = bottles.flatMap { entry ->
                    val b = entry.bottle ?: return@flatMap emptyList()
                    val total = b.totalMl ?: ((b.breastMilkMl ?: 0.0) + (b.formulaMl ?: 0.0))
                    val breastMilk = b.breastMilkMl ?: if (b.milkType == MilkType.BREAST_MILK) total else 0.0
                    val formula = b.formulaMl ?: if (b.milkType == MilkType.FORMULA) total else 0.0
                    val other = (total - breastMilk - formula).coerceAtLeast(0.0)
                    listOf(TrendSeries.BREAST_MILK to breastMilk, TrendSeries.FORMULA to formula, TrendSeries.OTHER_MILK to other)
                        .filter { it.second > 0 }
                        .map { (series, ml) -> Sample(entry.date(), series, ml, entry) }
                }
                samples to pointMarks(samples.map { it.entry }.distinct()) { milkSeries(it) }
            }
            TrendMetric.BOTTLE_SIZE -> {
                val list = bottles.filter { (it.bottle?.totalMl ?: 0.0) > 0 }
                list.map { Sample(it.date(), TrendSeries.BOTTLE, it.bottle!!.totalMl!!, it) } to
                    pointMarks(list) { TrendSeries.BOTTLE }
            }
            TrendMetric.TIME_BETWEEN_FEEDS -> {
                val sessions = sessions(feeds)
                sessions.zipWithNext { prev, next ->
                    Sample(date(next.startMs, zone), TrendSeries.FEED, (next.startMs - prev.startMs) / 1000.0, next.entries.first())
                } to sessions.map { TrendMark(it.entries.first().id, it.series, it.startMs, it.startMs) }
            }
            TrendMetric.PUMP_SESSIONS ->
                pumps.map { Sample(it.date(), TrendSeries.PUMP, 1.0, it) } to pumpMarks(pumps)
            TrendMetric.AMOUNT_PUMPED -> {
                val list = pumps.filter { pumpMl(it) > 0 }
                list.map { Sample(it.date(), TrendSeries.PUMP, pumpMl(it), it) } to pumpMarks(list)
            }
            TrendMetric.PUMP_HOURS -> {
                val list = pumps.filter { (it.pump?.durationSec ?: 0) > 0 }
                list.map { Sample(it.date(), TrendSeries.PUMP, it.pump!!.durationSec.toDouble(), it) } to pumpMarks(list)
            }
            TrendMetric.TOTAL_DIAPERS, TrendMetric.DAY_DIAPERS, TrendMetric.NIGHT_DIAPERS -> {
                val list = diapers.filter {
                    when (metric.part) {
                        DayPart.ALL -> true
                        DayPart.DAY -> it.daytime()
                        DayPart.NIGHT -> !it.daytime()
                    }
                }
                list.map { Sample(it.date(), diaperSeries(it), 1.0, it) } to pointMarks(list, ::diaperSeries)
            }
            TrendMetric.TOTAL_SLEEP, TrendMetric.DAY_SLEEP, TrendMetric.NIGHT_SLEEP -> {
                // Split each sleep across the calendar days (and day/night bands) it overlaps.
                val samples = sleeps.flatMap { sleep ->
                    val end = sleep.endTime!!
                    var date = date(sleep.startTime, zone)
                    val lastDate = date(end, zone)
                    buildList {
                        while (!date.isAfter(lastDate)) {
                            val dayStart = date.atStartOfDay(zone).toInstant().toEpochMilli()
                            val nextDay = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
                            val lightStart = date.atTime(DAY_START_HOUR, 0).atZone(zone).toInstant().toEpochMilli()
                            val lightEnd = date.atTime(DAY_END_HOUR, 0).atZone(zone).toInstant().toEpochMilli()
                            val total = overlapSec(sleep.startTime, end, dayStart, nextDay)
                            val light = overlapSec(sleep.startTime, end, lightStart, lightEnd)
                            val sec = when (metric.part) {
                                DayPart.ALL -> total
                                DayPart.DAY -> light
                                DayPart.NIGHT -> total - light
                            }
                            if (sec > 0) add(Sample(date, TrendSeries.SLEEP, sec, sleep))
                            date = date.plusDays(1)
                        }
                    }
                }
                samples to sleepMarks(samples.map { it.entry }.distinct())
            }
            TrendMetric.LONGEST_SLEEP -> {
                val longest = sleeps.groupBy { it.date() }.map { (date, list) ->
                    val best = list.maxBy { it.endTime!! - it.startTime }
                    Sample(date, TrendSeries.SLEEP, (best.endTime!! - best.startTime) / 1000.0, best)
                }
                longest to sleepMarks(longest.map { it.entry })
            }
            TrendMetric.DAY_NAPS, TrendMetric.NAP_LENGTH -> {
                val naps = sleeps.filter { it.daytime() }
                naps.map {
                    val value = if (metric == TrendMetric.DAY_NAPS) 1.0 else (it.endTime!! - it.startTime) / 1000.0
                    Sample(it.date(), TrendSeries.NAP, value, it)
                } to sleepMarks(naps, TrendSeries.NAP)
            }
            TrendMetric.WAKE_WINDOW -> {
                val gaps = sleeps.zipWithNext().filter { (prev, next) -> next.startTime > prev.endTime!! }
                gaps.map { (prev, next) ->
                    Sample(next.date(), TrendSeries.AWAKE, (next.startTime - prev.endTime!!) / 1000.0, next)
                } to gaps.map { (prev, next) -> TrendMark(next.id, TrendSeries.AWAKE, prev.endTime!!, next.startTime) }
            }
        }
    }

    private val FeedTypes = setOf(ActivityType.BOTTLE_FEED, ActivityType.BREASTFEED, ActivityType.SOLIDS)

    /** Feeds saved together from one Combo Feed count as a single session. */
    private fun sessions(feeds: List<ActivityEntity>): List<Session> =
        feeds.groupBy { it.comboGroupId ?: it.id }.values
            .map { group ->
                val types = group.map { it.type }.toSet()
                val series = when {
                    types.size > 1 -> TrendSeries.COMBO
                    ActivityType.BOTTLE_FEED in types -> TrendSeries.BOTTLE
                    ActivityType.BREASTFEED in types -> TrendSeries.BREASTFEED
                    else -> TrendSeries.SOLIDS
                }
                Session(group.minOf { it.startTime }, series, group.sortedBy { it.startTime })
            }
            .sortedBy { it.startMs }

    private fun breastSec(entry: ActivityEntity): Long =
        entry.breastfeed?.let { it.leftDurationSec + it.rightDurationSec } ?: 0

    private fun pumpMl(entry: ActivityEntity): Double =
        entry.pump?.let { it.totalMl ?: ((it.leftMl ?: 0.0) + (it.rightMl ?: 0.0)) } ?: 0.0

    private fun pumpMarks(list: List<ActivityEntity>) = list.map {
        TrendMark(it.id, TrendSeries.PUMP, it.startTime, it.endTime ?: (it.startTime + (it.pump?.durationSec ?: 0) * 1000))
    }

    private fun sleepMarks(list: List<ActivityEntity>, series: TrendSeries = TrendSeries.SLEEP) =
        list.map { TrendMark(it.id, series, it.startTime, it.endTime ?: it.startTime) }

    private fun milkSeries(entry: ActivityEntity): TrendSeries = when (entry.bottle?.milkType) {
        MilkType.BREAST_MILK -> TrendSeries.BREAST_MILK
        MilkType.FORMULA -> TrendSeries.FORMULA
        else -> TrendSeries.OTHER_MILK
    }

    private fun diaperSeries(entry: ActivityEntity): TrendSeries = when (entry.diaper?.diaperType) {
        DiaperType.WET -> TrendSeries.WET
        DiaperType.DIRTY -> TrendSeries.DIRTY
        DiaperType.MIXED -> TrendSeries.MIXED_DIAPER
        DiaperType.DRY, null -> TrendSeries.DRY
    }

    private fun date(ms: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()

    private fun isDaytime(ms: Long, zone: ZoneId): Boolean =
        Instant.ofEpochMilli(ms).atZone(zone).hour in DAY_START_HOUR until DAY_END_HOUR

    private fun overlapSec(start: Long, end: Long, from: Long, until: Long): Double =
        ((minOf(end, until) - maxOf(start, from)) / 1000.0).coerceAtLeast(0.0)
}
