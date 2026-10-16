package cc.blit.groglog.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
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

/**
 * The scheme used before Android 12 and when wallpaper colours are off: Material's tonal-spot scheme generated from
 * GrogLog's amber, so surfaces are warm neutrals tinted by the seed and containers carry the amber.
 */
internal val light = lightColorScheme(
    primary = Color(0xFF815620),
    onPrimary = Color(0xFFFFF7F3),
    primaryContainer = Color(0xFFFEC483),
    onPrimaryContainer = Color(0xFF633D07),
    inversePrimary = Color(0xFFFEC483),
    secondary = Color(0xFF725B42),
    onSecondary = Color(0xFFFFF7F3),
    secondaryContainer = Color(0xFFFDDDBD),
    onSecondaryContainer = Color(0xFF644E35),
    tertiary = Color(0xFF5E632F),
    onTertiary = Color(0xFFF9FEBB),
    tertiaryContainer = Color(0xFFF6FCB9),
    onTertiaryContainer = Color(0xFF5C612D),
    background = Color(0xFFFFF8F4),
    onBackground = Color(0xFF3B3125),
    surface = Color(0xFFFFF8F4),
    onSurface = Color(0xFF3B3125),
    surfaceVariant = Color(0xFFF2DFCF),
    onSurfaceVariant = Color(0xFF6A5D50),
    surfaceTint = Color(0xFF815620),
    inverseSurface = Color(0xFF120D08),
    inverseOnSurface = Color(0xFFA59B93),
    error = Color(0xFFA73B21),
    onError = Color(0xFFFFF7F6),
    errorContainer = Color(0xFFFD795A),
    onErrorContainer = Color(0xFF6E1400),
    outline = Color(0xFF87786A),
    outlineVariant = Color(0xFFC0AFA0),
    scrim = Color(0xFF000000),
    surfaceBright = Color(0xFFFFF8F4),
    surfaceDim = Color(0xFFE9D7C7),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFFFF1E6),
    surfaceContainer = Color(0xFFFBEBDD),
    surfaceContainerHigh = Color(0xFFF6E5D7),
    surfaceContainerHighest = Color(0xFFF2DFCF),
)

internal val dark = darkColorScheme(
    primary = Color(0xFFEDBE8B),
    onPrimary = Color(0xFF593A12),
    primaryContainer = Color(0xFF6D4C22),
    onPrimaryContainer = Color(0xFFFFDDBC),
    inversePrimary = Color(0xFF7C582E),
    secondary = Color(0xFFE0C1A3),
    onSecondary = Color(0xFF513C25),
    secondaryContainer = Color(0xFF4B3821),
    onSecondaryContainer = Color(0xFFD8BA9C),
    tertiary = Color(0xFFF9FEBB),
    onTertiary = Color(0xFF5E632F),
    tertiaryContainer = Color(0xFFEBF0AE),
    onTertiaryContainer = Color(0xFF555A27),
    background = Color(0xFF120D08),
    onBackground = Color(0xFFF5E2D2),
    surface = Color(0xFF120D08),
    onSurface = Color(0xFFF5E2D2),
    surfaceVariant = Color(0xFF2E2419),
    onSurfaceVariant = Color(0xFFB9A899),
    surfaceTint = Color(0xFFEDBE8B),
    inverseSurface = Color(0xFFFFF8F4),
    inverseOnSurface = Color(0xFF5C544C),
    error = Color(0xFFF97758),
    onError = Color(0xFF450900),
    errorContainer = Color(0xFF85230A),
    onErrorContainer = Color(0xFFFF9B82),
    outline = Color(0xFF817365),
    outlineVariant = Color(0xFF52463A),
    scrim = Color(0xFF000000),
    surfaceBright = Color(0xFF352A1F),
    surfaceDim = Color(0xFF120D08),
    surfaceContainerLowest = Color(0xFF000000),
    surfaceContainerLow = Color(0xFF19120B),
    surfaceContainer = Color(0xFF201810),
    surfaceContainerHigh = Color(0xFF261E15),
    surfaceContainerHighest = Color(0xFF2E2419),
)

/**
 * The wallpaper's colours on Android 12 and later when `dynamicColour` is on, otherwise GrogLog's own scheme. The budget
 * colours in `GrogColors` carry meaning, so they stay the same under either.
 */
/**
 * A data colour used as text. Its mid-tones are too pale for small text on a light surface, so they are darkened there;
 * on dark surfaces and for shapes and strokes it is used as it is.
 */
@Composable
fun Color.asText(): Color = if (MaterialTheme.colorScheme.surface.luminance() > 0.5f) lerp(this, Color.Black, 0.45f) else this

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun GrogLogTheme(dynamicColour: Boolean = true, darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val context = LocalContext.current
    val scheme = when {
        dynamicColour && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        darkTheme -> dark
        else -> light
    }
    MaterialExpressiveTheme(colorScheme = scheme, motionScheme = MotionScheme.expressive(), content = content)
}
