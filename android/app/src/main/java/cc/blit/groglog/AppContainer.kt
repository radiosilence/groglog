package cc.blit.groglog

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.core.content.edit
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Queries
import cc.blit.groglog.data.Seed
import cc.blit.groglog.data.health.Health
import cc.blit.groglog.data.settingsStore
import cc.blit.groglog.model.Catalog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** The log and its settings, one of each per process. Screens read through `queries` and write through `logbook()`. */
class AppContainer(private val context: Context) {
    /**
     * Debug builds can swap the log for four months of sample data (Setup › Developer › Demo mode), as iOS's
     * `Store.demo()` does: the log and its settings in memory, sample heart and sleep readings for Reports, and nothing
     * written to Health Connect. The real log and settings are left untouched.
     */
    val isDemo: Boolean = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
        context.getSharedPreferences(DEVELOPER, Context.MODE_PRIVATE).getBoolean(DEMO_MODE, false)

    val database: AppDatabase = if (isDemo) AppDatabase.inMemory(context) else AppDatabase.onDisk(context)
    val prefs = if (isDemo) Prefs.demo() else Prefs(context.settingsStore)
    val queries: Queries get() = database.queries()

    /**
     * The on-disk log and its settings, which the widgets, the Quick Settings tile and the launcher shortcuts always
     * show and write, as iOS's use `Store.real`. Demo mode never reaches them.
     */
    val liveDatabase: AppDatabase by lazy { if (isDemo) AppDatabase.onDisk(context) else database }
    val livePrefs: Prefs = if (isDemo) Prefs(context.settingsStore) else prefs

    /** Work that outlives a screen, such as a rebuild after the day-end hour changes. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** A logbook on the current day-end hour. Settings are read afresh each time, so a changed hour is never stale. */
    suspend fun logbook(): Logbook = Logbook(database, prefs.current().clock)

    val health = Health(database, prefs, if (isDemo) ({ null }) else Health.connect(context))

    init {
        scope.launch {
            prefs.finishDayEndMove(database)
            Seed.drinksIfNeeded(logbook())
            if (isDemo) Seed.sample(logbook())
        }
        scope.launch { prefs.settings.collect { Catalog.currency = it.currency } }
        if (!isDemo) mirrorToHealth()
    }

    private fun mirrorToHealth() {
        // After the transaction, never inside it, so the log never waits on Health Connect or fails with it.
        scope.launch { Logbook.changed.collect { health.mirror(it) } }
        // Catches up anything that reached the log while Health Connect could not be written, such as a widget's tap
        // with the app in the background. Rewriting an unchanged day leaves it as it was.
        ProcessLifecycleOwner.get().lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                if (event != Lifecycle.Event.ON_START) return@LifecycleEventObserver
                scope.launch {
                    val today = prefs.current().clock.today
                    health.mirror(setOf(today - 1, today))
                }
            },
        )
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
