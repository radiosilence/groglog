package cc.blit.groglog.ui.calendar

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LifecycleResumeEffect

/**
 * Whether to tell heat bands apart by a mark as well as by colour, Android's nearest to iOS's Differentiate Without
 * Colour. Android has no such switch, so this follows the settings of someone who does not rely on colour: colour
 * correction (any mode, greyscale included) and, from Android 16, high-contrast text. Read again on each resume, since
 * both are changed in Settings while the app is in the background.
 */
@Composable
internal fun differentiateWithoutColour(): Boolean {
    val context = LocalContext.current
    var differentiate by remember { mutableStateOf(asksForMarks(context)) }
    LifecycleResumeEffect(context) {
        differentiate = asksForMarks(context)
        onPauseOrDispose {}
    }
    return differentiate
}

private fun asksForMarks(context: Context): Boolean {
    val correction = runCatching { Settings.Secure.getInt(context.contentResolver, "accessibility_display_daltonizer_enabled", 0) == 1 }.getOrDefault(false)
    val contrast = Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA &&
        context.getSystemService(AccessibilityManager::class.java)?.isHighContrastTextEnabled == true
    return correction || contrast
}
