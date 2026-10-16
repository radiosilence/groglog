package cc.blit.groglog.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import androidx.room.Upsert
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Favourite
import cc.blit.groglog.model.FavouriteItem
import cc.blit.groglog.model.Pour
import java.time.Instant
import java.util.UUID

/** One-off reads and the row writes `Logbook` and the importer compose into transactions. Screens use `Queries`. */
@Dao
internal interface Rows {
    @Insert
    suspend fun insert(drink: Drink)

    @Insert
    suspend fun insert(favourite: Favourite)

    @Insert
    suspend fun insert(pour: Pour)

    @Update
    suspend fun update(drink: Drink)

    @Update
    suspend fun update(favourite: Favourite)

    @Update
    suspend fun update(pour: Pour)

    @Upsert
    suspend fun save(drink: Drink)

    @Upsert
    suspend fun save(day: Day)

    @Update
    suspend fun update(day: Day)

    @Delete
    suspend fun delete(drink: Drink): Int

    @Delete
    suspend fun delete(favourite: Favourite): Int

    @Delete
    suspend fun delete(pour: Pour): Int

    @Delete
    suspend fun delete(day: Day): Int

    @Query("SELECT * FROM drink WHERE id = :id")
    suspend fun drink(id: UUID): Drink?

    @Query("SELECT * FROM drink WHERE name = :name AND category = :category LIMIT 1")
    suspend fun drink(name: String, category: String): Drink?

    @Query("SELECT * FROM drink WHERE category = :category LIMIT 1")
    suspend fun drinkOfCategory(category: String): Drink?

    @Query("SELECT * FROM drink")
    suspend fun drinks(): List<Drink>

    @Query("SELECT * FROM drink ORDER BY name")
    suspend fun drinksByName(): List<Drink>

    @Query("SELECT COUNT(*) FROM drink")
    suspend fun drinkCount(): Int

    @Query("SELECT * FROM favourite")
    suspend fun favourites(): List<Favourite>

    @Query("SELECT * FROM favourite ORDER BY sortOrder")
    suspend fun favouritesInOrder(): List<Favourite>

    @Query("SELECT * FROM favourite WHERE drinkId = :drinkId AND vessel = :vessel AND volumeMl = :volumeMl LIMIT 1")
    suspend fun favourite(drinkId: UUID, vessel: String, volumeMl: Double): Favourite?

    @Query("SELECT COUNT(*) FROM favourite")
    suspend fun favouriteCount(): Int

    @Query("UPDATE favourite SET lastUsed = :lastUsed WHERE drinkId = :drinkId AND vessel = :vessel AND volumeMl = :volumeMl")
    suspend fun markUsed(drinkId: UUID, vessel: String, volumeMl: Double, lastUsed: Instant)

    /** The tiles an intent or a launcher shortcut would offer, most recently drunk first. */
    @Transaction
    @Query("SELECT * FROM favourite ORDER BY lastUsed DESC, sortOrder")
    suspend fun favouritesByUse(): List<FavouriteItem>

    @Query("SELECT * FROM pour")
    suspend fun pours(): List<Pour>

    @Query("SELECT COUNT(*) FROM pour")
    suspend fun pourCount(): Int

    @Query("SELECT id FROM pour")
    suspend fun pourIds(): List<UUID>

    @Query("SELECT DISTINCT day FROM pour")
    suspend fun daysWithPours(): List<Int>

    @Query("SELECT DISTINCT day FROM pour WHERE drinkId = :drinkId")
    suspend fun days(drinkId: UUID): List<Int>

    /** The most recently logged on a day, by insertion order: the rowid, since an id is random and a timestamp is when it was drunk. */
    @Query("SELECT * FROM pour WHERE day = :day ORDER BY rowid DESC LIMIT 1")
    suspend fun lastLogged(day: Int): Pour?

    @Transaction
    @Query("SELECT * FROM pour WHERE day BETWEEN :from AND :to ORDER BY day, timestamp")
    suspend fun entries(from: Int, to: Int): List<Entry>

    @Transaction
    @Query("SELECT * FROM pour ORDER BY day, timestamp")
    suspend fun entries(): List<Entry>

    @Transaction
    @Query("SELECT * FROM pour ORDER BY timestamp")
    suspend fun entriesByTime(): List<Entry>

    @Query("SELECT * FROM day WHERE number = :number")
    suspend fun day(number: Int): Day?

    @Query("SELECT * FROM day")
    suspend fun days(): List<Day>

    @Query("SELECT COUNT(*) FROM day")
    suspend fun dayCount(): Int
}
