package cc.blit.groglog.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import cc.blit.groglog.container
import cc.blit.groglog.model.unitsText
import kotlinx.coroutines.flow.first

/**
 * Today against the day's budget, with a tap into the Log grid, so logging a drink at a bar takes two taps instead of
 * finding the app first. It grows from the iOS Lock Screen ring at one cell, through its rectangular reading, to the
 * Home Screen widget's summary with the burndown chart.
 */
class TodayWidget : GlanceAppWidget() {
    // Exact, so LocalSize is the widget's own size rather than a bucket's, and the chart is drawn at the size it shows.
    override val sizeMode = SizeMode.Exact
    override val previewSizeMode = SizeMode.Responsive(setOf(LINE, CHART))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val container = context.container
        val today = Today.observe(container.liveDatabase, container.livePrefs)
        val first = today.first()
        provideContent {
            val current by today.collectAsState(first)
            WidgetTheme { TodayContent(current) }
        }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        provideContent { WidgetTheme { TodayContent(Today.sample) } }
    }

    companion object {
        val RING = DpSize(48.dp, 48.dp)
        val LINE = DpSize(120.dp, 48.dp)
        val CHART = DpSize(120.dp, 110.dp)
    }
}

class TodayWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TodayWidget()
}

@Composable
private fun TodayContent(today: Today) {
    val size = LocalSize.current
    val modifier = GlanceModifier.widgetSurface()
        .clickable(openLog(LocalContext.current))
        .semantics { contentDescription = today.spoken }
    when {
        size.width < TodayWidget.LINE.width -> Ring(today, minOf(size.width, size.height), modifier)
        size.height < TodayWidget.CHART.height -> Box(modifier.padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) {
            Column {
                Total(today, 26)
                Detail(today)
                if (today.left != null) {
                    Spacer(GlanceModifier.height(4.dp))
                    DrainBar(today)
                }
            }
        }
        else -> Column(modifier.padding(14.dp)) {
            Total(today, 36)
            Text(
                if (today.budget == null) "units today" else "units",
                style = TextStyle(fontSize = 13.sp, color = GlanceTheme.colors.onSurfaceVariant),
            )
            // With no budget there is nothing to burn down, and a climbing line says no more than the total.
            if (today.budget != null && !today.isDry) {
                Burndown(
                    today,
                    width = size.width - 28.dp,
                    height = maxOf(16.dp, size.height - 28.dp - 90.dp),
                    modifier = GlanceModifier.defaultWeight().fillMaxWidth().padding(vertical = 4.dp),
                )
            } else {
                Spacer(GlanceModifier.defaultWeight())
            }
            today.detail?.let { Detail(today) }
        }
    }
}

/**
 * The day's budget as a ring that drains as drinks are logged, with the total inside. With no goal the ring is left out:
 * clamping to the guideline instead would pin it full all evening, which looks broken.
 */
@Composable
private fun Ring(today: Today, side: Dp, modifier: GlanceModifier) {
    val density = LocalContext.current.resources.displayMetrics.density
    Box(modifier, contentAlignment = Alignment.Center) {
        today.left?.let { left ->
            val bitmap = Drawings.ring(left, today.heat.toArgb(), (side.value * density).toInt(), density)
            Image(ImageProvider(bitmap), contentDescription = null, modifier = GlanceModifier.size(side))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                today.units.unitsText,
                style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold, color = today.totalColor()),
                maxLines = 1,
            )
            if (today.isOver) {
                Text("OVER", style = TextStyle(fontSize = 9.sp, fontWeight = FontWeight.Bold, color = today.heatColor))
            }
        }
    }
}
