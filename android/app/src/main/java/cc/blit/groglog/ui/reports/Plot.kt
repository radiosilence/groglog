package cc.blit.groglog.ui.reports

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.ScrollAxisRange
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.horizontalScrollAxisRange
import androidx.compose.ui.semantics.scrollBy
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DayKey
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.roundToInt

/** A bar centred on `x`, `width` days wide, stacked from the baseline in the order given. */
@Immutable
data class PlotBar(
    val x: Double,
    val width: Double,
    val stack: List<Pair<Double, Color>>,
    /** Drawn above the bar where colour alone should not carry its meaning. */
    val mark: String? = null,
    /** Fades the colour towards the top, as iOS's `.gradient` does. */
    val shaded: Boolean = false,
)

/** A line through points in days and the chart's units, with dots at each where `dot` is set. */
@Immutable
data class PlotLine(
    val points: List<Pair<Double, Double>>,
    val color: Color,
    val width: Dp = 2.dp,
    val dash: List<Dp>? = null,
    val dot: Dp? = null,
    /** Fills down to the baseline, fading as it goes. */
    val fill: Color? = null,
    /** Steps across each point's width rather than joining the points. */
    val step: Double? = null,
)

@Immutable
data class PlotDot(val x: Double, val y: Double, val color: Color, val size: Dp)

/** A stretch of the axis TalkBack reads as one item. */
@Immutable
data class PlotSlot(val from: Double, val to: Double, val description: String)

/**
 * Everything a chart draws, as plain values, so a chart is redrawn only when one of them changes. x is in days (or
 * any unit the chart's ticks agree on); y is in the left axis's units, with any trailing axis mapped into them.
 */
@Immutable
data class Plot(
    val from: Double,
    val to: Double,
    val top: Double,
    val bars: List<PlotBar> = emptyList(),
    val lines: List<PlotLine> = emptyList(),
    val dots: List<PlotDot> = emptyList(),
    /** Dashed vertical rules, such as now. */
    val rules: List<Double> = emptyList(),
    /** A dashed horizontal rule with a caption, such as the weekly guideline. */
    val guide: Pair<Double, String>? = null,
    val leftTicks: List<Pair<Double, String>> = niceTicks(top).map { it to it.tickText() },
    val rightTicks: List<Pair<Double, String>> = emptyList(),
    val rightColor: Color = Color.Unspecified,
    val xGrid: Boolean = true,
    /** Labels under the axis, centred on their x rather than starting at it. */
    val xCentred: Boolean = false,
    val slots: List<PlotSlot> = emptyList(),
    val xAxis: XAxis,
)

/** Where the labels under a chart go. x is days since 1970 for the date axes. */
sealed interface XAxis {
    fun ticks(left: Double, span: Double): List<Pair<Double, String>>

    /** At midnight every `every` days, or with a fifth of the window between them. */
    data class Days(val every: Int? = null) : XAxis {
        override fun ticks(left: Double, span: Double): List<Pair<Double, String>> {
            val stride = every ?: max(1, (span / 5).toInt())
            val first = Math.floorDiv(floor(left).toInt(), stride) * stride
            return (first..ceil(left + span).toInt() step stride).map { it.toDouble() to DateText.format(DayKey(it), "dMMM") }
        }
    }

    /** At the first of each month. */
    data object Months : XAxis {
        override fun ticks(left: Double, span: Double): List<Pair<Double, String>> {
            var month = DayKey(floor(left).toInt()).monthStart
            val ticks = mutableListOf<Pair<Double, String>>()
            while (month.number <= left + span) {
                ticks += month.number.toDouble() to DateText.format(month, "MMM")
                month += month.daysInMonth
            }
            return ticks
        }
    }

    data class Fixed(val ticks: List<Pair<Double, String>>) : XAxis {
        override fun ticks(left: Double, span: Double) = ticks
    }
}

/** The day under a held finger, read out above the chart. */
@Immutable
data class Readout(val x: Double, val title: String, val lines: List<String>)

/**
 * A chart drawn on a Canvas. It shows `window` of the plot, scrolls when the plot is wider than that, pinches where
 * `zoomable`, and reads out a point while held where `onSelect` is given. TalkBack reads each slot in view as an
 * item and can scroll the chart.
 */
