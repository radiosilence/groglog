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
import cc.blit.groglog.widget.Failed
import cc.blit.groglog.widget.Gone
import cc.blit.groglog.widget.Logged
import cc.blit.groglog.widget.QuickLog
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.activity.viewModels
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.Deferred
import cc.blit.groglog.widget.Outcome

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
        // Held by a ViewModel, so a rotation or theme change while the card shows reads the same result rather than
        // logging the drink again.
        val write by viewModels<Write> { viewModelFactory { initializer { Write(applicationContext, key) } } }
        lifecycleScope.launch {
            message = when (val outcome = write.outcome.await()) {
                is Logged -> "Logged ${outcome.serve.drink.name}" to outcome.summary
                Gone -> "Not logged" to "That drink is no longer in GrogLog."
                Failed -> "Couldn't log" to "Nothing was logged. Try again, or log it in GrogLog."
            }
            delay(2_000)
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

    /** The one write a shortcut tap makes, in the process-wide scope so it finishes even if this window closes first. */
    class Write(context: Context, key: String) : ViewModel() {
        val outcome: Deferred<Outcome> = context.container.let { container ->
            container.scope.async {
                QuickLog.log(key, container.liveDatabase, container.livePrefs.current())
                    .also { if (it is Logged) ShortcutManagerCompat.reportShortcutUsed(context, key) }
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
