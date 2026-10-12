package cc.blit.groglog.data

import android.util.Log
import androidx.room.withTransaction
import cc.blit.groglog.model.Catalog
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayTotals
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Favourite
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

    /** `abv` logs these at a strength of their own, leaving the drink as it is. Returns what was logged, for undoing it. */
    suspend fun log(serve: Serve, times: List<Instant>, abv: Double? = null): List<Pour> {
        val abvOverride = if (abv == serve.drink.abv) null else abv
        val pours = times.map {
            Pour(drinkId = serve.drink.id, timestamp = it, day = clock.day(it).number, vessel = serve.vessel, volumeMl = serve.volumeMl, price = serve.price, abvOverride = abvOverride)
        }
        writeChanging(times.map(clock::day).toSet()) {
            for (pour in pours) rows.insert(pour)
            times.maxOrNull()?.let { rows.markUsed(serve.drink.id, serve.vessel.raw, serve.volumeMl, it) }
            retotal(times.map(clock::day).toSet())
        }
        return pours
    }

    /** Returns what was logged, for undoing it. */
    suspend fun logUnits(units: Double, time: Instant): List<Pour> {
        var pour: Pour? = null
        writeChanging(setOf(clock.day(time))) {
            val drink = unitsDrink()
            pour = Pour(drinkId = drink.id, timestamp = time, day = clock.day(time).number, vessel = Vessel.SHOT, volumeMl = units * 10, price = 0.0)
                .also { rows.insert(it) }
            retotal(setOf(clock.day(time)))
        }
        return listOfNotNull(pour)
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
            if (before != null && (before.abv != drink.abv || before.category != drink.category)) {
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
        write { rows.insert(Favourite(drinkId = serve.drink.id, vessel = serve.vessel, volumeMl = serve.volumeMl, price = serve.price)) }
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
        var changed = 0
        for (drink in rows.drinks()) {
            val price = Catalog.price(drink.name, drink.category, drink.vessel, drink.volumeMl) ?: continue
            if (price == drink.price) continue
            rows.update(drink.copy(price = price))
            changed += 1
        }
        for (favourite in rows.favourites()) {
            val drink = rows.drink(favourite.drinkId) ?: continue
            val price = Catalog.price(drink.name, drink.category, favourite.vessel, favourite.volumeMl) ?: continue
            if (price == favourite.price) continue
            rows.update(favourite.copy(price = price))
            changed += 1
        }
        changed
    } ?: 0

    // Rebuilding

    /**
     * Recomputes every day in one transaction, after an import or when the day-end hour changes (which moves entries
     * between days).
     */
    suspend fun rebuild(reassigningDays: Boolean = false) {
        writeChanging(null) {
            if (reassigningDays) {
                for (pour in rows.pours()) {
                    val day = clock.day(pour.timestamp).number
                    if (day != pour.day) rows.update(pour.copy(day = day))
                }
            }
            val totals = rows.entries().groupBy { it.day }.mapValues { DayTotals.of(it.value) }
            // Rewritten in place rather than deleted and reinserted, so a day's dry mark and manual spend are never
            // dropped along the way.
            for (row in rows.days()) {
                val updated = row.with(totals[row.number] ?: DayTotals())
                if (updated.count == 0 && !updated.isAlcoholFree && updated.costOverride == null) {
                    rows.delete(updated)
                } else {
                    rows.update(updated)
                }
            }
            for ((number, dayTotals) in totals) {
                if (rows.day(number) == null) rows.save(Day(number).with(dayTotals))
            }
        }
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
            val entries = rows.entries(day.number, day.number)
            var row = (rows.day(day.number) ?: Day(day.number)).with(DayTotals.of(entries))
            if (entries.isNotEmpty()) row = row.copy(isAlcoholFree = false)
            save(row)
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
        val drink = Drink(name = "Units", category = DrinkCategory.UNITS, abv = 100.0, vessel = Vessel.SHOT, volumeMl = 10.0, isGeneric = true, sortOrder = 99)
        rows.insert(drink)
        return drink
    }

    private suspend fun save(row: Day) {
        if (row.count == 0 && !row.isAlcoholFree && row.costOverride == null) {
            rows.delete(row)
        } else {
            rows.save(row)
        }
    }

    /** Runs a write and, once it has committed, announces the days it touched. */
    private suspend fun writeChanging(days: Set<DayKey>?, body: suspend () -> Unit) {
        if (write(body) != null) changes.tryEmit(days)
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
