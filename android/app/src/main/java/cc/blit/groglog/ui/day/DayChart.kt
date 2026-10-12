package cc.blit.groglog.ui.day

import android.text.format.DateFormat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.CurvePoint
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.HourCounter
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.time.Instant
import java.time.format.TextStyle as DateTextStyle
import java.util.Date
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

private val gray = Color(0xFF8E8E93)

@Immutable
internal data class ChartSeries(
    val name: String,
    val color: Color,
    val points: List<CurvePoint>,
    val dashed: Boolean = false,
    /** What the legend reads the value from, when that isn't the drawn line. */
    val figures: List<CurvePoint>? = null,
) {
    fun value(hour: Double): Double? {
        val points = figures ?: points
        if (points.isEmpty()) return null
        return points.lastOrNull { it.x <= hour }?.units ?: 0.0
    }
}

/** The chart as plain values, so it is drawn again only when one of them changes. */
@Immutable
internal data class DayChartModel(
    val series: List<ChartSeries>,
    val budget: Double?,
    /** Hours into the day now, when the day is today; null draws the whole day. */
    val nowHour: Double?,
    val from: Double,
    val ticks: List<Pair<Double, String>>,
) {
    val today: ChartSeries get() = series.first()
    val at: Double get() = nowHour ?: 24.0
    val top: Double get() = max(2.0, max(budget ?: 0.0, series.flatMap { it.points }.maxOfOrNull { it.units } ?: 0.0)) * 1.1

    val spoken: String
        get() = (series.mapNotNull { s -> s.value(at)?.let { "${s.name} ${it.unitsText} units" } } + listOfNotNull(budget?.let { "budget ${it.unitsText}" }))
            .joinToString(", ")
}

/**
 * Running units through `day`, against the two days before it and the average day of the week before. `entries` holds
 * the week before and the day itself, fetched once for the screen and the chart.
 */
internal fun dayChart(day: DayKey, ledger: Ledger, budget: Double?, entries: List<Entry>, now: Instant, locale: Locale = Locale.getDefault()): DayChartModel {
    val clock = ledger.clock
    val yesterday = day - 1
    val dayBefore = day - 2
    val nowHour = if (day == ledger.today) clock.hours(now, day) else null
    val hours = HourCounter(clock)
    val firstHour = entries
        .filter { it.day == day.number || it.day == yesterday.number || it.day == dayBefore.number }
        .minOfOrNull { hours.hours(it.timestamp, it.dayKey) }
    val from = floor(max(0.0, min(10.0, (firstHour ?: 10.0) - 1)))
    val week = ledger.weekBefore(day)
    val series = listOf(
        ChartSeries("Today", GrogColors.grog, ledger.cumulative(entries, day, from, nowHour ?: 24.0)),
        ChartSeries("Yesterday", gray.copy(alpha = 0.6f), if (ledger.isLogged(yesterday)) ledger.cumulative(entries, yesterday, from) else emptyList()),
        // Named by its weekday, which is easier to place than "two days ago".
        ChartSeries(
            dayBefore.localDate.dayOfWeek.getDisplayName(DateTextStyle.SHORT, locale),
            gray.copy(alpha = 0.25f),
            if (ledger.isLogged(dayBefore)) ledger.cumulative(entries, dayBefore, from) else emptyList(),
        ),
        // The line is smoothed; the figure in the legend is the real mean by that time.
        ChartSeries(
            "Week avg",
            GrogColors.dry,
            ledger.averageCumulative(entries, week, from),
            dashed = true,
            figures = ledger.averageCumulative(entries, week, from, smoothed = false),
        ),
    )
    val ticks = generateSequence(from) { it + 3 }.takeWhile { it <= 24 }.map { it to clock.hourLabel(it, locale) }.toList()
    return DayChartModel(series, budget, nowHour, from, ticks)
}

/** Whole, round steps for the units axis, no more than five of them. */
internal fun unitTicks(top: Double): List<Double> {
    val raw = max(1.0, top / 5)
    val magnitude = 10.0.pow(floor(log10(raw)))
    val step = listOf(1.0, 2.0, 5.0, 10.0).map { it * magnitude }.first { it >= raw }
    return (0..ceil(top / step).toInt()).map { it * step }.filter { it <= top }
}

@Composable
internal fun DayChart(model: DayChartModel, now: Instant, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val time = remember(now) { DateFormat.getTimeFormat(context).format(Date.from(now)) }
    val numbers = MaterialTheme.typography.titleSmall.copy(fontFeatureSettings = "tnum")
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(if (model.nowHour == null) "End of day" else "By $time", style = numbers, color = MaterialTheme.colorScheme.onSurfaceVariant)
            for (s in model.series) {
                val value = s.value(model.at) ?: continue
                Text(value.unitsText, style = numbers, color = s.color, fontWeight = if (s === model.today) FontWeight.Bold else FontWeight.Normal)
            }
        }
        DayPlot(model, Modifier.fillMaxWidth().height(200.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            for (s in model.series) {
                if (s.points.isNotEmpty()) LegendKey(s.name, s.color, s.dashed)
            }
        }
    }
}

