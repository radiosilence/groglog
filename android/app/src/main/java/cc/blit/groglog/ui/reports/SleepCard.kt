package cc.blit.groglog.ui.reports

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Nights
import cc.blit.groglog.model.Sleep
import cc.blit.groglog.model.mean
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.theme.GrogColors
import kotlin.math.abs
import kotlin.math.roundToInt
import cc.blit.groglog.ui.shared.LegendKey
import cc.blit.groglog.ui.shared.LegendRow

enum class SleepStageBar(val label: String, val color: Color, val seconds: (Sleep) -> Double) {
    DEEP("Deep", GrogColors.deepSleep, { it.deep }),
    CORE("Core", GrogColors.coreSleep, { it.core + it.unstaged }),
    REM("REM", GrogColors.remSleep, { it.rem }),
    AWAKE("Awake", Color.Gray.copy(alpha = 0.35f), { it.awake }),
}

fun duration(seconds: Double): String {
    val minutes = (seconds / 60).roundToInt()
    return if (minutes >= 60) "${minutes / 60} h ${minutes % 60} m" else "$minutes m"
}

/** Time asleep and REM against the week before. Alcohol takes REM first, so its share says more than the total. */
fun sleepSummary(nights: Nights, night: DayKey, today: DayKey): List<AnnotatedString> {
    val sleep = nights[night]?.sleep ?: return emptyList()
    val before = ((night - 7)..(night - 1)).mapNotNull { nights[it]?.sleep }
    fun usual(value: (Sleep) -> Double?) = before.mapNotNull(value).takeIf { it.size >= 3 }?.mean
    val asleepChange = usual { it.asleep }?.let { sleep.asleep - it }
    val remChange = sleep.remShare?.let { share -> usual { it.remShare }?.let { (share - it) * 100 } }
    fun AnnotatedString.Builder.against(change: Double?, text: String?) {
        if (change == null || text == null) return
        withStyle(SpanStyle(color = if (change < 0) GrogColors.over else GrogColors.dry)) { append(", $text") }
    }
    val asleepText = asleepChange?.takeIf { abs(it) >= 300 }?.let { "${duration(abs(it))} ${if (it < 0) "less" else "more"} than the week before" }
    val remText = remChange?.takeIf { abs(it) >= 1 }?.let { "${abs(it).roundToInt()} points ${if (it < 0) "under" else "over"} the week before" }
    val now = if (night == today - 1) "Last night" else DateText.format(night, "EEEE")
    return listOfNotNull(
        buildAnnotatedString {
            append("$now ${duration(sleep.asleep)} asleep")
            against(asleepChange, asleepText)
        },
        sleep.remShare?.let { share ->
            buildAnnotatedString {
                append("REM ${duration(sleep.rem)}, ${(share * 100).roundToInt()}% of sleep")
                against(remChange, remText)
            }
        },
    )
}

/** Each night's sleep by stage, over what was drunk the evening before it. */
@Composable
fun SleepCard(ledger: Ledger, nights: Nights) {
    val today = ledger.today
    val slept = nights.byDay.filterValues { it.sleep != null }.keys
    val first = maxOf(slept.minOrNull() ?: today, today - 90)
    val days = if (first < today) (first..(today - 1)).toList() else emptyList()
    val window = rememberChartWindow(span = 14.0, left = (today - 13).number.toDouble())

    val bars = days.mapNotNull { day ->
        val sleep = nights[day]?.sleep ?: return@mapNotNull null
        day to SleepStageBar.entries.map { it.seconds(sleep) / 3600 to it.color }
    }
    val drank = days.filter(ledger::isLogged).map { it to ledger.totals(it).units }
    val top = maxOf(10.0, bars.maxOfOrNull { (_, stack) -> stack.sumOf { it.first } } ?: 0.0) * 1.1
    // Units share the height on their own scale, read off the right-hand axis.
    val most = maxOf(10.0, drank.maxOfOrNull { it.second } ?: 0.0) * 1.1
    val y = { units: Double -> units / most * top }
    val step = if (most > 60) 20 else if (most > 25) 10 else 5

    ReportCard("Sleep") {
        days.lastOrNull { nights[it]?.sleep != null }?.let { lastNight ->
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                for (line in sleepSummary(nights, lastNight, today)) {
                    Text(line, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        val plot = Plot(
            from = days.firstOrNull()?.number?.toDouble() ?: (today - 14).number.toDouble(),
            to = today.number.toDouble(),
            top = top,
            bars = bars.map { (day, stack) -> PlotBar(day.number + 0.5, 0.62, stack.filter { it.first > 0 }) },
            lines = listOf(PlotLine(drank.map { (day, units) -> day.number + 0.5 to y(units) }, GrogColors.grog, dot = 5.dp)),
            leftTicks = generateSequence(0) { it + 2 }.takeWhile { it <= top }.map { it.toDouble() to it.toString() }.toList(),
            rightTicks = generateSequence(0) { it + step }.takeWhile { it <= most }.map { y(it.toDouble()) to it.toString() }.toList(),
            rightColor = MaterialTheme.colorScheme.onSurfaceVariant,
            slots = days.map { day ->
                val sleep = nights[day]?.sleep
                val parts = listOfNotNull(
                    "Night of ${DateText.format(day, "EEEEdMMMM")}",
                    sleep?.let { s -> SleepStageBar.entries.joinToString(", ") { "${it.label} ${duration(it.seconds(s))}" } } ?: "no sleep recorded",
                    if (ledger.isLogged(day)) "drank ${ledger.totals(day).units.unitsText} units" else null,
                )
                PlotSlot(day.number.toDouble(), day.number + 1.0, parts.joinToString(", "))
            },
            xAxis = XAxis.Days(every = 3),
        )
        TimeChart(plot, window, height = 200.dp)
        LegendRow(spacing = 12.dp) {
            for (stage in SleepStageBar.entries) LegendKey(stage.label, stage.color, bar = true)
            LegendKey("Drank", GrogColors.grog)
        }
    }
}
