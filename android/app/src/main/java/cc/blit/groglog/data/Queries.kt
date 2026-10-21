package cc.blit.groglog.data

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Transaction
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayRange
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.FavouriteItem
import cc.blit.groglog.model.Pour
import java.text.Collator
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/**
 * Observed reads for screens. Each re-emits after any commit touching its tables, so screens update as soon as a write
 * lands, and each reads only what its screen shows. Observation is by table, so logging a drink re-runs every entries
 * query in the app; the public flows drop a result equal to the last, so a screen is not recomposed with an identical
 * list.
 */
@Dao
abstract class Queries {
    /** Every day's totals: the whole history in a few hundred rows a year. */
    fun days(): Flow<List<Day>> = observeDays().distinctUntilChanged()

    /**
     * Log entries with their drinks for a range of days, oldest first. A pour's day follows from its time, so ordering
     * by both is ordering by time, and it is the order the `(day, timestamp)` index already holds.
     */
    fun entries(days: DayRange): Flow<List<Entry>> =
        observeEntries(days.start.number, days.endInclusive.number).distinctUntilChanged()

    /** The Log grid's pinned drink-and-size tiles. */
    fun favourites(): Flow<List<FavouriteItem>> = observeFavourites().distinctUntilChanged()

    /** Every drink, by name as the reader's language sorts it, ignoring case. */
    fun drinks(): Flow<List<Drink>> {
        val collator = Collator.getInstance().apply { strength = Collator.SECONDARY }
        return observeDrinks().map { drinks -> drinks.sortedWith { a, b -> collator.compare(a.name, b.name) } }.distinctUntilChanged()
    }

    /** How many times a drink has been logged, which decides whether it can be deleted. */
    fun pourCount(drinkId: UUID): Flow<Int> = observePourCount(drinkId).distinctUntilChanged()

    /** Every drink ever logged, read once when the Log grid is ordered rather than observed. */
    @Query("SELECT * FROM pour")
    abstract suspend fun history(): List<Pour>

    @Query("SELECT * FROM day ORDER BY number")
    protected abstract fun observeDays(): Flow<List<Day>>

    @Transaction
    @Query("SELECT * FROM pour WHERE day BETWEEN :from AND :to ORDER BY day, timestamp")
    protected abstract fun observeEntries(from: Int, to: Int): Flow<List<Entry>>

    @Transaction
    @Query("SELECT * FROM favourite ORDER BY sortOrder")
    protected abstract fun observeFavourites(): Flow<List<FavouriteItem>>

    @Query("SELECT * FROM drink")
    protected abstract fun observeDrinks(): Flow<List<Drink>>

    @Query("SELECT COUNT(*) FROM pour WHERE drinkId = :drinkId")
    protected abstract fun observePourCount(drinkId: UUID): Flow<Int>
}