@Composable
internal fun LegendKey(label: String, color: Color, dashed: Boolean = false) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Canvas(Modifier.width(18.dp).height(3.dp)) {
            drawLine(
                color, Offset(0f, size.height / 2), Offset(size.width, size.height / 2), size.height,
                StrokeCap.Round, if (dashed) PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 4.dp.toPx())) else null,
            )
        }
        Spacer(Modifier.width(6.dp))
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun DayPlot(model: DayChartModel, modifier: Modifier) {
    val measurer = rememberTextMeasurer()
    val label = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant, fontFeatureSettings = "tnum")
    val grid = MaterialTheme.colorScheme.outlineVariant
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val ticks = unitTicks(model.top)
    // The lines are running totals sampled every few minutes, which would read out as a list of fractions of an hour;
    // where each line stands now says more.
    Canvas(modifier.semantics {
        contentDescription = "Running total through the day"
        stateDescription = model.spoken
    }) {
        val axis = ticks.maxOf { measurer.measure(it.unitsText, label).size.width } + 6.dp.toPx()
        val bottom = measurer.measure("0", label).size.height + 4.dp.toPx()
        val plot = Rect(axis, 0f, size.width, size.height - bottom)
        fun x(hour: Double) = plot.left + ((hour - model.from) / (24 - model.from)).toFloat() * plot.width
        fun y(units: Double) = plot.bottom - (units / model.top).toFloat() * plot.height

        for (tick in ticks) {
            drawLine(grid, Offset(plot.left, y(tick)), Offset(plot.right, y(tick)), 0.5.dp.toPx())
            val text = measurer.measure(tick.unitsText, label)
            drawText(text, topLeft = Offset(0f, y(tick) - text.size.height / 2f))
        }
        // At large text sizes the hour labels outgrow their gaps, so any that would touch the one before are left out.
        var lastRight = Float.NEGATIVE_INFINITY
        for ((hour, name) in model.ticks) {
            drawLine(grid, Offset(x(hour), plot.top), Offset(x(hour), plot.bottom), 0.5.dp.toPx())
            val text = measurer.measure(name, label)
            val left = (x(hour) - text.size.width / 2f).coerceIn(plot.left, size.width - text.size.width)
            if (left < lastRight + 6.dp.toPx()) continue
            drawText(text, topLeft = Offset(left, plot.bottom + 4.dp.toPx()))
            lastRight = left + text.size.width
        }

        val today = model.today.points
        if (today.isNotEmpty()) {
            val area = steps(today, ::x, ::y).apply {
                lineTo(x(today.last().x), plot.bottom)
                lineTo(x(today.first().x), plot.bottom)
                close()
            }
            drawPath(area, Brush.verticalGradient(listOf(GrogColors.grog.copy(alpha = 0.35f), GrogColors.grog.copy(alpha = 0.02f)), plot.top, plot.bottom))
        }
        for (s in model.series.asReversed()) {
            if (s.points.isEmpty()) continue
            val path = if (s.dashed) linear(s.points, ::x, ::y) else steps(s.points, ::x, ::y)
            val width = if (s === model.today) 3.dp.toPx() else 2.dp.toPx()
            val dash = if (s.dashed) PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())) else null
            drawPath(path, s.color, style = Stroke(width, cap = StrokeCap.Round, join = StrokeJoin.Round, pathEffect = dash))
        }

        model.budget?.let { budget ->
            val at = y(budget)
            drawLine(GrogColors.over.copy(alpha = 0.7f), Offset(plot.left, at), Offset(plot.right, at), 1.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 3.dp.toPx())))
            val text = measurer.measure("budget", label.merge(TextStyle(color = GrogColors.over)))
            drawText(text, topLeft = Offset(plot.left + 2.dp.toPx(), at - text.size.height - 1.dp.toPx()))
        }
        model.nowHour?.let { hour ->
            drawLine(secondary.copy(alpha = 0.7f), Offset(x(hour), plot.top), Offset(x(hour), plot.bottom), 1.5.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())))
        }
    }
}

/** A running total holds its value until the next drink, then steps up. */
private fun DrawScope.steps(points: List<CurvePoint>, x: (Double) -> Float, y: (Double) -> Float) = Path().apply {
    moveTo(x(points.first().x), y(points.first().units))
    for ((previous, point) in points.zipWithNext()) {
        lineTo(x(point.x), y(previous.units))
        lineTo(x(point.x), y(point.units))
    }
}

private fun DrawScope.linear(points: List<CurvePoint>, x: (Double) -> Float, y: (Double) -> Float) = Path().apply {
    moveTo(x(points.first().x), y(points.first().units))
    for (point in points.drop(1)) lineTo(x(point.x), y(point.units))
}

@Preview(showBackground = true)
@Composable
private fun DayChartPreview() {
    val model = DayChartModel(
        series = listOf(
            ChartSeries("Today", GrogColors.grog, listOf(CurvePoint(12.0, 0.0), CurvePoint(14.5, 2.8), CurvePoint(17.0, 5.6), CurvePoint(18.5, 5.6))),
            ChartSeries("Yesterday", gray.copy(alpha = 0.6f), listOf(CurvePoint(12.0, 0.0), CurvePoint(15.0, 2.3), CurvePoint(16.0, 4.6), CurvePoint(24.0, 4.6))),
            ChartSeries("Sat", gray.copy(alpha = 0.25f), emptyList()),
            ChartSeries("Week avg", GrogColors.dry, (0..48).map { CurvePoint(12 + it * 0.25, 3.5 * it / 48) }, dashed = true),
        ),
        budget = 4.0,
        nowHour = 18.5,
        from = 12.0,
        ticks = listOf(12.0 to "17", 15.0 to "20", 18.0 to "23", 21.0 to "02", 24.0 to "05"),
    )
    GrogLogTheme { DayChart(model, Instant.now()) }
}
