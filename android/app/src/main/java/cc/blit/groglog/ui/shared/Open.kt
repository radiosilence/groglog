package cc.blit.groglog.ui.shared

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.activity.result.ActivityResultLauncher
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.staticCompositionLocalOf
import kotlinx.coroutines.launch

/**
 * Starts an activity another app answers. False when no app can, or the platform refuses (an action protected by a
 * permission GrogLog does not hold), so the caller says so rather than the app closing.
 */
fun Context.startSafely(intent: Intent): Boolean =
    try {
        startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }

/** As `startSafely`, for a system picker or permission screen launched for its result. */
fun <I> ActivityResultLauncher<I>.launchSafely(input: I): Boolean =
    try {
        launch(input)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }

/** The page's snackbar, for a row deep in it to say something brief. */
val LocalSnackbar = staticCompositionLocalOf<SnackbarHostState?> { null }

/** Shows a message in the page's snackbar, where it has one. */
@Composable
fun rememberNotice(): (String) -> Unit {
    val host = LocalSnackbar.current
    val scope = rememberCoroutineScope()
    return remember(host, scope) { { message -> host?.let { scope.launch { it.showSnackbar(message) } } } }
}
