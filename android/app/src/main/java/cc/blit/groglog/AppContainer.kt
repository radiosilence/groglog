package cc.blit.groglog

import android.content.Context
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
class AppContainer(context: Context) {
    val database: AppDatabase = AppDatabase.onDisk(context)
    val prefs = Prefs(context.settingsStore)
    val queries: Queries get() = database.queries()

    /** Work that outlives a screen, such as a rebuild after the day-end hour changes. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** A logbook on the current day-end hour. Settings are read afresh each time, so a changed hour is never stale. */
    suspend fun logbook(): Logbook = Logbook(database, prefs.current().clock)

    val health = Health(database, prefs, Health.connect(context))

    init {
        scope.launch { Seed.drinksIfNeeded(logbook()) }
        scope.launch { prefs.settings.collect { Catalog.currency = it.currency } }
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
}

val Context.container: AppContainer get() = (applicationContext as GrogLogApplication).container
