package cc.blit.groglog.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.Action
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.material3.ColorProviders
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.MainActivity
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.dark
import cc.blit.groglog.ui.theme.light

/** The wallpaper's colours where the launcher offers them (Android 12 on), GrogLog's own before that. */
@Composable
internal fun WidgetTheme(content: @Composable () -> Unit) {
    GlanceTheme(colors = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) GlanceTheme.colors else ColorProviders(light, dark), content = content)
}

/** The widget's own surface, with the launcher's corner radius where it has one. */
@Composable
internal fun GlanceModifier.widgetSurface() =
    fillMaxSize().appWidgetBackground().background(GlanceTheme.colors.widgetBackground).cornerRadius(android.R.dimen.system_app_widget_background_radius)

/** Opens the app on the Log tab, as tapping the iOS widgets does. */
internal fun openLog(context: Context): Action =
    actionStartActivity(
        Intent(Intent.ACTION_VIEW, Uri.parse("groglog://log"), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
    )

internal val Today.heatColor: ColorProvider get() = ColorProvider(heat)

/** The total's colour: the heat once something is logged, quiet before. */
@Composable
internal fun Today.totalColor(): ColorProvider = if (units > 0) heatColor else GlanceTheme.colors.onSurfaceVariant

/** The detail line's colour: teal for a dry day, otherwise as the total. */
@Composable
internal fun Today.detailColor(): ColorProvider = if (isDry) ColorProvider(GrogColors.dry) else totalColor()

@Composable
internal fun Total(today: Today, size: Int) {
    Text(
        today.units.unitsText,
        style = TextStyle(fontSize = size.sp, fontWeight = FontWeight.Bold, color = today.totalColor()),
        maxLines = 1,
    )
}

@Composable
internal fun Detail(today: Today) {
    Text(
        today.detail,
        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium, color = today.detailColor()),
        maxLines = 1,
    )
}

/** The Day screen's budget bar at widget size. Left out with no budget, since it would have nothing to measure. */
@Composable
internal fun DrainBar(today: Today) {
    val left = today.left ?: return
    LinearProgressIndicator(
        progress = left,
        modifier = GlanceModifier.fillMaxWidth().height(5.dp),
        color = today.heatColor,
        backgroundColor = GlanceTheme.colors.surfaceVariant,
    )
}

/** The burndown chart, drawn at the size it will be shown so its line keeps its weight. */
@Composable
internal fun Burndown(today: Today, width: Dp, height: Dp, modifier: GlanceModifier = GlanceModifier) {
    val density = LocalContext.current.resources.displayMetrics.density
    val bitmap = Drawings.burndown(today.burndown, today.heat.toArgb(), (width.value * density).toInt(), (height.value * density).toInt(), density)
    Image(ImageProvider(bitmap), contentDescription = null, modifier = modifier, contentScale = ContentScale.FillBounds)
}
