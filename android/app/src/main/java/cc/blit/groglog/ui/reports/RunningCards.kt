package cc.blit.groglog.ui.reports

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cc.blit.groglog.model.CurvePoint
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.theme.GrogColors
import java.time.Instant
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt
import cc.blit.groglog.ui.shared.LegendKey
import cc.blit.groglog.ui.shared.LegendRow

private val earlierGrey = Color.Gray

/** The big figure on the week and month cards, with how it compares to the period before at the same point. */
@Composable
private fun Headline(units: Double, change: Double?) {
    Row(verticalAlignment = Alignment.Bottom) {
        // Shrinks rather than wraps at the largest text sizes.
        BasicText(
            units.unitsText,
            style = MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface),
            maxLines = 1,
            autoSize = TextAutoSize.StepBased(minFontSize = 20.sp, maxFontSize = 40.sp),
            modifier = Modifier.alignByBaseline().weight(1f, fill = false),
        )
        Text("units", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.alignByBaseline().padding(start = 6.dp))
        Spacer(Modifier.weight(1f))
        change?.let {
            val down = it <= 0
            val tint = if (down) GrogColors.dry else GrogColors.over
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.alignByBaseline().clearAndSetSemantics { contentDescription = "${abs(it * 100).roundToInt()} per cent ${if (down) "down" else "up"}" },
            ) {
                Icon(if (down) ReportIcons.trendingDown else ReportIcons.trendingUp, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
                Text("${(it * 100).roundToInt()}%", style = MaterialTheme.typography.titleMedium, color = tint, modifier = Modifier.padding(start = 4.dp))
            }
        }
    }
}

