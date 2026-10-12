package cc.blit.groglog.widget

import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Serves
import cc.blit.groglog.data.Settings
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.leftText
import cc.blit.groglog.model.unitsText
import java.time.Instant

/** A drink logged from outside the app, and where the day stands after it. */
data class Logged(val serve: Serve, val units: Double, val budget: Double?) {
    /** What the iOS intent says after logging: "3.5 units today, 1.0 of 4.5 left." */
    val summary: String
        get() = budget?.let { "${units.unitsText} units today, ${units.leftText(it)}." } ?: "${units.unitsText} units today."
}

/**
 * Logging by `Serve.key`, for a widget tile, the Quick Settings tile and a launcher shortcut. Each goes through the same
 * `Logbook` transaction as a tap on the Log grid, so there is no second write path.
 */
object QuickLog {
    /** Logs the serve now. Null when the key no longer names a drink, as when it was deleted after the tile was drawn. */
    suspend fun log(key: String, database: AppDatabase, settings: Settings, at: Instant = Instant.now()): Logged? {
        val serve = Serves.matching(key, database) ?: return null
        val clock = settings.clock
        Logbook(database, clock).log(serve, listOf(at))
        val day = clock.day(at)
        val ledger = Ledger(database.rows().days(), clock)
        return Logged(serve, ledger.totals(day).units, ledger.dailyBudget(day, settings.goal))
    }
}
