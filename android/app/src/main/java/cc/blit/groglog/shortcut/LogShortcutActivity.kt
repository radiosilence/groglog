package cc.blit.groglog.shortcut

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.lifecycle.lifecycleScope
import cc.blit.groglog.container
import cc.blit.groglog.ui.theme.GrogLogTheme
import cc.blit.groglog.widget.QuickLog
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * A launcher shortcut's target: logs the drink it carries and says so in a small card over whatever was on screen, then
 * goes, so logging from the home screen never opens the app. Android 13 and later hide a toast from the background,
 * and the iOS intent answers in a dialog, so the answer is a window of its own.
 */
class LogShortcutActivity : ComponentActivity() {
    private var message by mutableStateOf<Pair<String, String>?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val key = intent.getStringExtra(EXTRA_SERVE) ?: return finish()
        val app = applicationContext
        val container = app.container
        // The process-wide scope, so the drink is logged even if this window is closed first.
        val write = container.scope.launch {
            val logged = QuickLog.log(key, container.liveDatabase, container.livePrefs.current())
            if (logged != null) ShortcutManagerCompat.reportShortcutUsed(app, key)
            message = logged?.let { "Logged ${it.serve.drink.name}" to it.summary } ?: ("Not logged" to "That drink is no longer in GrogLog.")
        }
        lifecycleScope.launch {
            write.join()
            delay(1_500)
            finish()
        }
        setContent {
            GrogLogTheme {
                Box(
                    Modifier
                        .fillMaxSize()
                        .clickable(interactionSource = null, indication = null, onClick = ::finish)
                        .navigationBarsPadding()
                        .padding(24.dp),
                    contentAlignment = Alignment.BottomCenter,
                ) {
                    message?.let { (title, detail) ->
                        Surface(
                            shape = RoundedCornerShape(20.dp),
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            tonalElevation = 0.dp,
                            shadowElevation = 6.dp,
                            modifier = Modifier.widthIn(max = 360.dp).semantics { liveRegion = LiveRegionMode.Polite },
                        ) {
                            Column(Modifier.padding(horizontal = 20.dp, vertical = 16.dp)) {
                                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                                Text(detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }

    companion object {
        private const val ACTION = "cc.blit.groglog.action.LOG_DRINK"
        private const val EXTRA_SERVE = "serve"

        fun intent(context: Context, key: String): Intent =
            Intent(ACTION).setClass(context, LogShortcutActivity::class.java).putExtra(EXTRA_SERVE, key)
    }
}
