package cc.blit.groglog.ui.reports

import android.text.format.DateFormat
import androidx.compose.animation.core.AnimationState
import androidx.compose.animation.core.animateDecay
import androidx.compose.animation.core.exponentialDecay
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DayKey
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** A card on the Reports page: a title, then its content. */
@Composable
fun ReportCard(title: String?, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (title != null) {
                Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            }
            content()
        }
    }
}

/**
 * What part of a time axis a chart shows: `left` and `span` in days. A chart scrolls and, where `zoomable`, pinches
 * within `from` to `to`, which can grow as data arrives, so they are applied when read rather than stored.
 */
@Stable
class ChartWindow(span: Double, left: Double, val minSpan: Double, val maxSpan: Double) {
    var span by mutableDoubleStateOf(span)
        private set
    private var rawLeft by mutableDoubleStateOf(left)

    fun span(from: Double, to: Double) = span.coerceIn(min(minSpan, to - from), max(min(maxSpan, to - from), 0.0))

    fun left(from: Double, to: Double) = rawLeft.coerceIn(from, max(from, to - span(from, to)))

    fun scroll(days: Double, from: Double, to: Double) {
        rawLeft = left(from, to) + days
        rawLeft = left(from, to)
    }

    /** Keeps the day under `anchor` (0 at the left edge, 1 at the right) where it is. */
    fun zoom(factor: Double, anchor: Double, from: Double, to: Double) {
        val before = span(from, to)
        val x = left(from, to) + anchor * before
        span = (before / factor).coerceIn(minSpan, maxSpan)
        rawLeft = x - anchor * span(from, to)
        rawLeft = left(from, to)
    }

    fun reset(span: Double, left: Double) {
        this.span = span
        rawLeft = left
    }
}

@Composable
fun rememberChartWindow(span: Double, left: Double, minSpan: Double = span, maxSpan: Double = span) =
    remember { ChartWindow(span, left, minSpan, maxSpan) }

private enum class Gesture { UNDECIDED, PAN, ZOOM, SELECT }

/**
 * Scrolling, pinching and reading out a chart. A horizontal drag scrolls and flings, a vertical one is left to the
 * page, two fingers pinch where the chart allows it, and holding still then dragging reads out the point under the
 * finger until it lifts. `plot` gives the plot area's left edge and width in pixels.
 */
suspend fun PointerInputScope.chartGestures(
    window: ChartWindow,
    bounds: () -> Pair<Double, Double>,
    plot: () -> Pair<Float, Float>,
    zoomable: Boolean,
    scope: CoroutineScope,
    onSelect: ((Double?) -> Unit)?,
) {
    var fling: Job? = null
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        fling?.cancel()
        val slop = viewConfiguration.touchSlop
        val tracker = VelocityTracker()
        tracker.addPosition(down.uptimeMillis, down.position)
        var gesture = Gesture.UNDECIDED
        var travelled = Offset.Zero
        val pressAt = down.uptimeMillis
        fun daysPerPx(): Double {
            val (from, to) = bounds()
            return window.span(from, to) / plot().second
        }
        fun x(position: Offset): Double {
            val (from, to) = bounds()
            val (left, width) = plot()
            return window.left(from, to) + (position.x - left) / width * window.span(from, to)
        }
        while (true) {
            val event = if (gesture == Gesture.UNDECIDED && onSelect != null) {
                val wait = viewConfiguration.longPressTimeoutMillis - (currentEvent.changes.firstOrNull()?.uptimeMillis?.minus(pressAt) ?: 0)
                withTimeoutOrNull(max(1L, wait)) { awaitPointerEvent() }
            } else {
                awaitPointerEvent()
            }
            if (event == null) {
                gesture = Gesture.SELECT
                onSelect?.invoke(x(down.position))
                continue
            }
            val pressed = event.changes.filter { it.pressed }
            if (pressed.isEmpty()) break
            if (gesture == Gesture.UNDECIDED && event.changes.any { it.isConsumed }) return@awaitEachGesture
            if (pressed.size >= 2 && zoomable && gesture != Gesture.SELECT) gesture = Gesture.ZOOM
            val (from, to) = bounds()
            when (gesture) {
                Gesture.UNDECIDED -> {
                    travelled += pressed[0].positionChange()
                    if (travelled.getDistance() > slop) {
                        // Mostly up or down: the page is being scrolled, not the chart.
                        if (abs(travelled.y) > abs(travelled.x)) return@awaitEachGesture
                        gesture = Gesture.PAN
                    }
                }
                Gesture.PAN -> {
                    val change = pressed[0]
                    window.scroll(-change.positionChange().x * daysPerPx(), from, to)
                    tracker.addPosition(change.uptimeMillis, change.position)
                    change.consume()
                }
                Gesture.ZOOM -> {
                    val (left, width) = plot()
                    val anchor = ((event.calculateCentroid().x - left) / width).toDouble().coerceIn(0.0, 1.0)
                    window.zoom(event.calculateZoom().toDouble(), anchor, from, to)
                    window.scroll(-event.calculatePan().x * daysPerPx(), from, to)
                    event.changes.forEach { it.consume() }
                }
                Gesture.SELECT -> {
                    onSelect?.invoke(x(pressed[0].position))
                    pressed[0].consume()
                }
            }
        }
        if (gesture == Gesture.SELECT) onSelect?.invoke(null)
        if (gesture == Gesture.PAN) {
            val velocity = tracker.calculateVelocity().x
            fling = scope.launch {
                var last = 0f
                AnimationState(0f, velocity).animateDecay(exponentialDecay()) {
                    val (from, to) = bounds()
                    window.scroll(-(value - last) * daysPerPx(), from, to)
                    last = value
                }
            }
        }
    }
}

