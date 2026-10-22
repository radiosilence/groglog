package cc.blit.groglog.data

import android.util.Log
import androidx.room.withTransaction
import cc.blit.groglog.core.DayPour
import cc.blit.groglog.core.DrinkPriceIn
import cc.blit.groglog.core.FavouritePriceIn
import cc.blit.groglog.core.PourTotals
import cc.blit.groglog.core.logbookAbvOverride
import cc.blit.groglog.core.logbookDayAfterEdit
import cc.blit.groglog.core.logbookDrinkEditRetotals
import cc.blit.groglog.core.logbookPriceResets
import cc.blit.groglog.core.logbookRebuild
import cc.blit.groglog.core.logbookRetotal
import cc.blit.groglog.model.Catalog
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Favourite
import cc.blit.groglog.model.Generics
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Vessel
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/**
 * Every change to the log goes through here, each as one transaction. After a change only the affected days' totals
 * are recomputed from their entries, so `Day` rows are always derived, never incremented, and cannot drift. Observed
 * queries refresh as each transaction commits.
 *
 * A write that fails is logged and dropped rather than thrown, as on iOS: the screens that call these have nothing
 * useful to do with the error.
 */
class Logbook(val database: AppDatabase, val clock: DayClock) {
    internal val rows: Rows = database.rows()

    // Entries

    /**
     * `abv` logs these at a strength of their own, leaving the drink as it is. Returns what was logged, for undoing it,
     * or null when the write failed and nothing was.
     */
    suspend fun log(serve: Serve, times: List<Instant>, abv: Double? = null): List<Pour>? {
        val abvOverride = logbookAbvOverride(serve.drink.abv, abv)
        val pours = times.map {
            Pour(drinkId = serve.drink.id, timestamp = it, day = clock.day(it).number, vessel = serve.vessel, volumeMl = serve.volumeMl, price = serve.price, abvOverride = abvOverride)
        }
        val committed = writeChanging(times.map(clock::day).toSet()) {
            store(serve.drink)
            for (pour in pours) rows.insert(pour)
            times.maxOrNull()?.let { rows.markUsed(serve.drink.id, serve.vessel.raw, serve.volumeMl, it) }
            retotal(times.map(clock::day).toSet())
        }
        return pours.takeIf { committed }
    }

    /** Returns what was logged, for undoing it, or null when the write failed. */
    suspend fun logUnits(units: Double, time: Instant): List<Pour>? {
        var pour: Pour? = null
        val committed = writeChanging(setOf(clock.day(time))) {
            val drink = unitsDrink()
            pour = Pour(drinkId = drink.id, timestamp = time, day = clock.day(time).number, vessel = Vessel.SHOT, volumeMl = units * 10, price = 0.0)
                .also { rows.insert(it) }
            retotal(setOf(clock.day(time)))
        }
        return listOfNotNull(pour).takeIf { committed }
    }

    suspend fun delete(pour: Pour) = delete(listOf(pour))

    /** Removes these entries, in one transaction. One already gone is passed over. */
    suspend fun delete(pours: Collection<Pour>) {
        val days = pours.mapTo(HashSet()) { it.dayKey }
        writeChanging(days) {
            for (pour in pours) rows.delete(pour)
            retotal(days)
        }
    }

    /**
     * Removes the most recently logged drink on a day, by insertion order rather than timestamp, so undoing a backdated
     * drink removes that one. The rowid gives insertion order; a pour's id is random and its timestamp is when it was
     * drunk.
     */
    suspend fun undo(day: DayKey) {
        writeChanging(setOf(day)) {
            val last = rows.lastLogged(day.number) ?: return@writeChanging
            rows.delete(last)
            retotal(setOf(day))
        }
    }

    suspend fun update(pour: Pour, time: Instant, vessel: Vessel, volumeMl: Double, price: Double, abvOverride: Double? = null) {
        writeChanging(setOf(pour.dayKey, clock.day(time))) {
            val updated = pour.copy(abvOverride = abvOverride, timestamp = time, day = clock.day(time).number, vessel = vessel, volumeMl = volumeMl, price = price)
            rows.update(updated)
            retotal(setOf(pour.dayKey, updated.dayKey))
        }
    }

    /** Sets a day's spend manually, or clears it so spend is the sum of the drinks' prices. */
    suspend fun setSpend(amount: Double?, day: DayKey) {
        write { save((rows.day(day.number) ?: Day(day.number)).copy(costOverride = amount)) }
    }

    suspend fun setAlcoholFree(dry: Boolean, day: DayKey) {
        write { save((rows.day(day.number) ?: Day(day.number)).copy(isAlcoholFree = dry)) }
    }

    // Drinks

    /** Saves a drink. If its strength or type changed, every day it was logged on is retotalled. */
    suspend fun save(drink: Drink) {
        val retotalled = write {
            val before = rows.drink(drink.id)
            rows.save(drink)
            if (before != null && logbookDrinkEditRetotals(before.abv, before.category.kind, drink.abv, drink.category.kind)) {
                rows.days(drink.id).map(::DayKey).toSet().also { retotal(it) }
            } else {
                emptySet()
            }
        }
        if (!retotalled.isNullOrEmpty()) changes.tryEmit(retotalled)
    }

    /** Adds a new drink, pinned to the Log grid at its usual size. */
    suspend fun add(drink: Drink) {
        write {
            rows.insert(drink)
            rows.insert(Favourite(drinkId = drink.id, vessel = drink.vessel, volumeMl = drink.volumeMl, price = drink.price))
        }
    }

