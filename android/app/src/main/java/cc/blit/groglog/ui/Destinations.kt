package cc.blit.groglog.ui

import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow

/** Where a widget, a shortcut or a link asked the app to open: `groglog://log` and `groglog://log/units`. */
enum class Destination { LOG, UNITS }

/**
 * The destination waiting to be shown. `MainActivity` puts the Log tab on the back stack and clears `LOG`; the Log tab opens its
 * units sheet for `UNITS` and clears it.
 */
object Destinations {
    val pending = MutableStateFlow<Destination?>(null)

    fun open(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != "groglog" || uri.host != "log") return
        pending.value = if (uri.pathSegments.firstOrNull() == "units") Destination.UNITS else Destination.LOG
    }
}
