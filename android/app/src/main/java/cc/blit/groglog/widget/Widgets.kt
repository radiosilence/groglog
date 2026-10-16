package cc.blit.groglog.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.updateAll
import cc.blit.groglog.AppContainer
import cc.blit.groglog.container
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.shortcut.Shortcuts
import java.io.File
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.launch

/**
 * Keeps what the log shows outside the app in step with it: both widgets and the launcher shortcuts follow every
 * commit, whoever made it (a screen, a widget tile, an import), and every change to the settings. A widget also has to
 * move on when the day ends with nothing logged, so an alarm redraws it then.
 */
object Widgets {
    fun follow(context: Context, container: AppContainer) {
        container.scope.launch {
            quietly {
                Shortcuts.publish(context, container.liveDatabase)
                scheduleDayEnd(context, container.livePrefs.current().clock)
                publishPreviews(context)
            }
        }
        container.scope.launch {
            merge(
                container.liveDatabase.invalidationTracker.createFlow("pour", "day", "drink", "favourite", emitInitialState = false).map {},
                container.livePrefs.settings.drop(1).map {},
            ).conflate().collect { refresh(context, container) }
        }
    }

    suspend fun refresh(context: Context, container: AppContainer) = quietly {
        TodayWidget().updateAll(context)
        TilesWidget().updateAll(context)
        Shortcuts.publish(context, container.liveDatabase)
        scheduleDayEnd(context, container.livePrefs.current().clock)
    }

    /** Nothing here is worth stopping the app for: a widget left a commit behind is put right by the next one. */
    private suspend fun quietly(body: suspend () -> Unit) {
        try {
            body()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            Log.e("Widgets", "Refresh failed", error)
        }
    }

    /** Not a wake-up alarm: a widget only needs to be right by the time the screen is next on. */
    private fun scheduleDayEnd(context: Context, clock: DayClock) {
        val intent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, DayEndReceiver::class.java).setAction(DayEndReceiver.DAY_END),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        context.getSystemService(AlarmManager::class.java).set(AlarmManager.RTC, clock.end(clock.today).toEpochMilli(), intent)
    }

    /**
     * The widget picker's previews from Android 15, drawn from `providePreview`. Publishing is rate-limited, so it is done
     * once per installed version; the record is kept out of backups, since a restored phone has not published them.
     */
    private suspend fun publishPreviews(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return
        val version = context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode.toString()
        val record = File(context.noBackupFilesDir, "widget-previews")
        if (record.exists() && record.readText() == version) return
        val manager = GlanceAppWidgetManager(context)
        val published = listOf(TodayWidgetReceiver::class, TilesWidgetReceiver::class)
            .map { manager.setWidgetPreviews(it) }
            .all { it == GlanceAppWidgetManager.SET_WIDGET_PREVIEWS_RESULT_SUCCESS }
        if (published) record.writeText(version)
    }
}

/** Redraws the widgets when the day ends, and when the clock or time zone changes under them. */
class DayEndReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in listOf(DAY_END, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) return
        val pending = goAsync()
        val app = context.applicationContext
        val container = app.container
        container.scope.launch {
            try {
                Widgets.refresh(app, container)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        /** The alarm set for the end of the day. */
        const val DAY_END = "cc.blit.groglog.widget.DAY_END"
    }
}
