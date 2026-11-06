package com.lifestyle.nestly.ui.trends

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lifestyle.nestly.data.units.UnitPrefs
import com.lifestyle.nestly.ui.components.ActivityIcon
import com.lifestyle.nestly.ui.components.Format
import com.lifestyle.nestly.ui.theme.NestlyColors
import com.lifestyle.nestly.ui.theme.NestlyType
import com.lifestyle.nestly.ui.theme.headerColor
import kotlin.math.abs
import kotlin.math.roundToLong

val TrendSeries.color: Color
    get() = when (this) {
        TrendSeries.FEED, TrendSeries.BOTTLE, TrendSeries.BREAST_MILK -> Color(0xFFF7A93B)
        TrendSeries.BREASTFEED -> NestlyColors.Feed
        TrendSeries.COMBO -> Color(0xFFE5862F)
        TrendSeries.SOLIDS -> Color(0xFFD9C36A)
        TrendSeries.FORMULA -> Color(0xFFFFE29A)
        TrendSeries.OTHER_MILK -> NestlyColors.TextMuted
        TrendSeries.PUMP -> NestlyColors.PumpBlob
        TrendSeries.WET -> Color(0xFFE9DC9A)
        TrendSeries.DIRTY -> Color(0xFFB98D5E)
        TrendSeries.MIXED_DIAPER -> NestlyColors.DiaperBlob
        TrendSeries.DRY -> NestlyColors.TextMuted
        TrendSeries.SLEEP -> NestlyColors.SleepBlob
        TrendSeries.NAP -> NestlyColors.Sleep
        TrendSeries.AWAKE -> NestlyColors.Feed
    }

/** "6.5", "150 mL", "3h 30m". */
fun TrendMetric.formatValue(value: Double, prefs: UnitPrefs): String = when (unit) {
    MetricUnit.COUNT -> Format.number(value, 1)
    MetricUnit.VOLUME -> Format.volume(value, prefs)
    MetricUnit.DURATION -> Format.duration(value.roundToLong())
}

/** "6.5 sessions per day", "980 mL per day", "3h 30m average". */
fun TrendMetric.summary(value: Double, prefs: UnitPrefs): String {
    val amount = if (unit == MetricUnit.COUNT) "${formatValue(value, prefs)} $noun" else formatValue(value, prefs)
    return when (stat) {
        MetricStat.PER_DAY -> "$amount per day"
        MetricStat.AVERAGE -> "$amount average"
    }
}

/** Below this the change rounds to nothing in the badge. */
fun TrendMetric.isMeaningful(delta: Double): Boolean = abs(delta) >= when (unit) {
    MetricUnit.COUNT -> 0.05
    MetricUnit.VOLUME -> 1.5
    MetricUnit.DURATION -> 1.0
}

/** "Fewer sessions than the previous 14 days", "Longer than the previous day". */
fun TrendMetric.comparison(delta: Double, window: TrendsWindow): String {
    val up = delta > 0
    val lead = when {
        unit == MetricUnit.COUNT -> if (up) "More $noun" else "Fewer $noun"
        unit == MetricUnit.DURATION && stat == MetricStat.AVERAGE -> if (up) "Longer" else "Shorter"
        else -> if (up) "More" else "Less"
    }
    val period = if (window.days == 1) "the previous day" else "the previous ${window.days} days"
    return "$lead than $period"
}

/** Small arrow + amount pill tinted with the section colour, e.g. "↓ 0.6". */
@Composable
fun DeltaBadge(metric: TrendMetric, delta: Double, prefs: UnitPrefs) {
    Row(
        Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(metric.section.headerColor)
            .padding(horizontal = 5.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (delta > 0) Icons.Outlined.ArrowUpward else Icons.Outlined.ArrowDownward,
            contentDescription = if (delta > 0) "Up" else "Down",
            tint = NestlyColors.HeaderText,
            modifier = Modifier.size(12.dp),
        )
        Spacer(Modifier.width(3.dp))
        Text(
            metric.formatValue(abs(delta), prefs),
            style = NestlyType.Small.copy(fontSize = 12.sp, lineHeight = 14.sp, fontWeight = FontWeight.SemiBold),
            color = NestlyColors.HeaderText,
        )
    }
}

/** Activity icon, with a small sun or moon for daytime / nighttime metrics. */
@Composable
fun MetricIcon(metric: TrendMetric, size: Dp = 40.dp) {
    Box(Modifier.size(size)) {
        ActivityIcon(metric.icon, size = size)
        val overlay = when (metric.part) {
            DayPart.DAY -> Icons.Outlined.WbSunny
            DayPart.NIGHT -> Icons.Outlined.Bedtime
            DayPart.ALL -> null
        }
        if (overlay != null) {
            Icon(
                overlay,
                contentDescription = null,
                tint = NestlyColors.TextPrimary,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .size(size * 0.38f),
            )
        }
    }
}

/** The "1d 7d 14d" chips in the Trends header. */
@Composable
fun WindowChips(selected: TrendsWindow, onSelect: (TrendsWindow) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        TrendsWindow.entries.forEach { window ->
            val isSelected = window == selected
            Box(
                Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(if (isSelected) NestlyColors.SegmentSelected else Color.Transparent)
                    .border(1.dp, if (isSelected) NestlyColors.SegmentSelected else NestlyColors.TextMuted, RoundedCornerShape(6.dp))
                    .clickable { onSelect(window) }
                    .padding(horizontal = 10.dp, vertical = 5.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(window.label, style = NestlyType.Small.copy(fontWeight = FontWeight.Medium), color = NestlyColors.TextPrimary)
            }
        }
    }
}

@Composable
fun SeriesDot(series: TrendSeries, size: Dp = 10.dp, square: Boolean = false) {
    Box(
        Modifier
            .size(size)
            .clip(if (square) RoundedCornerShape(3.dp) else CircleShape)
            .background(series.color),
    )
}
