package cc.blit.groglog.ui.reports

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.Nights
import cc.blit.groglog.model.Units
import cc.blit.groglog.model.WeekStat
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.theme.GrogColors
import kotlin.math.roundToInt

/** The ranges the weekly bars show at once, in weeks. */
val weekRanges = listOf(8 to "8 weeks", 12 to "12 weeks", 26 to "6 months", 52 to "1 year")

/** Weekly units as bars against the tapering budget, scrolling back to the first week with a log or a reading. */
@Composable
fun WeeksCard(stats: List<WeekStat>, nights: Nights, weeks: Int, onWeeks: (Int) -> Unit, shownHeart: HeartReading, onShowHeart: (HeartReading) -> Unit) {
    val thisWeek = stats.last().start
    val window = rememberChartWindow(span = weeks * 7.0, left = (thisWeek - 7 * (weeks - 1)).number.toDouble())
    val differentiate = differentiatesWithoutColour()
    val centre = { stat: WeekStat -> stat.start.number + 3.5 }
    val hearts = listOf(HeartReading.RESTING, HeartReading.HRV).flatMap { reading ->
        HeartPoint.line(reading, stats.map { it.start }, at = { it.number + 3.5 }) { nights.mean(reading.value, it..(it + 6)) }
    }
    val drawn = HeartPoint.drawn(shownHeart, hearts)
    val heartPoints = hearts.filter { it.reading == drawn }

    ReportCard("Weekly") {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            for ((index, range) in weekRanges.withIndex()) {
                SegmentedButton(
                    selected = weeks == range.first,
                    onClick = {
                        onWeeks(range.first)
                        // A new range opens on the latest weeks.
                        window.reset(range.first * 7.0, (thisWeek - 7 * (range.first - 1)).number.toDouble())
                    },
                    shape = SegmentedButtonDefaults.itemShape(index, weekRanges.size),
                    icon = {},
                    label = { Text(range.second, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                )
            }
        }

        val top = maxOf(Units.WEEKLY_GUIDELINE, stats.maxOfOrNull { it.totals.units } ?: 0.0, stats.mapNotNull { it.budget }.maxOrNull() ?: 0.0) * 1.15
        val scale = HeartScale.of(heartPoints, top)
        val plot = Plot(
            from = stats.first().start.number.toDouble(),
            to = (thisWeek + 7).number.toDouble(),
            top = top,
            bars = stats.map { week ->
                val over = week.budget?.let { week.totals.units > it } == true
                PlotBar(centre(week), 4.4, listOf(week.totals.units to if (over) GrogColors.over else GrogColors.grog), mark = if (differentiate && over) "!" else null, shaded = true)
            },
            lines = listOf(PlotLine(stats.filter { it.budget != null }.map { centre(it) to it.budget!! }, GrogColors.dry, width = 2.5.dp, step = 7.0)) +
                // Resting rate is the heavier line, since it keeps falling for weeks after the drinking does.
                heartLines(heartPoints, scale, dots = false) { if (it.reading == HeartReading.RESTING) 2.5.dp else 1.5.dp },
            dots = heartDots(heartPoints, scale, dots = false, size = 6.dp),
            rules = listOf(thisWeek.number + 3.5),
            guide = Units.WEEKLY_GUIDELINE to "14 u guideline",
            rightTicks = scale?.ticks?.map { it.first to it.second.toString() }.orEmpty(),
            rightColor = scale?.color ?: androidx.compose.ui.graphics.Color.Unspecified,
            slots = stats.map { week ->
                val over = week.budget?.let { week.totals.units > it } == true
                val parts = listOfNotNull(
                    "Week of ${DateText.format(week.start, "dMMMM")}",
                    "${week.totals.units.unitsText} units",
                    week.budget?.let { "budget ${it.unitsText}" },
                    if (over) "over budget" else null,
                    heartPoints.firstOrNull { !it.bridge && it.x == centre(week) }?.let { "${it.reading.label} ${it.value.roundToInt()} ${it.reading.unit}" },
                )
                PlotSlot(week.start.number.toDouble(), week.start.number + 7.0, parts.joinToString(", "))
            },
            xAxis = XAxis.Months,
        )
        TimeChart(plot, window, height = 220.dp)

        Row(verticalAlignment = Alignment.CenterVertically) {
            LegendRow(Modifier.weight(1f)) {
                LegendKey("Units", GrogColors.grog)
                LegendKey("Budget", GrogColors.dry)
            }
            Text("scroll back", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
        }
        HeartChips(hearts, "", shownHeart, onShowHeart)
    }
}