    /** Only drinks never logged can be deleted (the schema refuses otherwise); the rest can be hidden. */
    suspend fun delete(drink: Drink) {
        write { rows.delete(drink) }
    }

    /** The drink with this name and type, or a new one created at this size. */
    suspend fun drink(name: String, category: DrinkCategory, abv: Double, vessel: Vessel, volumeMl: Double, price: Double = 0.0): Drink? =
        write { findOrCreate(name, category, abv, vessel, volumeMl, price) }

    suspend fun pin(serve: Serve) {
        write {
            store(serve.drink)
            rows.insert(Favourite(drinkId = serve.drink.id, vessel = serve.vessel, volumeMl = serve.volumeMl, price = serve.price))
        }
    }

    /** Stores a generic drink the grid offered before it was ever used (`Generics`), under its fixed id. */
    private suspend fun store(drink: Drink) {
        if (drink.isGeneric && rows.drink(drink.id) == null) rows.insert(drink)
    }

    suspend fun unpin(favourite: Favourite) {
        write { rows.delete(favourite) }
    }

    /**
     * Resets every drink and Log tile to the catalogue price, for prices that drifted or were never set. Drinks the
     * catalogue does not price are left alone, and logged entries keep the price recorded at the time. Returns how many
     * changed.
     */
    suspend fun resetPrices(): Int = write {
        val drinks = rows.drinks()
        val favourites = rows.favourites()
        val resets = logbookPriceResets(
            drinks.map { DrinkPriceIn(it.id.toString(), it.name, it.category.kind, it.vessel.kind, it.volumeMl, it.price) },
            favourites.map { FavouritePriceIn(it.id.toString(), it.drinkId.toString(), it.vessel.kind, it.volumeMl, it.price) },
            Catalog.currency,
        )
        val drinkPrices = resets.drinks.associate { it.id to it.price }
        val favouritePrices = resets.favourites.associate { it.id to it.price }
        for (drink in drinks) drinkPrices[drink.id.toString()]?.let { rows.update(drink.copy(price = it)) }
        for (favourite in favourites) favouritePrices[favourite.id.toString()]?.let { rows.update(favourite.copy(price = it)) }
        drinkPrices.size + favouritePrices.size
    } ?: 0

    // Rebuilding

    /**
     * Recomputes every day in one transaction, after an import or when the day-end hour changes (which moves entries
     * between days).
     */
    suspend fun rebuild(reassigningDays: Boolean = false): Boolean =
        writeChanging(null) {
            if (reassigningDays) {
                for (pour in rows.pours()) {
                    val day = clock.day(pour.timestamp).number
                    if (day != pour.day) rows.update(pour.copy(day = day))
                }
            }
            // Rewritten in place rather than deleted and reinserted, so a day's dry mark and manual spend are never
            // dropped along the way.
            val plan = logbookRebuild(
                rows.days().map { it.core },
                rows.entries().map { DayPour(it.day.toLong(), it.units, it.kcal, it.price) },
            )
            for (row in plan.updates) rows.update(Day.of(row))
            for (number in plan.deletes) rows.delete(Day(number.toInt()))
            for (row in plan.inserts) rows.save(Day.of(row))
        }

    /** Runs a batch of writes, such as an import, as one transaction, retotalling the touched days at the end. */
    internal suspend fun bulk(body: suspend (Rows) -> Set<DayKey>) {
        val touched = database.withTransaction { body(rows).also { retotal(it) } }
        changes.tryEmit(touched)
    }

    companion object {
        private val changes = MutableSharedFlow<Set<DayKey>?>(extraBufferCapacity = 1024)

        /**
         * The days each committed write changed the entries of, from every logbook in the process, or null for a
         * rebuild, which may have changed any. The Health Connect mirror follows this, so no write path can skip it.
         * Nothing is buffered without a collector.
         */
        val changed: SharedFlow<Set<DayKey>?> = changes
    }

    // Internals

    /** Recomputes days from their entries. Logging a drink clears a dry mark; a day left with neither is deleted. */
    internal suspend fun retotal(days: Set<DayKey>) {
        for (day in days) {
            val result = logbookRetotal(
                rows.day(day.number)?.core,
                day.number.toLong(),
                rows.entries(day.number, day.number).map { PourTotals(it.units, it.kcal, it.price) },
            )
            save(Day.of(result.row), result.delete)
        }
    }

    internal suspend fun findOrCreate(name: String, category: DrinkCategory, abv: Double, vessel: Vessel, volumeMl: Double, price: Double = 0.0): Drink {
        rows.drink(name, category.raw)?.let { return it }
        val drink = Drink(name = name, category = category, abv = abv, vessel = vessel, volumeMl = volumeMl, price = price)
        rows.insert(drink)
        return drink
    }

    internal suspend fun unitsDrink(): Drink {
        rows.drinkOfCategory(DrinkCategory.UNITS.raw)?.let { return it }
        rows.insert(Generics.units)
        return Generics.units
    }

    private suspend fun save(row: Day) {
        val result = logbookDayAfterEdit(row.core)
        save(Day.of(result.row), result.delete)
    }

    private suspend fun save(row: Day, delete: Boolean) {
        if (delete) rows.delete(row) else rows.save(row)
    }

    /** Runs a write and, once it has committed, announces the days it touched. False when it failed and was rolled back. */
    private suspend fun writeChanging(days: Set<DayKey>?, body: suspend () -> Unit): Boolean {
        val committed = write(body) != null
        if (committed) changes.tryEmit(days)
        return committed
    }

    private suspend fun <T> write(body: suspend () -> T): T? =
        try {
            database.withTransaction { body() }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            Log.e("Logbook", "Write failed", error)
            null
        }
}
