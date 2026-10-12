package cc.blit.groglog

import android.content.Context
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
class AppContainer(context: Context) {
    val database: AppDatabase = AppDatabase.onDisk(context)
    val prefs = Prefs(context.settingsStore)
    val queries: Queries get() = database.queries()

    /** Work that outlives a screen, such as a rebuild after the day-end hour changes. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** A logbook on the current day-end hour. Settings are read afresh each time, so a changed hour is never stale. */
    suspend fun logbook(): Logbook = Logbook(database, prefs.current().clock)

    init {
        scope.launch { Seed.drinksIfNeeded(logbook()) }
        scope.launch { prefs.settings.collect { Catalog.currency = it.currency } }
    }
}

val Context.container: AppContainer get() = (applicationContext as GrogLogApplication).container
