package cc.blit.groglog.ui.reports

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Nights
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.HeatBand
import java.time.Instant
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/** A day's drinking as a bar over its own noon. */
@Immutable
data class DayBar(val day: DayKey, val units: Double, val partial: Boolean, val budget: Double?) {
    val x: Double get() = day.number + 0.5
    val band: HeatBand get() = HeatBand.of(units, budget)

    val spoken: String
        get() {
            val drank = "${units.unitsText} units${if (partial) " so far" else ""}"
            return if (budget == null) drank else "$drank, budget ${budget.unitsText}, ${band.spoken}"
        }
}

/**
 * Everything a progress chart shows, worked out from the log: what was drunk each day as bars, the daily budget as a
 * line that runs on from now as the dashed plan, and the heart readings. Nothing here is averaged except the heart
 * readings of a monthly chart.
 */
@Immutable
data class Progress(
    val start: DayKey,
    val today: DayKey,
    val now: Double,
    val bars: List<DayBar>,
    val behind: List<Pair<Double, Double>>,
    val ahead: List<Pair<Double, Double>>,
    val hearts: List<HeartPoint>,
    val budgets: Map<DayKey, Double>,
) {
    /** Scaled to the last `days` days, so an old binge does not flatten the recent weeks. */
    fun top(days: Double): Double {
        val shown = bars.filter { it.day >= today - days.roundToInt() }
        return maxOf(10.0, bars.lastOrNull { it.day == today }?.units ?: 0.0, shown.maxOfOrNull { it.units } ?: 0.0, ahead.maxOfOrNull { it.second } ?: 0.0) * 1.15
    }

    companion object {
        /**
         * `history` is as far back as the chart scrolls, from the log's own history only: older heart readings come in
         * from the left edge on a dash, and widening the chart to reach them would leave months of it empty.
         */
        fun of(ledger: Ledger, goal: Goal, nights: Nights, heart: HeartLines, history: Int, now: Instant): Progress {
            val clock = ledger.clock
            val today = ledger.today
            val start = minOf(maxOf(ledger.firstDay ?: (today - 27), today - history), today)
            // To the minute, so the chart reads the same from one commit to the next.
            val wall = now.atZone(clock.zone)
            val x = DayKey.of(now, clock.zone).number + (wall.toLocalTime().toSecondOfDay() / 60) / 1440.0
            val budgets = (start..(today + 14)).mapNotNull { day -> ledger.dailyBudget(day, goal)?.let { day to it } }.toMap()
            val bars = (start..today).mapNotNull { day ->
                when {
                    day == today -> DayBar(day, ledger.totals(day).units, partial = true, budget = budgets[day])
                    ledger.isLogged(day) -> DayBar(day, ledger.totals(day).units, partial = false, budget = budgets[day])
                    else -> null
                }
            }
            // Every day's budget sits at its own noon, so each day's cut spans the same width. Placing today's point on
            // the now rule would stretch the segment before it and squash the one after, so the line would kink at
            // today; the rule is met by a point interpolated along the line instead.
            val curve = budgets.map { (day, units) -> day.number + 0.5 to units }.sortedBy { it.first }
            val ruleDay = if (x >= today.number + 0.5) today else today - 1
            val onTheRule = ledger.dailyBudget(ruleDay, goal)?.let { here ->
                ledger.dailyBudget(ruleDay + 1, goal)?.let { next -> x to here + (next - here) * (x - (ruleDay.number + 0.5)) }
            }
            val nightsShown = (start..(today - 1)).toList()
            val noon = { day: DayKey -> day.number + 0.5 }
            val hearts = when (heart) {
                HeartLines.NIGHTLY -> HeartReading.entries.flatMap { reading ->
                    HeartPoint.line(reading, nightsShown, nights.last(reading.value, start), noon) { nights[it]?.let(reading.value) }
                }
                // The anchor is averaged the same way, so a lone old reading with no week around it is not used.
                HeartLines.AVERAGED -> listOf(HeartReading.HRV, HeartReading.RESTING).flatMap { reading ->
                    HeartPoint.line(reading, nightsShown, nights.last(reading.value, start), noon) { nights.mean(reading.value, (it - 6)..it) }
                }
            }
            return Progress(
                start = start,
                today = today,
                now = x,
                bars = bars,
                behind = curve.filter { it.first <= x } + listOfNotNull(onTheRule),
                ahead = listOfNotNull(onTheRule) + curve.filter { it.first > x },
                hearts = hearts,
                budgets = budgets,
            )
        }
    }
}

