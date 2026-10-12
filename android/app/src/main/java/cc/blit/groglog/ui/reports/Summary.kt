package cc.blit.groglog.ui.reports

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cc.blit.groglog.model.DayRange
import cc.blit.groglog.model.DayTotals
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.WeekStat
import cc.blit.groglog.model.kcalText
import cc.blit.groglog.model.money
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.theme.GrogColors
import java.time.DayOfWeek
import java.time.format.TextStyle
import java.util.Locale

/** Streaks, gaps, spend and calories over the weeks the weekly bars show. */
@Composable
fun SummaryTiles(ledger: Ledger, stats: List<WeekStat>, days: DayRange, currency: String) {
    val totals = stats.fold(DayTotals()) { sum, week -> sum + week.totals }
    val dry = stats.sumOf { it.dryDays }
    val unlogged = stats.sumOf { it.unloggedDays }
    // Complete weeks only: this one is still being drunk.
    val average = if (stats.size > 1) ledger.weeklyAverage(stats.first().start..(stats.last().start - 1)) else null
    val dryColour = GrogColors.dry
    val tiles = listOf(
        Tile("Average week", average?.let { "${it.unitsText} u" } ?: "—"),
        Tile("Dry streak", "${ledger.dryStreak()} days", "Best ${ledger.longestDryStreak(days)}", dryColour),
        Tile("Dry days", "$dry of ${days.count}", tint = dryColour),
        Tile("Not logged", "$unlogged days", if (unlogged > 0) "Fill these in from Calendar" else null),
        Tile("Spent", totals.cost.money(currency)),
        Tile("Calories", totals.kcal.kcalText, "≈ ${(totals.kcal / 250).toInt()} burgers"),
    )
    // One column at the largest text sizes, where two leave each figure too narrow to read.
    val columns = if (LocalDensity.current.fontScale >= 1.5f) 1 else 2
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for (row in tiles.chunked(columns)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (tile in row) TileView(tile, Modifier.weight(1f))
            }
        }
    }
}

private data class Tile(val title: String, val value: String, val detail: String? = null, val tint: Color = Color.Unspecified)

@Composable
private fun TileView(tile: Tile, modifier: Modifier) {
    Surface(modifier.heightIn(min = 88.dp), shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.padding(14.dp).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(tile.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            BasicText(
                tile.value,
                style = MaterialTheme.typography.titleLarge.copy(
                    fontWeight = FontWeight.Bold,
                    color = if (tile.tint == Color.Unspecified) MaterialTheme.colorScheme.onSurface else tile.tint,
                ),
                maxLines = 1,
                autoSize = TextAutoSize.StepBased(minFontSize = 13.sp, maxFontSize = MaterialTheme.typography.titleLarge.fontSize),
            )
            tile.detail?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

/** Which weekdays carry the most drinking: average units per weekday across logged days. */
@Composable
fun WeekdayCard(ledger: Ledger, days: DayRange) {
    val clock = ledger.clock
    val byWeekday = days.filter(ledger::isLogged).groupBy { it.weekday }
    val order = (0 until 7).map { (it + clock.firstWeekday - 1) % 7 + 1 }
    val bars = order.mapIndexed { index, weekday ->
        val logged = byWeekday[weekday].orEmpty()
        val average = if (logged.isEmpty()) 0.0 else logged.sumOf { ledger.totals(it).units } / logged.size
        Triple(index, weekday, average)
    }
    val top = maxOf(1.0, bars.maxOf { it.third }) * 1.1
    val name = { weekday: Int, style: TextStyle -> DayOfWeek.of((weekday + 5) % 7 + 1).getDisplayName(style, Locale.getDefault()) }
    ReportCard("By weekday") {
        val plot = Plot(
            from = 0.0,
            to = 7.0,
            top = top,
            bars = bars.map { (index, weekday, average) ->
                PlotBar(index + 0.5, 0.62, listOf(average to GrogColors.grog.copy(alpha = if (weekday == ledger.today.weekday) 1f else 0.45f)), shaded = true)
            },
            xGrid = false,
            xCentred = true,
            slots = bars.map { (index, weekday, average) -> PlotSlot(index.toDouble(), index + 1.0, "${name(weekday, TextStyle.FULL)}, ${average.unitsText} units on average") },
            xAxis = XAxis.Fixed(bars.map { (index, weekday, _) -> index + 0.5 to name(weekday, TextStyle.SHORT) }),
        )
        TimeChart(plot, window = null, height = 160.dp, modifier = Modifier.fillMaxWidth())
    }
}