@Composable
fun TimeChart(
    plot: Plot,
    window: ChartWindow?,
    height: Dp,
    modifier: Modifier = Modifier,
    zoomable: Boolean = false,
    readout: Readout? = null,
    onSelect: ((Double?) -> Unit)? = null,
) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val axisStyle = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant)
    val grid = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)
    val ruleColour = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
    val leftWidth = remember(plot.leftTicks, axisStyle) {
        (plot.leftTicks.maxOfOrNull { measurer.width(it.second, axisStyle) } ?: 0f) + with(density) { 6.dp.toPx() }
    }
    val rightWidth = remember(plot.rightTicks, axisStyle) {
        if (plot.rightTicks.isEmpty()) 0f else (plot.rightTicks.maxOf { measurer.width(it.second, axisStyle) } + with(density) { 6.dp.toPx() })
    }
    val labelHeight = remember(axisStyle) { measurer.measure("8", axisStyle).size.height + with(density) { 4.dp.toPx() } }
    val topInset = with(density) { 14.dp.toPx() }
    var widthPx by remember { mutableFloatStateOf(1f) }
    val plotArea = { leftWidth to max(1f, widthPx - leftWidth - rightWidth) }
    val current by rememberUpdatedState(plot)
    val select by rememberUpdatedState(onSelect)
    val scope = rememberCoroutineScope()

    val span = window?.span(plot.from, plot.to) ?: (plot.to - plot.from)
    val left = window?.left(plot.from, plot.to) ?: plot.from

    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .onSizeChanged { widthPx = it.width.toFloat() }
            .then(
                if (window == null) {
                    Modifier
                } else {
                    Modifier
                        .pointerInput(window, zoomable, onSelect != null) {
                            chartGestures(window, { current.from to current.to }, plotArea, zoomable, scope, if (onSelect != null) { x -> select?.invoke(x) } else null)
                        }
                        .semantics {
                            horizontalScrollAxisRange = ScrollAxisRange(
                                value = { (window.left(current.from, current.to) - current.from).toFloat() },
                                maxValue = { max(0.0, current.to - current.from - window.span(current.from, current.to)).toFloat() },
                            )
                            scrollBy { x, _ ->
                                window.scroll(x / plotArea().second * window.span(current.from, current.to), current.from, current.to)
                                true
                            }
                        }
                },
            ),
    ) {
        Canvas(Modifier.fillMaxSize().clearAndSetSemantics {}) {
            val area = Rect(leftWidth, topInset, size.width - rightWidth, size.height - labelHeight)
            fun px(x: Double) = (area.left + (x - left) / span * area.width).toFloat()
            fun py(y: Double) = (area.bottom - y / plot.top * area.height).toFloat()
            val dayPx = area.width / span

            for ((value, text) in plot.leftTicks) {
                val y = py(value)
                drawLine(grid, Offset(area.left, y), Offset(area.right, y), strokeWidth = 1.dp.toPx())
                label(measurer, text, axisStyle, Offset(area.left - 4.dp.toPx(), y), alignX = 1f)
            }
            for ((value, text) in plot.rightTicks) {
                label(measurer, text, axisStyle.copy(color = plot.rightColor), Offset(area.right + 4.dp.toPx(), py(value)))
            }
            // A label that would run into the one before is left out, which large text makes common.
            var labelled = Float.NEGATIVE_INFINITY
            for ((x, text) in plot.xAxis.ticks(left, span)) {
                val at = px(x)
                if (at < area.left - 1 || at > area.right + 1) continue
                if (plot.xGrid) drawLine(grid, Offset(at, area.top), Offset(at, area.bottom), strokeWidth = 1.dp.toPx())
                val width = measurer.width(text, axisStyle)
                val start = if (plot.xCentred) at - width / 2 else at + 2.dp.toPx()
                if (start < labelled + 4.dp.toPx() || start + width > size.width) continue
                label(measurer, text, axisStyle, Offset(start, area.bottom + 2.dp.toPx()), alignY = 0f)
                labelled = start + width
            }

            clipRect(area.left, 0f, area.right, area.bottom) {
                for (bar in plot.bars) {
                    val centre = px(bar.x)
                    val width = max(2.dp.toPx(), (bar.width * dayPx).toFloat())
                    if (centre + width < area.left || centre - width > area.right) continue
                    var base = 0.0
                    val total = bar.stack.sumOf { it.first }
                    for ((index, segment) in bar.stack.withIndex()) {
                        val (height, colour) = segment
                        // Only the stack's ends are rounded.
                        val radius = if (bar.stack.size == 1 || index == bar.stack.lastIndex) 3.dp else 0.dp
                        if (bar.shaded) {
                            val path = Path()
                            val rect = Rect(centre - width / 2, py(base + height), centre + width / 2, py(base))
                            path.addRoundRect(androidx.compose.ui.geometry.RoundRect(rect, androidx.compose.ui.geometry.CornerRadius(4.dp.toPx())))
                            drawPath(path, Brush.verticalGradient(listOf(colour.copy(alpha = colour.alpha * 0.75f), colour), startY = rect.top, endY = rect.bottom))
                        } else {
                            bar(centre, width, py(base + height), py(base), colour, radius)
                        }
                        base += height
                    }
                    bar.mark?.let { mark ->
                        label(
                            measurer,
                            mark,
                            axisStyle.copy(color = bar.stack.last().second.copy(alpha = 1f), fontWeight = FontWeight.Bold),
                            Offset(centre, py(total) - 2.dp.toPx()),
                            alignX = 0.5f,
                            alignY = 1f,
                        )
                    }
                }
                plot.guide?.let { (value, caption) ->
                    val y = py(value)
                    drawLine(ruleColour.copy(alpha = 0.6f), Offset(area.left, y), Offset(area.right, y), strokeWidth = 1.dp.toPx(), pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())))
                    label(measurer, caption, axisStyle, Offset(area.right - 2.dp.toPx(), y - 2.dp.toPx()), alignX = 1f, alignY = 1f)
                }
                for (line in plot.lines) {
                    val points = if (line.step != null) {
                        line.points.flatMap { (x, y) -> listOf(Offset(px(x - line.step / 2), py(y)), Offset(px(x + line.step / 2), py(y))) }
                    } else {
                        line.points.map { (x, y) -> Offset(px(x), py(y)) }
                    }
                    line.fill?.let { fill ->
                        if (points.size >= 2) {
                            val area = Path().apply {
                                moveTo(points.first().x, py(0.0))
                                for (point in points) lineTo(point.x, point.y)
                                lineTo(points.last().x, py(0.0))
                                close()
                            }
                            drawPath(area, Brush.verticalGradient(listOf(fill, fill.copy(alpha = 0.02f)), startY = points.minOf { it.y }, endY = py(0.0)))
                        }
                    }
                    polyline(points, line.color, line.width, line.dash)
                    line.dot?.let { dot -> for (point in points) drawCircle(line.color, dot.toPx() / 2, point) }
                }
                for (dot in plot.dots) drawCircle(dot.color, dot.size.toPx() / 2, Offset(px(dot.x), py(dot.y)))
                for (x in plot.rules) verticalRule(px(x), area.top, area.bottom, ruleColour)
                readout?.let { verticalRule(px(it.x), area.top, area.bottom, ruleColour.copy(alpha = 0.5f), width = 1.dp, dash = false) }
            }
        }

        // TalkBack's items: one per slot in view, laid over the stretch of the axis it describes.
        Layout(
            content = {
                for (slot in plot.slots) {
                    Box(Modifier.semantics { contentDescription = slot.description })
                }
            },
            modifier = Modifier.fillMaxSize(),
        ) { measurables, constraints ->
            val area = constraints.maxWidth - leftWidth - rightWidth
            val placeables = measurables.mapIndexed { index, measurable ->
                val slot = plot.slots[index]
                val start = leftWidth + ((slot.from - left) / span * area).toFloat()
                val end = leftWidth + ((slot.to - left) / span * area).toFloat()
                val visible = end > leftWidth && start < leftWidth + area
                val width = if (visible) max(1, (end - start).roundToInt()) else 0
                Triple(measurable.measure(androidx.compose.ui.unit.Constraints.fixed(width, if (visible) constraints.maxHeight else 0)), start, visible)
            }
            layout(constraints.maxWidth, constraints.maxHeight) {
                for ((placeable, start, visible) in placeables) if (visible) placeable.place(start.roundToInt(), 0)
            }
        }

        readout?.let { ReadoutBubble(it, x = leftWidth + ((it.x - left) / span * plotArea().second).toFloat()) }
    }
}

/** The held day's figures, above the chart at the finger's x, kept inside the chart's edges. */
@Composable
private fun ReadoutBubble(readout: Readout, x: Float) {
    Layout(
        content = {
            Surface(
                shape = RoundedCornerShape(10.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.95f),
                shadowElevation = 2.dp,
            ) {
                Column(Modifier.padding(8.dp)) {
                    Text(readout.title, style = MaterialTheme.typography.labelLarge)
                    for (line in readout.lines) {
                        Text(line, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        },
        modifier = Modifier.fillMaxSize().clearAndSetSemantics {},
    ) { measurables, constraints ->
        val bubble = measurables[0].measure(constraints.copy(minWidth = 0, minHeight = 0))
        layout(constraints.maxWidth, constraints.maxHeight) {
            bubble.place((x - bubble.width / 2).roundToInt().coerceIn(0, max(0, constraints.maxWidth - bubble.width)), 0)
        }
    }
}
