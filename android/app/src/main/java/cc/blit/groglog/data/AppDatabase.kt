package cc.blit.groglog.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.Favourite
import cc.blit.groglog.model.Pour

/**
 * The SQLite database: schema, migrations, and where it lives. Writes go through `Logbook`.
 *
 * Version 1 is the iOS schema as it stands after its eighth migration, less the iCloud sync tables, which have no
 * counterpart here.
 */
@Database(entities = [Drink::class, Favourite::class, Pour::class, Day::class], version = 1)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun queries(): Queries
    internal abstract fun rows(): Rows

    companion object {
        /**
         * Append migrations; never edit a shipped one. The database is never erased to change schema, so there is no
         * destructive fallback.
         */
        val migrations: List<Migration> = listOf()

        fun onDisk(context: Context): AppDatabase =
            Room.databaseBuilder(context, AppDatabase::class.java, "groglog.sqlite")
                .addMigrations(*migrations.toTypedArray())
                .build()

        /** Tests and demo data. */
        fun inMemory(context: Context): AppDatabase =
            Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
                .addMigrations(*migrations.toTypedArray())
                .build()
    }
}
