package cc.blit.groglog.ui.reports

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cc.blit.groglog.core.ReadingKind
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Night
import cc.blit.groglog.ui.theme.GrogColors
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max

/** Which heart readings a progress chart carries: each night as it came, or the week around it. */
enum class HeartLines { NIGHTLY, AVERAGED }

enum class HeartReading(val label: String, val short: String, val unit: String, val color: Color, val kind: ReadingKind, val value: (Night) -> Double?) {
    HRV("HRV", "HRV", "ms", GrogColors.hrv, ReadingKind.HRV, Night::hrv),
    RESTING("Resting HR", "RHR", "bpm", GrogColors.pulse, ReadingKind.RESTING_HR, Night::restingHR),
    SLEEPING("Asleep HR", "Asleep", "bpm", GrogColors.sleeping, ReadingKind.SLEEPING_HR, Night::sleepingHR);

    /** HRV falls after a heavy night; heart rate rises. */
    fun isWorse(change: Double) = if (this == HRV) change < 0 else change > 0
}

/**
 * A heart reading at `x`, in days on the chart's axis.
 *
 * `run` numbers a stretch of consecutive readings; a missing night starts a new one. `alone` is a reading with no
 * neighbour in its run, so there is no line to draw it with. `bridge` is one end of a dashed line across nights with no
 * reading, which joins what was measured either side of the gap and claims nothing about what is in it.
 */
data class HeartPoint(
    val x: Double,
    val value: Double,
    val reading: HeartReading,
    val run: Int,
    val alone: Boolean = false,
    val bridge: Boolean = false,
) {
    companion object {
        /**
         * The line through `days`, broken where a night has no reading and bridged across the break. `before` is the
         * last reading ahead of the first day, however old, so a line that went quiet before the chart begins still
         * comes in from the left rather than starting cold. Its end is cut to the first day, on the same slope.
         */
        fun line(reading: HeartReading, days: List<DayKey>, before: DayKey? = null, at: (DayKey) -> Double, value: (DayKey) -> Double?): List<HeartPoint> {
            var run = 0
            val measured = days.mapNotNull { day ->
                val v = value(day)
                if (v == null) {
                    run += 1
                    null
                } else {
                    HeartPoint(at(day), v, reading, run)
                }
            }
            val sizes = measured.groupingBy { it.run }.eachCount()
            val points = measured.map { it.copy(alone = sizes[it.run] == 1) }
            val anchor = before?.let { day ->
                val then = value(day) ?: return@let null
                val next = points.firstOrNull() ?: return@let null
                val edge = days.firstOrNull()?.let(at) ?: return@let null
                val from = at(day)
                HeartPoint(edge, then + (next.value - then) * (edge - from) / (next.x - from), reading, run = -1)
            }
            val ends = listOfNotNull(anchor) + points
            val bridges = ends.zipWithNext().withIndex().flatMap { (index, pair) ->
                if (pair.first.run == pair.second.run) {
                    emptyList()
                } else {
                    listOf(pair.first, pair.second).map { HeartPoint(it.x, it.value, reading, index, bridge = true) }
                }
            }
            return points + bridges
        }

        /** The chosen reading, or the first there is when the chosen one has no data in this chart. */
        fun drawn(shown: HeartReading, points: List<HeartPoint>): HeartReading? {
            val readings = points.map { it.reading }.toSet()
            return if (shown in readings) shown else HeartReading.entries.firstOrNull { it in readings }
        }
    }
}

/**
 * One heart reading laid over a units chart, fitted to its height with its own axis down the trailing edge, in the
 * reading's colour. One at a time: HRV in ms and heart rate in bpm on a shared scale left each a thin band.
 */
data class HeartScale(val low: Double, val high: Double, val top: Double, val color: Color) {
    fun y(value: Double) = top * (0.08 + 0.84 * (value - low) / (high - low))

    /** Tick positions in the chart's units, and the reading each stands for. */
    val ticks: List<Pair<Double, Int>>
        get() {
            val step = if (high - low > 60) 20.0 else 10.0
            val first = ceil(low / step) * step
            return generateSequence(first) { it + step }.takeWhile { it <= high }.map { y(it) to it.toInt() }.toList()
        }

    companion object {
        fun of(points: List<HeartPoint>, top: Double): HeartScale? {
            val reading = points.firstOrNull()?.reading ?: return null
            val lo = points.minOf { it.value }
            val hi = points.maxOf { it.value }
            val low = floor(lo / 5) * 5 - 5
            return HeartScale(low, max(low + 20, ceil(hi / 5) * 5 + 5), top, reading.color)
        }
    }
}

/**
 * The heart readings a chart has, as chips in each reading's colour that choose which one it draws, on their own row
 * below the drinking keys. The choice is shared by every chart.
 */
@Composable
fun HeartChips(points: List<HeartPoint>, suffix: String, shown: HeartReading, onShow: (HeartReading) -> Unit) {
    val drawn = HeartPoint.drawn(shown, points) ?: return
    val readings = HeartReading.entries.filter { reading -> points.any { it.reading == reading } }
    Row(
        Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        for (reading in readings) {
            val selected = reading == drawn
            FilterChip(
                selected = selected,
                onClick = { onShow(reading) },
                label = { Text("${reading.short}$suffix", fontWeight = if (selected) FontWeight.SemiBold else null) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = reading.color.copy(alpha = 0.18f),
                    selectedLabelColor = reading.color,
                ),
                border = FilterChipDefaults.filterChipBorder(
                    enabled = true,
                    selected = selected,
                    selectedBorderColor = reading.color,
                    selectedBorderWidth = 1.dp,
                ),
            )
        }
        Text(drawn.unit, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
    }
}
