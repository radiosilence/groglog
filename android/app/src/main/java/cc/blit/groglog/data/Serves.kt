package cc.blit.groglog.data

import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Vessel
import java.util.UUID

/**
 * A serve as a string, `Serve.key`, and back: what a launcher shortcut, a widget or a Quick Settings tile carries to log
 * a drink through the same `Logbook` transaction as the Log grid.
 */
object Serves {
    /**
     * The tiles to offer outside the app: pinned drinks, most recently drunk first, excluding hidden drinks and Units,
     * which in the app asks for an amount and here could only log one. Unlike the Log grid, today's other drinks are not
     * included, since suggestions need not track the day.
     */
    suspend fun grid(database: AppDatabase): List<Serve> =
        database.rows().favouritesByUse()
            .filter { !it.drink.isHidden && it.drink.category != DrinkCategory.UNITS }
            .map { it.serve }

    /**
     * The inverse of `Serve.key`: a drink in a size at its pinned price, or the drink's derived price at that size if it
     * is no longer pinned. Prices are read at call time rather than carried in the key, because they change.
     */
    suspend fun matching(key: String, database: AppDatabase): Serve? {
        val parts = key.split("|").filter { it.isNotEmpty() }
        if (parts.size != 3 || parts[0].length != 36) return null
        val drinkId = runCatching { UUID.fromString(parts[0]) }.getOrNull() ?: return null
        val vessel = Vessel.fromRaw(parts[1]) ?: return null
        val volumeMl = parts[2].toDoubleOrNull() ?: return null
        val rows = database.rows()
        val drink = rows.drink(drinkId) ?: return null
        val price = rows.favourite(drinkId, vessel.raw, volumeMl)?.price
        return if (price != null) Serve(drink, vessel, volumeMl, price) else Serve(drink, vessel, volumeMl)
    }
}
