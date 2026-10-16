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

/** What came of logging from outside the app. */
sealed interface Outcome

/** The key no longer names a drink, as when it was deleted after the tile was drawn. */
data object Gone : Outcome

/** The write failed and nothing was logged. */
data object Failed : Outcome

/** A drink logged from outside the app, and where the day stands after it. */
data class Logged(val serve: Serve, val units: Double, val budget: Double?) : Outcome {
    /** What the iOS intent says after logging: "3.5 units today, 1.0 of 4.5 left." */
    val summary: String
        get() = budget?.let { "${units.unitsText} units today, ${units.leftText(it)}." } ?: "${units.unitsText} units today."
}

/**
 * Logging by `Serve.key`, for a widget tile, the Quick Settings tile and a launcher shortcut. Each goes through the same
 * `Logbook` transaction as a tap on the Log grid, so there is no second write path.
 */
object QuickLog {
    /** Logs the serve now, and says whether it was, so nothing reports a drink logged that was not. */
    suspend fun log(key: String, database: AppDatabase, settings: Settings, at: Instant = Instant.now()): Outcome {
        val serve = Serves.matching(key, database) ?: return Gone
        val clock = settings.clock
        Logbook(database, clock).log(serve, listOf(at)) ?: return Failed
        val day = clock.day(at)
        val ledger = Ledger(database.rows().days(), clock)
        return Logged(serve, ledger.totals(day).units, ledger.dailyBudget(day, settings.goal))
    }
}
