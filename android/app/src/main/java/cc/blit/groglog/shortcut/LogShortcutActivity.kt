package cc.blit.groglog.shortcut

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.core.content.pm.ShortcutManagerCompat
import cc.blit.groglog.container
import cc.blit.groglog.widget.QuickLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * A launcher shortcut's target: logs the drink it carries and finishes without drawing anything, so logging from the
 * home screen never opens the app. The result is reported in a toast, as the iOS intent's dialog reports it.
 */
class LogShortcutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val key = intent.getStringExtra(EXTRA_SERVE)
        // A translucent activity with no window must finish before it would be shown; the write outlives it.
        finish()
        if (key == null) return
        val app = applicationContext
        val container = app.container
        container.scope.launch {
            val logged = QuickLog.log(key, container.database, container.prefs.current())
            if (logged != null) ShortcutManagerCompat.reportShortcutUsed(app, key)
            val message = logged?.let { "Logged ${it.serve.drink.name}. ${it.summary}" } ?: "That drink is no longer in GrogLog."
            withContext(Dispatchers.Main) { Toast.makeText(app, message, Toast.LENGTH_LONG).show() }
        }
    }

    companion object {
        private const val ACTION = "cc.blit.groglog.action.LOG_DRINK"
        private const val EXTRA_SERVE = "serve"

        fun intent(context: Context, key: String): Intent =
            Intent(ACTION).setClass(context, LogShortcutActivity::class.java).putExtra(EXTRA_SERVE, key)
    }
}