/** This week's running total against the last few weeks, with the week's budget as a dashed line. */
@Composable
fun WeekCard(ledger: Ledger, goal: Goal, entries: List<Entry>) {
    val clock = ledger.clock
    val today = ledger.today
    val start = clock.weekStart(today)
    val into = start.distanceTo(today) + min(1.0, clock.hours(Instant.now(), today) / 24)
    val current = ledger.runningTotal(entries, start..(start + 6), until = into)
    val weeks = (1..3).map { ledger.runningTotal(entries, (start - 7 * it)..(start - 7 * it + 6)) }
    // A week with nothing logged has no line, and an earlier week does not stand in for it as "last week".
    val earlier = weeks.withIndex().filter { it.value.size > 1 }
    val budget = if (goal.isEnabled) ledger.weekBudgetCurve(start, goal) else emptyList()
    val lastWeek = if (weeks[0].size > 1) weeks[0].lastOrNull { it.x <= into }?.units else null
    val now = current.lastOrNull()?.units ?: 0.0

    ReportCard("This week") {
        Headline(now, lastWeek?.takeIf { it > 0 }?.let { (now - it) / it })
        lastWeek?.let {
            Text("Last week by now: ${it.unitsText} u", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val curve = { points: List<CurvePoint> -> points.map { it.x to it.units } }
        val top = maxOf(1.0, (weeks.flatten() + current + budget).maxOfOrNull { it.units } ?: 0.0) * 1.1
        val plot = Plot(
            from = 0.0,
            to = 7.0,
            top = top,
            lines = earlier.map { (index, week) ->
                // Faint, and fainter with age, as the earlier days are on the Day chart: context, not data to read.
                PlotLine(curve(week), earlierGrey.copy(alpha = listOf(0.4f, 0.25f, 0.15f)[min(index, 2)]), width = 1.5.dp)
            } + listOfNotNull(
                budget.takeIf { it.isNotEmpty() }?.let { PlotLine(curve(it), GrogColors.dry, dash = listOf(4.dp, 4.dp)) },
                PlotLine(curve(current), GrogColors.grog, width = 3.dp, fill = GrogColors.grog.copy(alpha = 0.3f)),
            ),
            dots = current.lastOrNull()?.let { listOf(PlotDot(it.x, it.units, GrogColors.grog, 10.dp)) }.orEmpty(),
            xAxis = XAxis.Fixed((0..6).map { it.toDouble() to DateText.format(start + it, "EEE") }),
        )
        val weekBudget = budget.lastOrNull()?.let { ", week's budget ${it.units.unitsText}" } ?: ""
        // The marks are points along a running total, which would read out one by one as fractions of a day.
        TimeChart(plot, window = null, height = 200.dp, modifier = Modifier.clearAndSetSemantics { contentDescription = "Running total this week, ${now.unitsText} units so far$weekBudget" })
        LegendRow {
            LegendKey("This week", GrogColors.grog)
            LegendKey("Earlier weeks", earlierGrey.copy(alpha = 0.4f))
            if (budget.isNotEmpty()) LegendKey("Budget", GrogColors.dry, dashed = true)
        }
    }
}

/** This month's running total against last month's. */
@Composable
fun MonthCard(ledger: Ledger, entries: List<Entry>) {
    val today = ledger.today
    val thisMonth = today.monthStart
    val lastMonth = (thisMonth - 1).monthStart
    val into = thisMonth.distanceTo(today) + min(1.0, ledger.clock.hours(Instant.now(), today) / 24)
    val current = ledger.runningTotal(entries, thisMonth..(thisMonth + thisMonth.daysInMonth - 1), until = into)
    val previous = ledger.runningTotal(entries, lastMonth..(thisMonth - 1))
    val dayOfMonth = today.components.day
    val lastAtSameDay = previous.lastOrNull { it.x <= dayOfMonth }?.units ?: 0.0
    val now = current.lastOrNull()?.units ?: 0.0
    // A month with nothing logged has no line. The comparison also needs a logged day by this point in it: days never
    // logged are a gap, and a zero would read as a dry start to the month.
    val hasLastMonth = previous.size > 1
    val comparable = hasLastMonth && (0 until min(dayOfMonth, lastMonth.daysInMonth)).any { ledger.isLogged(lastMonth + it) }

    ReportCard("This month") {
        Headline(now, if (comparable && lastAtSameDay > 0) (now - lastAtSameDay) / lastAtSameDay else null)
        if (comparable) {
            Text("Last month by day $dayOfMonth: ${lastAtSameDay.unitsText} u", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val shownPrevious = if (hasLastMonth) previous else emptyList()
        val top = maxOf(1.0, (shownPrevious + current).maxOfOrNull { it.units } ?: 0.0) * 1.1
        val plot = Plot(
            from = 0.0,
            to = 31.0,
            top = top,
            lines = listOf(
                PlotLine(shownPrevious.map { it.x to it.units }, earlierGrey.copy(alpha = 0.4f)),
                PlotLine(current.map { it.x to it.units }, GrogColors.grog, width = 3.dp, fill = GrogColors.grog.copy(alpha = 0.35f)),
            ),
            dots = current.lastOrNull()?.let { listOf(PlotDot(it.x, it.units, GrogColors.grog, 10.dp)) }.orEmpty(),
            rules = listOf(dayOfMonth.toDouble()),
            xAxis = XAxis.Fixed(listOf(1, 8, 15, 22, 29).map { it.toDouble() to it.toString() }),
        )
        val lastMonthTotal = if (hasLastMonth) ", last month ${(previous.lastOrNull()?.units ?: 0.0).unitsText}" else ""
        TimeChart(plot, window = null, height = 200.dp, modifier = Modifier.clearAndSetSemantics { contentDescription = "Running total this month, ${now.unitsText} units so far$lastMonthTotal" })
        LegendRow {
            LegendKey(DateText.format(thisMonth, "MMMM"), GrogColors.grog)
            if (hasLastMonth) LegendKey(DateText.format(lastMonth, "MMMM"), earlierGrey.copy(alpha = 0.4f))
        }
    }
}