/** What the held day was, read from the log rather than off the bars, so a dry day and a day never logged say which. */
fun readout(ledger: Ledger, goal: Goal, x: Double): Readout {
    val day = DayKey(kotlin.math.floor(x).toInt())
    val today = ledger.today
    val units = ledger.totals(day).units
    val budget = ledger.dailyBudget(day, goal)
    val drank = when (ledger.status(day)) {
        DayStatus.DRANK -> "${units.unitsText} u${if (day == today) " so far" else ""}${budget?.let { ", ${HeatBand.of(units, it).spoken}" } ?: ""}"
        DayStatus.ALCOHOL_FREE -> "Dry"
        DayStatus.TODAY -> "Nothing yet"
        DayStatus.UNLOGGED, DayStatus.UNTRACKED -> "Not logged"
        DayStatus.FUTURE -> null
    }
    val limit = budget?.let { "${if (day > today) "Plan" else "Budget"} ${it.unitsText} u" }
    return Readout(day.number + 0.5, DateText.format(day, "EEEdMMM"), listOfNotNull(drank, limit))
}

/**
 * Weekly or monthly progress: daily units as bars against the budget, the fortnight ahead as the plan, and the heart
 * readings. Scrolls back `history` days and pinches between four days and all of them.
 */
@Composable
fun ProgressCard(
    title: String,
    days: Double,
    history: Int,
    ledger: Ledger,
    goal: Goal,
    nights: Nights,
    heart: HeartLines,
    shownHeart: HeartReading,
    onShowHeart: (HeartReading) -> Unit,
    onSetGoal: () -> Unit,
) {
    val now = minuteClock()
    val progress = remember(ledger, goal, nights, heart, now) { Progress.of(ledger, goal, nights, heart, history, now) }
    val today = progress.today
    val window = rememberChartWindow(span = days, left = (today - (days.roundToInt() - 4)).number.toDouble(), minSpan = 4.0, maxSpan = history.toDouble())
    var selected by remember { mutableStateOf<Double?>(null) }
    val differentiate = differentiatesWithoutColour()

    ReportCard(title) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            val style = MaterialTheme.typography.bodyMedium
            val secondary = MaterialTheme.colorScheme.onSurfaceVariant
            ledger.dailyBudget(today, goal)?.let { todays ->
                Text("Today's budget ${todays.unitsText} u", style = style, color = secondary)
                ledger.projection(goal).stoppable?.let { stop ->
                    Text(
                        if (stop <= today) "Already low enough to stop" else "Low enough to stop by ${DateText.format(stop, "dMMMyyyy")} at this rate",
                        style = style,
                        color = GrogColors.dry,
                    )
                }
            }
            for (line in heartSummary(nights, heart, today - 1)) Text(line, style = style, color = secondary)
        }

        val from = progress.start.number.toDouble()
        val to = (today + 15).number.toDouble()
        val span = window.span(from, to)
        val top = progress.top(span)
        val drawn = HeartPoint.drawn(shownHeart, progress.hearts)
        val heartPoints = progress.hearts.filter { it.reading == drawn }
        val scale = HeartScale.of(heartPoints, top)
        val plot = Plot(
            from = from,
            to = to,
            top = top,
            // Today's bar is faded: the day is not over, so the bar is not at its final height.
            bars = progress.bars.map { bar ->
                val heat = GrogColors.heat(bar.units, bar.budget)
                PlotBar(bar.x, 0.62, listOf(bar.units to heat.copy(alpha = if (bar.partial) 0.45f else 1f)), mark = if (differentiate) bar.band.mark else null)
            },
            lines = listOf(
                PlotLine(progress.behind, GrogColors.dry),
                PlotLine(progress.ahead, GrogColors.dry, dash = listOf(4.dp, 4.dp)),
            ) + heartLines(heartPoints, scale, dots = heart == HeartLines.NIGHTLY),
            dots = heartDots(heartPoints, scale, dots = heart == HeartLines.NIGHTLY, size = 6.dp),
            rules = listOf(progress.now),
            rightTicks = scale?.ticks?.map { it.first to it.second.toString() }.orEmpty(),
            rightColor = scale?.color ?: androidx.compose.ui.graphics.Color.Unspecified,
            slots = (progress.start..(today + 14)).map { day ->
                PlotSlot(day.number.toDouble(), day.number + 1.0, spokenDay(day, progress, heartPoints))
            },
            xAxis = XAxis.Days(),
        )
        TimeChart(
            plot,
            window,
            height = 220.dp,
            zoomable = true,
            readout = selected?.let { readout(ledger, goal, it) },
            onSelect = { selected = it },
        )

        LegendRow {
            LegendKey("Drank", GrogColors.grog, bar = true, ramp = listOf(GrogColors.dry, GrogColors.grog, GrogColors.over))
            if (goal.isEnabled) {
                LegendKey("Budget", GrogColors.dry)
                LegendKey("Plan", GrogColors.dry, dashed = true)
            }
        }
        HeartChips(progress.hearts, if (heart == HeartLines.NIGHTLY) "" else ", 7-night", shownHeart, onShowHeart)
        if (!goal.isEnabled) {
            TextButton(onClick = onSetGoal) {
                Icon(ReportIcons.target, contentDescription = null)
                Text("Set a goal to see your budget come down", modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}

/** One day for TalkBack: what was drunk, the budget or plan, and the heart reading drawn. */
private fun spokenDay(day: DayKey, progress: Progress, hearts: List<HeartPoint>): String {
    val parts = mutableListOf(DateText.format(day, "EEEEdMMMM"))
    val bar = progress.bars.firstOrNull { it.day == day }
    when {
        bar != null -> parts += bar.spoken
        day > progress.today -> progress.budgets[day]?.let { parts += "plan ${it.unitsText} units" }
        else -> parts += "not logged"
    }
    hearts.firstOrNull { !it.bridge && it.x == day.number + 0.5 }?.let { parts += "${it.reading.label} ${it.value.roundToInt()} ${it.reading.unit}" }
    return parts.joinToString(", ")
}

/** Each run of readings as a line, and the dashed bridges across the gaps. */
fun heartLines(points: List<HeartPoint>, scale: HeartScale?, dots: Boolean, width: (HeartPoint) -> androidx.compose.ui.unit.Dp = { 2.dp }): List<PlotLine> {
    scale ?: return emptyList()
    return points.groupBy { Triple(it.run, it.bridge, it.reading) }.map { (key, run) ->
        val bridge = key.second
        val reading = key.third
        PlotLine(
            run.map { it.x to scale.y(it.value) },
            reading.color.copy(alpha = if (bridge) 0.6f else 1f),
            width = if (bridge) width(run[0]) * 0.75f else width(run[0]),
            dash = if (bridge) listOf(3.dp, 4.dp) else null,
        )
    }
}

/** Dots on every reading of a nightly line, and on any reading too alone to have a line. */
fun heartDots(points: List<HeartPoint>, scale: HeartScale?, dots: Boolean, size: androidx.compose.ui.unit.Dp): List<PlotDot> {
    scale ?: return emptyList()
    return points.filter { !it.bridge && (dots || it.alone) }.map { PlotDot(it.x, scale.y(it.value), it.reading.color, size) }
}

/** Last night against the week before it, to show the effect of one evening; or, averaged, the last week. */
fun heartSummary(nights: Nights, heart: HeartLines, lastNight: DayKey): List<AnnotatedString> {
    val week = (lastNight - 7)..(lastNight - 1)
    return when (heart) {
        HeartLines.NIGHTLY -> HeartReading.entries.mapNotNull { reading ->
            val value = nights[lastNight]?.let(reading.value) ?: return@mapNotNull null
            val change = nights.mean(reading.value, week)?.let { value - it } ?: 0.0
            buildAnnotatedString {
                append("${reading.short} last night ${value.roundToInt()} ${reading.unit}")
                if (abs(change) >= 1) {
                    withStyle(SpanStyle(color = if (reading.isWorse(change)) GrogColors.over else GrogColors.dry)) {
                        append(", ${abs(change).roundToInt()} ${if (change < 0) "under" else "over"} the week before")
                    }
                }
            }
        }
        HeartLines.AVERAGED -> {
            val hrv = nights.mean({ it.hrv }, (lastNight - 6)..lastNight)
            val resting = nights.mean({ it.restingHR }, (lastNight - 6)..lastNight)
            if (hrv == null && resting == null) {
                emptyList()
            } else {
                listOf(AnnotatedString(listOfNotNull(hrv?.let { "HRV ${it.roundToInt()} ms" }, resting?.let { "RHR ${it.roundToInt()} bpm" }).joinToString(" · ") + " over the last week"))
            }
        }
    }
}

/** The time to the minute, moving on each minute, for the now rule. */
@Composable
fun minuteClock(): Instant {
    var now by remember { mutableStateOf(Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MINUTES)) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000 - System.currentTimeMillis() % 60_000)
            now = Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MINUTES)
        }
    }
    return now
}
