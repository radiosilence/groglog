package cc.blit.groglog.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalContext
import cc.blit.groglog.model.Units
import kotlin.math.min

/** GrogLog's colours, the same in light and dark as on iOS. */
object GrogColors {
    val grog = Color(0.97f, 0.64f, 0.20f)
    val dry = Color(0.20f, 0.74f, 0.60f)
    val over = Color(0.88f, 0.24f, 0.30f)
    val hrv = Color(0.45f, 0.42f, 0.95f)
    val pulse = Color(0.93f, 0.36f, 0.62f)
    val sleeping = Color(0.25f, 0.62f, 0.95f)
    val deepSleep = Color(0.29f, 0.25f, 0.72f)
    val coreSleep = Color(0.42f, 0.55f, 0.95f)
    val remSleep = Color(0.55f, 0.82f, 0.98f)

    /** Teal for a day inside its budget, amber just over, sliding to red the further past it goes. */
    fun heat(units: Double, budget: Double?): Color {
        val limit = budget ?: (Units.WEEKLY_GUIDELINE / 7)
        if (units <= limit) return dry
        return lerp(grog, over, min(1.0, (units - limit) / limit).toFloat())
    }
}

/**
 * The bands `GrogColors.heat` shades between, for telling them apart by something other than hue: a mark where colour
 * alone is not enough, and words for TalkBack.
 */
enum class HeatBand {
    WITHIN, OVER, WELL_OVER;

    val mark: String?
        get() = when (this) {
            WITHIN -> null
            OVER -> "!"
            WELL_OVER -> "!!"
        }

    val spoken: String
        get() = when (this) {
            WITHIN -> "within budget"
            OVER -> "over budget"
            WELL_OVER -> "well over budget"
        }

    companion object {
        /** Well over is half as much again as the budget, where the colour is halfway from amber to red. */
        fun of(units: Double, budget: Double?): HeatBand {
            val limit = budget ?: (Units.WEEKLY_GUIDELINE / 7)
            return when {
                units <= limit -> WITHIN
                units < limit * 1.5 -> OVER
                else -> WELL_OVER
            }
        }
    }
}

private val light = lightColorScheme(
    primary = GrogColors.grog,
    onPrimary = Color.Black,
    secondary = GrogColors.dry,
    onSecondary = Color.Black,
    error = GrogColors.over,
)

private val dark = darkColorScheme(
    primary = GrogColors.grog,
    onPrimary = Color.Black,
    secondary = GrogColors.dry,
    onSecondary = Color.Black,
    error = GrogColors.over,
)

/**
 * GrogLog's palette, or with `dynamicColour` the wallpaper's on Android 12 and later. The budget colours in
 * `GrogColors` carry meaning, so they stay the same under either.
 */
@Composable
fun GrogLogTheme(dynamicColour: Boolean = false, darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val context = LocalContext.current
    val scheme = when {
        dynamicColour && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        darkTheme -> dark
        else -> light
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
