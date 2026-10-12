package cc.blit.groglog.widget

import android.content.Context
import android.widget.Toast
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import cc.blit.groglog.R
import cc.blit.groglog.container
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.theme.GrogColors
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

/**
 * The Log grid's first tiles as buttons that log without opening the app, beside what the day has left. Each tile logs
 * through `QuickLog`, the same `Logbook` transaction as a tap on the grid.
 */
class TilesWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(NARROW, WIDE))
    override val previewSizeMode = SizeMode.Responsive(setOf(NARROW, WIDE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val container = context.container
        val today = Today.observe(container.liveDatabase, container.livePrefs)
        val first = today.first()
        provideContent {
            val current by today.collectAsState(first)
            WidgetTheme { TilesContent(current, currentState(LogTileAction.flash)) }
        }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        provideContent { WidgetTheme { TilesContent(Today.sample, null) } }
    }

    companion object {
        val NARROW = DpSize(110.dp, 110.dp)
        val WIDE = DpSize(250.dp, 110.dp)
    }
}

class TilesWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TilesWidget()
}

/**
 * Logs the tile's drink, then shows a tick on that tile for a moment while the total above it moves. Every widget is
 * redrawn by the commit itself (`Widgets.follow`); only the tick is this widget's own.
 */
class LogTileAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val key = parameters[serve] ?: return
        val container = context.container
        if (QuickLog.log(key, container.liveDatabase, container.livePrefs.current()) == null) {
            withContext(Dispatchers.Main) { Toast.makeText(context, "That drink is no longer in GrogLog.", Toast.LENGTH_SHORT).show() }
            return
        }
        // A second tap during the tick restarts it rather than being cleared by the first.
        val mark = "$key#${System.nanoTime()}"
        updateAppWidgetState(context, glanceId) { it[flash] = mark }
        TilesWidget().update(context, glanceId)
        delay(2.seconds)
        updateAppWidgetState(context, glanceId) { if (it[flash] == mark) it.remove(flash) }
        TilesWidget().update(context, glanceId)
    }

    companion object {
        val serve = ActionParameters.Key<String>("serve")
        internal val flash = stringPreferencesKey("logged")
    }
}

@Composable
private fun TilesContent(today: Today, flash: String?) {
    val size = LocalSize.current
    val logged = flash?.substringBefore('#')
    val modifier = GlanceModifier.widgetSurface().clickable(openLog(LocalContext.current))
    if (size.width >= TilesWidget.WIDE.width) {
        Row(modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Summary(today, width = size.width - 24.dp - 12.dp - 184.dp, height = size.height - 24.dp, modifier = GlanceModifier.defaultWeight().fillMaxHeight())
            if (today.tiles.isNotEmpty()) {
                Spacer(GlanceModifier.width(12.dp))
                TileGrid(today.tiles, logged, GlanceModifier.width(184.dp).fillMaxHeight())
            }
        }
    } else if (today.tiles.isEmpty()) {
        Column(modifier.padding(12.dp)) {
            Summary(today, width = size.width - 24.dp, height = size.height - 24.dp, modifier = GlanceModifier.fillMaxSize())
        }
    } else {
        Column(modifier.padding(8.dp)) {
            Row(GlanceModifier.fillMaxWidth().padding(horizontal = 4.dp).semantics { contentDescription = today.spoken }, verticalAlignment = Alignment.CenterVertically) {
                Text(
                    today.units.unitsText,
                    style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold, color = today.totalColor()),
                    maxLines = 1,
                )
                Spacer(GlanceModifier.width(6.dp))
                Text(
                    if (today.isDry || today.budget != null) today.detail else "units today",
                    style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, color = today.detailColor()),
                    maxLines = 1,
                )
            }
            Spacer(GlanceModifier.height(6.dp))
            TileGrid(today.tiles, logged, GlanceModifier.defaultWeight().fillMaxWidth())
        }
    }
}

/** The Day screen's total, large and coloured by how the day is going, over the budget draining through the day. */
@Composable
private fun Summary(today: Today, width: Dp, height: Dp, modifier: GlanceModifier) {
    Column(modifier.semantics { contentDescription = today.spoken }) {
        Total(today, 36)
        Text(
            if (today.budget == null) "units today" else "units",
            style = TextStyle(fontSize = 13.sp, color = GlanceTheme.colors.onSurfaceVariant),
        )
        Burndown(
            today,
            width = width,
            height = maxOf(16.dp, height - 76.dp),
            modifier = GlanceModifier.defaultWeight().fillMaxWidth().padding(vertical = 4.dp),
        )
        Detail(today)
    }
}

@Composable
private fun TileGrid(tiles: List<Serve>, logged: String?, modifier: GlanceModifier) {
    Column(modifier) {
        tiles.chunked(2).forEachIndexed { index, row ->
            if (index > 0) Spacer(GlanceModifier.height(6.dp))
            Row(GlanceModifier.defaultWeight().fillMaxWidth()) {
                Tile(row[0], row[0].id == logged, GlanceModifier.defaultWeight().fillMaxHeight())
                Spacer(GlanceModifier.width(6.dp))
                // A lone last tile keeps its column's width rather than stretching across both.
                row.getOrNull(1)?.let { Tile(it, it.id == logged, GlanceModifier.defaultWeight().fillMaxHeight()) }
                    ?: Spacer(GlanceModifier.defaultWeight())
            }
        }
    }
}

private val GLYPH = 40.dp

@Composable
private fun Tile(serve: Serve, logged: Boolean, modifier: GlanceModifier) {
    val size = serve.vessel.shortLabel(serve.volumeMl)
    Column(
        modifier
            .background(GlanceTheme.colors.secondaryContainer)
            .cornerRadius(14.dp)
            .clickable(actionRunCallback<LogTileAction>(actionParametersOf(LogTileAction.serve to serve.id)))
            .semantics { contentDescription = if (logged) "Logged ${serve.drink.name}" else "Log ${serve.drink.name}, $size, ${serve.units.unitsText} units" }
            .padding(horizontal = 6.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (logged) {
            Image(
                ImageProvider(R.drawable.ic_logged),
                contentDescription = null,
                modifier = GlanceModifier.size(20.dp),
                colorFilter = ColorFilter.tint(ColorProvider(GrogColors.dry)),
            )
            Text("Logged", style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, color = GlanceTheme.colors.onSecondaryContainer))
        } else {
            val density = LocalContext.current.resources.displayMetrics.density
            Image(
                ImageProvider(Drawings.glyph(serve, (GLYPH.value * density).toInt())),
                contentDescription = null,
                modifier = GlanceModifier.defaultWeight().fillMaxWidth(),
            )
            Text(
                serve.drink.name,
                style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = GlanceTheme.colors.onSecondaryContainer),
                maxLines = 1,
            )
            // The size matters as much as the name: a can and a bottle of the same beer differ by a unit.
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(size, style = TextStyle(fontSize = 10.sp, color = GlanceTheme.colors.onSurfaceVariant), maxLines = 1)
                Spacer(GlanceModifier.width(3.dp))
                Text("${serve.units.unitsText} u", style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, color = ColorProvider(GrogColors.grog)), maxLines = 1)
            }
        }
    }
}