/** Gridline values from zero to `top` at a round step, about `count` of them, as charts space them. */
fun niceTicks(top: Double, count: Int = 5): List<Double> {
    if (top <= 0) return listOf(0.0)
    val rough = top / count
    val magnitude = 10.0.pow(floor(log10(rough)))
    val step = listOf(1.0, 2.0, 5.0, 10.0).map { it * magnitude }.first { it >= rough }
    return generateSequence(0.0) { it + step }.takeWhile { it <= top + 1e-9 }.toList()
}

fun Double.tickText(): String = if (this == floor(this)) toLong().toString() else String.format(Locale.getDefault(), "%.1f", this)

/** Dates as the reader's locale writes them, from a skeleton such as "dMMM". */
object DateText {
    private val cache = HashMap<String, DateTimeFormatter>()

    fun format(day: DayKey, skeleton: String): String =
        cache.getOrPut(skeleton + Locale.getDefault()) {
            DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(Locale.getDefault(), skeleton))
        }.format(day.localDate)
}

/** A polyline through `points`, solid or dashed. */
fun DrawScope.polyline(points: List<Offset>, color: Color, width: Dp, dash: List<Dp>? = null) {
    if (points.size < 2) return
    val path = Path().apply {
        moveTo(points[0].x, points[0].y)
        for (point in points.drop(1)) lineTo(point.x, point.y)
    }
    drawPath(
        path,
        color,
        style = Stroke(
            width = width.toPx(),
            cap = StrokeCap.Round,
            join = StrokeJoin.Round,
            pathEffect = dash?.let { PathEffect.dashPathEffect(it.map { d -> d.toPx() }.toFloatArray()) },
        ),
    )
}

fun DrawScope.verticalRule(x: Float, top: Float, bottom: Float, color: Color, width: Dp = 1.5.dp, dash: Boolean = true) {
    drawLine(
        color,
        Offset(x, top),
        Offset(x, bottom),
        strokeWidth = width.toPx(),
        pathEffect = if (dash) PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())) else null,
    )
}

/** A bar from the baseline up to `y`, rounded at the top as iOS's charts round them. */
fun DrawScope.bar(centre: Float, width: Float, y: Float, baseline: Float, color: Color, radius: Dp = 3.dp) {
    if (baseline - y < 0.5f) return
    val r = min(radius.toPx(), min(width / 2, (baseline - y) / 2))
    val path = Path().apply {
        addRoundRect(
            androidx.compose.ui.geometry.RoundRect(
                left = centre - width / 2,
                top = y,
                right = centre + width / 2,
                bottom = baseline,
                topLeftCornerRadius = CornerRadius(r),
                topRightCornerRadius = CornerRadius(r),
                bottomLeftCornerRadius = CornerRadius(r),
                bottomRightCornerRadius = CornerRadius(r),
            ),
        )
    }
    drawPath(path, color)
}

/** Text at a point, aligned by `alignX` and `alignY` (0 start or top, 0.5 centre, 1 end or bottom). */
fun DrawScope.label(measurer: TextMeasurer, text: String, style: TextStyle, at: Offset, alignX: Float = 0f, alignY: Float = 0.5f): TextLayoutResult {
    val layout = measurer.measure(text, style)
    drawText(layout, topLeft = Offset(at.x - layout.size.width * alignX, at.y - layout.size.height * alignY))
    return layout
}

/** Space for a chart's axis labels, measured from a sample so it grows with the text size. */
fun TextMeasurer.width(text: String, style: TextStyle) = measure(text, style).size.width.toFloat()
