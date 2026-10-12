package cc.blit.groglog

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.core.content.edit
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Queries
import cc.blit.groglog.data.Seed
import cc.blit.groglog.data.settingsStore
import cc.blit.groglog.model.Catalog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** The log and its settings, one of each per process. Screens read through `queries` and write through `logbook()`. */
class AppContainer(private val context: Context) {
    /**
     * Debug builds can swap the log for four months of sample data in memory (Setup › Developer › Demo mode), leaving
     * the real log untouched. Settings are shared.
     */
    val isDemo: Boolean = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
        context.getSharedPreferences(DEVELOPER, Context.MODE_PRIVATE).getBoolean(DEMO_MODE, false)

    val database: AppDatabase = if (isDemo) AppDatabase.inMemory(context) else AppDatabase.onDisk(context)
    val prefs = Prefs(context.settingsStore)
    val queries: Queries get() = database.queries()

    /** Work that outlives a screen, such as a rebuild after the day-end hour changes. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** A logbook on the current day-end hour. Settings are read afresh each time, so a changed hour is never stale. */
    suspend fun logbook(): Logbook = Logbook(database, prefs.current().clock)

    init {
        scope.launch {
            Seed.drinksIfNeeded(logbook())
            if (isDemo) Seed.sample(logbook())
        }
        scope.launch { prefs.settings.collect { Catalog.currency = it.currency } }
    }

    /** Turns demo mode on or off and restarts the app on the chosen log, since every screen holds the database. */
    fun setDemo(on: Boolean) {
        // Written before returning, since the process exits next.
        context.getSharedPreferences(DEVELOPER, Context.MODE_PRIVATE).edit(commit = true) { putBoolean(DEMO_MODE, on) }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)?.component ?: return
        context.startActivity(Intent.makeRestartActivityTask(launch))
        Runtime.getRuntime().exit(0)
    }

    private companion object {
        const val DEVELOPER = "developer"
        const val DEMO_MODE = "demoMode"
    }
}

val Context.container: AppContainer get() = (applicationContext as GrogLogApplication).container
